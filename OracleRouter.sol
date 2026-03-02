// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./OracleRegistry.sol";

/// @title OracleRouter
/// @author Ernesto Cisneros Cino — FMD-DAO OracleLayer
/// @notice Punto único de consulta de datos externos para todos los módulos.
///         Gestiona TTL, flags de estado y el ciclo de vida de cada dataKey.
///
/// @dev ESTADOS DE UN DATO:
///   FRESH    — publicado dentro del TTL, sin disputa activa
///   STALE    — TTL vencido sin actualización
///   DISPUTED — hay una disputa abierta (OracleDispute la congela)
///   FROZEN   — congelado por resolución DRAW o exploit detectado
///
/// @dev FLUJO NORMAL:
///   1. Proveedor ACTIVE llama publishData(dataKey, value)
///   2. Dato queda FRESH con TTL configurado por dataKey
///   3. Si TTL vence → OracleScheduler marca STALE
///   4. Si se abre disputa → OracleDispute llama freezeData()
///   5. Disputa resuelta → OracleDispute llama resolveData()
///
/// @dev LECTURA:
///   getData(dataKey)   → (value, status, timestamp, providerId)
///   getFresh(dataKey)  → revierte si el dato no está FRESH
///   isFresh(dataKey)   → bool sin revertir
///
/// @dev TTL POR DEFECTO:
///   Datos críticos (marcados por Governance): 6 horas
///   Datos estándar:                           24 horas
///   En crisis (setCrisisState=true):          TTL se reduce a la mitad

contract OracleRouter is AccessControl, ReentrancyGuard {

    // ─── Roles ───────────────────────────────────────────────────────────────

    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");
    bytes32 public constant WRITER_ROLE     = keccak256("WRITER_ROLE");     // proveedores activos
    bytes32 public constant DISPUTE_ROLE    = keccak256("DISPUTE_ROLE");    // OracleDispute
    bytes32 public constant SCHEDULER_ROLE  = keccak256("SCHEDULER_ROLE");  // OracleScheduler

    // ─── Constants ───────────────────────────────────────────────────────────

    uint256 public constant DEFAULT_TTL          = 24 hours;
    uint256 public constant CRITICAL_TTL         = 6 hours;
    uint256 public constant CRISIS_TTL_DIVISOR   = 2;   // TTL / 2 en crisis

    // ─── Enums ───────────────────────────────────────────────────────────────

    enum DataStatus { FRESH, STALE, DISPUTED, FROZEN }

    // ─── Structs ─────────────────────────────────────────────────────────────

    struct DataEntry {
        bytes    value;
        DataStatus status;
        uint256  publishedAt;
        uint256  ttl;           // TTL efectivo en segundos al momento de publicación
        bytes32  providerId;
        bool     critical;
        bool     exists;
    }

    struct DataConfig {
        uint256 customTtl;      // 0 = usar default
        bool    critical;
        bool    configured;
    }

    // ─── State ───────────────────────────────────────────────────────────────

    OracleRegistry public registry;

    mapping(bytes32 => DataEntry)  public data;
    mapping(bytes32 => DataConfig) public dataConfigs;
    bytes32[]                      public dataKeys;

    bool    public crisisMode;

    // Último dato válido por key (para fallback ante STALE/DISPUTED)
    mapping(bytes32 => bytes)   public lastValidValue;
    mapping(bytes32 => uint256) public lastValidAt;

    // ─── Events ──────────────────────────────────────────────────────────────

    event DataPublished(
        bytes32 indexed dataKey,
        bytes32 indexed providerId,
        uint256 ttl,
        uint256 timestamp
    );

    event DataStale(
        bytes32 indexed dataKey,
        bytes32 indexed providerId,
        uint256 staleSince
    );

    event DataFrozen(
        bytes32 indexed dataKey,
        string  reason
    );

    event DataResolved(
        bytes32 indexed dataKey,
        bytes   newValue,
        string  resolution  // "CONFIRMED" | "REFUTED" | "RESTORED"
    );

    event DataConfigured(
        bytes32 indexed dataKey,
        uint256 customTtl,
        bool    critical
    );

    event CrisisModeChanged(bool active);

    // ─── Constructor ─────────────────────────────────────────────────────────

    constructor(address admin, address _registry) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(GOVERNANCE_ROLE,    admin);
        registry = OracleRegistry(_registry);
    }

    // ─── Publish ─────────────────────────────────────────────────────────────

    /// @notice Publica un dato nuevo o actualiza uno existente
    /// @dev Solo el proveedor ACTIVE puede publicar.
    ///      Verifica que msg.sender sea el endpoint del proveedor activo.
    /// @param dataKey Identificador del dato (e.g. keccak256("GINI_C1"))
    /// @param value   Valor codificado (ABI encoded)
    function publishData(bytes32 dataKey, bytes calldata value)
        external onlyRole(WRITER_ROLE) nonReentrant
    {
        // Verificar que el caller es el proveedor activo
        bytes32 activeId = registry.activeProviderId();
        require(activeId != bytes32(0), "OracleRouter: no active provider");

        OracleRegistry.Provider memory active = registry.getProvider(activeId);
        require(
            active.endpoint == msg.sender ||
            hasRole(GOVERNANCE_ROLE, msg.sender), // governance puede publicar en tests
            "OracleRouter: caller is not active provider"
        );

        // No publicar sobre datos disputados — deben resolverse primero
        if (data[dataKey].exists) {
            require(
                data[dataKey].status != DataStatus.DISPUTED,
                "OracleRouter: data under dispute"
            );
        }

        uint256 effectiveTtl = _effectiveTtl(dataKey);

        // Si es una key nueva, registrarla
        if (!data[dataKey].exists) {
            dataKeys.push(dataKey);
        } else if (data[dataKey].status == DataStatus.FRESH) {
            // Guardar como último valor válido antes de reemplazar
            lastValidValue[dataKey] = data[dataKey].value;
            lastValidAt[dataKey]    = data[dataKey].publishedAt;
        }

        data[dataKey] = DataEntry({
            value:       value,
            status:      DataStatus.FRESH,
            publishedAt: block.timestamp,
            ttl:         effectiveTtl,
            providerId:  activeId,
            critical:    dataConfigs[dataKey].critical,
            exists:      true
        });

        // También actualizar lastValid con el nuevo valor
        lastValidValue[dataKey] = value;
        lastValidAt[dataKey]    = block.timestamp;

        emit DataPublished(dataKey, activeId, effectiveTtl, block.timestamp);
    }

    // ─── Stale Management ────────────────────────────────────────────────────

    /// @notice Marca un dato como STALE si su TTL venció
    /// @dev Callable por OracleScheduler o cualquier cuenta.
    function markStale(bytes32 dataKey) external {
        require(data[dataKey].exists,                    "OracleRouter: key not found");
        require(data[dataKey].status == DataStatus.FRESH, "OracleRouter: not fresh");
        require(
            block.timestamp >= data[dataKey].publishedAt + data[dataKey].ttl,
            "OracleRouter: TTL not expired"
        );

        data[dataKey].status = DataStatus.STALE;
        emit DataStale(dataKey, data[dataKey].providerId, block.timestamp);
    }

    // ─── Dispute Interface ────────────────────────────────────────────────────

    /// @notice Congela un dato mientras hay una disputa activa
    /// @dev Solo OracleDispute puede llamar esta función.
    function freezeData(bytes32 dataKey)
        external onlyRole(DISPUTE_ROLE)
    {
        require(data[dataKey].exists, "OracleRouter: key not found");
        require(
            data[dataKey].status == DataStatus.FRESH ||
            data[dataKey].status == DataStatus.STALE,
            "OracleRouter: cannot freeze in current status"
        );

        data[dataKey].status = DataStatus.DISPUTED;
        emit DataFrozen(dataKey, "DISPUTE_OPENED");
    }

    /// @notice Resuelve un dato congelado tras el resultado de la disputa
    /// @param dataKey    Clave del dato
    /// @param newValue   Valor a establecer (el original si CONFIRMED, el alternativo si REFUTED)
    /// @param resolution "CONFIRMED" | "REFUTED" | "DRAW"
    function resolveData(
        bytes32        dataKey,
        bytes calldata newValue,
        string calldata resolution
    ) external onlyRole(DISPUTE_ROLE) {
        require(data[dataKey].exists,                       "OracleRouter: key not found");
        require(data[dataKey].status == DataStatus.DISPUTED, "OracleRouter: not disputed");

        bytes32 kResolution = keccak256(bytes(resolution));

        if (kResolution == keccak256("DRAW")) {
            // DRAW → dato queda FROZEN indefinidamente, usar lastValidValue
            data[dataKey].status = DataStatus.FROZEN;
            emit DataFrozen(dataKey, "DISPUTE_DRAW");
        } else {
            // CONFIRMED o REFUTED → publicar nuevo valor
            data[dataKey].value       = newValue;
            data[dataKey].status      = DataStatus.FRESH;
            data[dataKey].publishedAt = block.timestamp;
            data[dataKey].ttl         = _effectiveTtl(dataKey);

            lastValidValue[dataKey] = newValue;
            lastValidAt[dataKey]    = block.timestamp;

            emit DataResolved(dataKey, newValue, resolution);
        }
    }

    // ─── Crisis Mode ──────────────────────────────────────────────────────────

    /// @notice Activa o desactiva el modo crisis (reduce TTL a la mitad)
    /// @dev Llamado por ImmunityCore vía call de bajo nivel.
    function setCrisisState(bool active) external {
        require(
            hasRole(GOVERNANCE_ROLE, msg.sender) ||
            hasRole(SCHEDULER_ROLE,  msg.sender),
            "OracleRouter: not authorized"
        );
        crisisMode = active;
        emit CrisisModeChanged(active);
    }

    // ─── Configuration ────────────────────────────────────────────────────────

    /// @notice Configura TTL y criticidad de una dataKey
    function configureKey(bytes32 dataKey, uint256 customTtl, bool critical)
        external onlyRole(GOVERNANCE_ROLE)
    {
        dataConfigs[dataKey] = DataConfig({
            customTtl:  customTtl,
            critical:   critical,
            configured: true
        });

        // Actualizar la entrada existente si hay una
        if (data[dataKey].exists) {
            data[dataKey].critical = critical;
        }

        emit DataConfigured(dataKey, customTtl, critical);
    }

    // ─── Read Interface ───────────────────────────────────────────────────────

    /// @notice Lee un dato — devuelve el último válido si está STALE/DISPUTED/FROZEN
    /// @return value       Valor actual (o último válido si no está FRESH)
    /// @return status      Estado actual del dato
    /// @return publishedAt Timestamp de publicación
    /// @return providerId  ID del proveedor que lo publicó
    /// @return isCurrent   true si el valor devuelto es FRESH
    function getData(bytes32 dataKey)
        external view
        returns (
            bytes memory value,
            DataStatus   status,
            uint256      publishedAt,
            bytes32      providerId,
            bool         isCurrent
        )
    {
        require(data[dataKey].exists, "OracleRouter: key not found");

        DataEntry storage entry = data[dataKey];
        status      = entry.status;
        publishedAt = entry.publishedAt;
        providerId  = entry.providerId;

        if (entry.status == DataStatus.FRESH) {
            // Verificar que el TTL no haya vencido in-memory
            bool ttlExpired = block.timestamp >= entry.publishedAt + entry.ttl;
            if (ttlExpired) {
                value     = lastValidValue[dataKey];
                isCurrent = false;
                status    = DataStatus.STALE;
            } else {
                value     = entry.value;
                isCurrent = true;
            }
        } else {
            // STALE / DISPUTED / FROZEN → devolver último válido
            value     = lastValidValue[dataKey];
            isCurrent = false;
        }
    }

    /// @notice Lee un dato y revierte si no está FRESH
    function getFresh(bytes32 dataKey)
        external view returns (bytes memory value, bytes32 providerId)
    {
        require(data[dataKey].exists, "OracleRouter: key not found");
        DataEntry storage entry = data[dataKey];
        require(entry.status == DataStatus.FRESH, "OracleRouter: data not fresh");
        require(
            block.timestamp < entry.publishedAt + entry.ttl,
            "OracleRouter: TTL expired"
        );
        return (entry.value, entry.providerId);
    }

    /// @notice Verifica si un dato está FRESH sin revertir
    function isFresh(bytes32 dataKey) external view returns (bool) {
        if (!data[dataKey].exists) return false;
        DataEntry storage entry = data[dataKey];
        return entry.status == DataStatus.FRESH &&
               block.timestamp < entry.publishedAt + entry.ttl;
    }

    /// @notice Verifica si un dato está STALE (TTL vencido o marcado explícitamente)
    function isStale(bytes32 dataKey) external view returns (bool) {
        if (!data[dataKey].exists) return false;
        DataEntry storage entry = data[dataKey];
        if (entry.status == DataStatus.STALE) return true;
        if (entry.status == DataStatus.FRESH) {
            return block.timestamp >= entry.publishedAt + entry.ttl;
        }
        return false;
    }

    /// @notice Lista de todas las dataKeys registradas
    function getDataKeys() external view returns (bytes32[] memory) {
        return dataKeys;
    }

    /// @notice Número total de dataKeys
    function getDataKeyCount() external view returns (uint256) {
        return dataKeys.length;
    }

    // ─── Internal ────────────────────────────────────────────────────────────

    /// @notice Calcula el TTL efectivo para una dataKey
    function _effectiveTtl(bytes32 dataKey) internal view returns (uint256 ttl) {
        DataConfig storage cfg = dataConfigs[dataKey];

        if (cfg.configured && cfg.customTtl > 0) {
            ttl = cfg.customTtl;
        } else if (cfg.critical) {
            ttl = CRITICAL_TTL;
        } else {
            ttl = DEFAULT_TTL;
        }

        // En crisis: reducir TTL a la mitad
        if (crisisMode) ttl = ttl / CRISIS_TTL_DIVISOR;

        // Mínimo absoluto: 1 hora
        if (ttl < 1 hours) ttl = 1 hours;
    }
}
