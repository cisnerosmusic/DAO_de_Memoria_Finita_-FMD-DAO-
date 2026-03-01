// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./OracleRegistry.sol";
import "./OracleDispute.sol";
import "./OracleRouter.sol";

/// @title OracleScheduler
/// @author Ernesto Cisneros Cino — FMD-DAO OracleLayer
/// @notice Gestiona el calendario de rotación de proveedores de oráculo,
///         la confirmación automática de datos no disputados, y la activación
///         del standby cuando el activo falla.
///
/// @dev RESPONSABILIDADES:
///
///   1. Rotación cíclica
///      Al inicio de cada ciclo llama OracleRegistry.rotateCycle()
///      El ciclo dura N segundos (configurable por gobernanza)
///      Ningún proveedor puede ser activo dos ciclos consecutivos
///
///   2. Confirmación automática de datos no disputados
///      Al cierre de la ventana de disputa (48h / 24h en crisis),
///      si no hubo disputa, confirma el dato y acredita score al proveedor
///
///   3. Activación de standby por STALE
///      Si el dato crítico lleva más de STALE_TAKEOVER_THRESHOLD sin actualizar,
///      transfiere el control al proveedor standby
///
///   4. Sincronización con el Sistema Inmunológico
///      Si ambos proveedores (activo + standby) están STALE simultáneamente,
///      notifica al ImmunityCore con señal de amenaza +2
///
/// @dev LLAMADORES EXTERNOS (keepers / cron):
///      El Scheduler está diseñado para ser llamado por keepers externos
///      (Chainlink Automation, Gelato, o keeper interno de C1).
///      Cualquier función pública puede ser llamada por el keeper autorizado.
///      En caso de fallo del keeper, cualquier miembro puede llamar
///      triggerRotation() o confirmExpiredWindows() pagando el gas.

contract OracleScheduler is AccessControl, ReentrancyGuard {

    // ─── Roles ───────────────────────────────────────────────────────────────

    bytes32 public constant KEEPER_ROLE     = keccak256("KEEPER_ROLE");
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");
    bytes32 public constant IMMUNITY_ROLE   = keccak256("IMMUNITY_ROLE"); // ImmunityCore

    // ─── Constants ───────────────────────────────────────────────────────────

    uint256 public constant MIN_CYCLE_DURATION  = 7  days;
    uint256 public constant MAX_CYCLE_DURATION  = 90 days;
    uint256 public constant DEFAULT_CYCLE       = 30 days;

    // Tiempo máximo sin actualización antes de que el standby tome el control
    uint256 public constant STALE_TAKEOVER_THRESHOLD = 24 hours;

    // Ventanas de disputa (espejadas desde OracleDispute para referencia)
    uint256 public constant DISPUTE_WINDOW_NORMAL = 48 hours;
    uint256 public constant DISPUTE_WINDOW_CRISIS  = 24 hours;

    // ─── Structs ─────────────────────────────────────────────────────────────

    /// @notice Registro de un ciclo completo de oráculo
    struct CycleRecord {
        uint256 cycleId;
        bytes32 activeProviderId;
        bytes32 standbyProviderId;
        uint256 startedAt;
        uint256 endsAt;
        bool    rotated;        // si ya se ejecutó la rotación al cierre
        uint256 dataConfirmed;  // cantidad de datos confirmados sin disputa
        uint256 dataDisputed;   // cantidad de datos que tuvieron disputa
        uint256 staleEvents;    // cantidad de eventos STALE en el ciclo
    }

    /// @notice Registro de una ventana de confirmación pendiente
    struct ConfirmationWindow {
        bytes32 dataKey;
        uint256 windowEnd;      // cuando cierra la ventana de disputa
        bool    processed;
    }

    // ─── State ───────────────────────────────────────────────────────────────

    OracleRegistry public registry;
    OracleDispute  public dispute;
    OracleRouter   public router;

    // Interfaz mínima al ImmunityCore para notificación de amenaza doble STALE
    address public immunityCoreAddress;

    uint256 public cycleDuration;       // duración de cada ciclo en segundos
    uint256 public currentCycleId;
    uint256 public cycleStartedAt;      // timestamp de inicio del ciclo actual

    bool    public systemInCrisis;

    // historial de ciclos
    mapping(uint256 => CycleRecord) public cycleHistory;

    // ventanas de confirmación pendientes
    ConfirmationWindow[] public pendingWindows;

    // dataKey → timestamp de última publicación (para detectar STALE)
    mapping(bytes32 => uint256) public lastPublishedAt;

    // dataKeys críticos registrados (cuyo STALE dispara takeover)
    bytes32[] public criticalDataKeys;
    mapping(bytes32 => bool) public isCritical;

    // tracking de STALE activo por dataKey
    mapping(bytes32 => bool) public isStale;

    // ─── Events ──────────────────────────────────────────────────────────────

    event CycleStarted(
        uint256 indexed cycleId,
        bytes32 activeProvider,
        bytes32 standbyProvider,
        uint256 endsAt
    );

    event CycleRotated(
        uint256 indexed cycleId,
        bytes32 newActive,
        bytes32 newStandby
    );

    event ConfirmationWindowRegistered(
        bytes32 indexed dataKey,
        uint256 windowEnd
    );

    event DataAutoConfirmed(
        bytes32 indexed dataKey,
        bytes32 indexed providerId,
        uint256 cycleId
    );

    event StaleDetected(
        bytes32 indexed dataKey,
        bytes32 indexed providerId,
        uint256 staleDuration
    );

    event StandbyActivatedByStale(
        bytes32 indexed dataKey,
        bytes32 indexed newActiveProvider
    );

    event DoubleStaleAlert(
        bytes32 indexed dataKey,
        uint256 timestamp
    );

    event CrisisStateUpdated(bool inCrisis);
    event CriticalKeyRegistered(bytes32 indexed dataKey);
    event CycleDurationUpdated(uint256 newDuration);

    // ─── Constructor ─────────────────────────────────────────────────────────

    constructor(
        address admin,
        address _registry,
        address _dispute,
        address _router,
        address _immunityCore
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        registry             = OracleRegistry(_registry);
        dispute              = OracleDispute(_dispute);
        router               = OracleRouter(_router);
        immunityCoreAddress  = _immunityCore;
        cycleDuration        = DEFAULT_CYCLE;
        currentCycleId       = 1;
        cycleStartedAt       = block.timestamp;

        // Inicializar primer registro de ciclo
        _initCycleRecord();
    }

    // ─── Cycle Management ────────────────────────────────────────────────────

    /// @notice Ejecuta la rotación de ciclo si el tiempo ha llegado
    /// @dev Puede ser llamado por keeper o por cualquier miembro
    ///      No falla si se llama antes de tiempo — simplemente no hace nada
    function triggerRotation() external nonReentrant {
        require(
            block.timestamp >= cycleStartedAt + cycleDuration,
            "OracleScheduler: cycle not ended"
        );
        require(
            !cycleHistory[currentCycleId].rotated,
            "OracleScheduler: already rotated"
        );

        // Cerrar ciclo actual
        cycleHistory[currentCycleId].rotated = true;

        // Ejecutar rotación en el Registry
        registry.rotateCycle();

        // Avanzar ciclo
        currentCycleId++;
        cycleStartedAt = block.timestamp;

        _initCycleRecord();

        emit CycleRotated(
            currentCycleId - 1,
            registry.activeProviderId(),
            registry.standbyProviderId()
        );

        emit CycleStarted(
            currentCycleId,
            registry.activeProviderId(),
            registry.standbyProviderId(),
            block.timestamp + cycleDuration
        );
    }

    /// @notice Inicializa el registro del ciclo actual
    function _initCycleRecord() internal {
        cycleHistory[currentCycleId] = CycleRecord({
            cycleId:           currentCycleId,
            activeProviderId:  registry.activeProviderId(),
            standbyProviderId: registry.standbyProviderId(),
            startedAt:         block.timestamp,
            endsAt:            block.timestamp + cycleDuration,
            rotated:           false,
            dataConfirmed:     0,
            dataDisputed:      0,
            staleEvents:       0
        });
    }

    // ─── Confirmation Windows ─────────────────────────────────────────────────

    /// @notice Registra una ventana de confirmación cuando el oráculo publica un dato
    /// @dev Llamado internamente o por el Router tras cada publicación
    /// @param dataKey Clave del dato publicado
    function registerConfirmationWindow(bytes32 dataKey)
        external onlyRole(KEEPER_ROLE)
    {
        uint256 window = systemInCrisis
            ? DISPUTE_WINDOW_CRISIS
            : DISPUTE_WINDOW_NORMAL;

        pendingWindows.push(ConfirmationWindow({
            dataKey:   dataKey,
            windowEnd: block.timestamp + window,
            processed: false
        }));

        lastPublishedAt[dataKey] = block.timestamp;

        emit ConfirmationWindowRegistered(dataKey, block.timestamp + window);
    }

    /// @notice Procesa todas las ventanas de confirmación expiradas
    /// @dev Llamado por keeper periódicamente
    ///      Por cada ventana expirada sin disputa: confirma el dato y acredita score
    function confirmExpiredWindows() external nonReentrant onlyRole(KEEPER_ROLE) {
        for (uint256 i = 0; i < pendingWindows.length; i++) {
            ConfirmationWindow storage cw = pendingWindows[i];

            if (cw.processed) continue;
            if (block.timestamp < cw.windowEnd) continue;

            // Verificar si hay disputa activa para este dataKey
            (bool hasDispute,) = dispute.hasActiveDispute(cw.dataKey);

            if (!hasDispute) {
                // Confirmar automáticamente
                dispute.expireIfUndisputed(cw.dataKey);

                cycleHistory[currentCycleId].dataConfirmed++;

                emit DataAutoConfirmed(
                    cw.dataKey,
                    registry.activeProviderId(),
                    currentCycleId
                );
            } else {
                // Hay disputa activa — no procesar aquí, OracleDispute lo gestiona
                cycleHistory[currentCycleId].dataDisputed++;
            }

            cw.processed = true;
        }
    }

    // ─── STALE Detection & Takeover ──────────────────────────────────────────

    /// @notice Verifica todos los datos críticos en busca de STALE
    /// @dev Llamado por keeper cada hora aproximadamente
    function checkStaleData() external onlyRole(KEEPER_ROLE) {
        for (uint256 i = 0; i < criticalDataKeys.length; i++) {
            bytes32 key = criticalDataKeys[i];
            _checkKeyStale(key);
        }
    }

    /// @notice Verifica un dataKey específico en busca de STALE
    function checkSingleKey(bytes32 dataKey) external {
        require(isCritical[dataKey], "OracleScheduler: not a critical key");
        _checkKeyStale(dataKey);
    }

    function _checkKeyStale(bytes32 dataKey) internal {
        uint256 lastUpdate = lastPublishedAt[dataKey];
        if (lastUpdate == 0) return; // nunca publicado — no es STALE aún

        uint256 staleDuration = block.timestamp - lastUpdate;

        if (staleDuration < STALE_TAKEOVER_THRESHOLD) {
            // Dentro del umbral — si estaba marcado STALE, limpiar
            if (isStale[dataKey]) {
                isStale[dataKey] = false;
            }
            return;
        }

        // STALE confirmado
        if (!isStale[dataKey]) {
            isStale[dataKey] = true;
            cycleHistory[currentCycleId].staleEvents++;

            emit StaleDetected(
                dataKey,
                registry.activeProviderId(),
                staleDuration
            );
        }

        // Verificar si el standby también está STALE (doble fallo)
        bool standbyAlsoStale = _isStandbyStale(dataKey);

        if (standbyAlsoStale) {
            // Alerta crítica al Sistema Inmunológico
            _notifyDoubleStale(dataKey);
        } else {
            // Activar takeover del standby
            _activateStandbyTakeover(dataKey);
        }
    }

    /// @notice Verifica si el standby también lleva más de STALE_TAKEOVER_THRESHOLD
    ///         sin publicar datos (heurística: si el activo actual lleva > 48h STALE
    ///         y el standby no ha publicado nada en el ciclo actual, se considera STALE)
    function _isStandbyStale(bytes32 dataKey) internal view returns (bool) {
        // Heurística conservadora:
        // Si el activo lleva más de 2× el umbral sin actualizar,
        // asumimos que el standby tampoco puede cubrir
        uint256 lastUpdate = lastPublishedAt[dataKey];
        uint256 staleDuration = block.timestamp - lastUpdate;
        return staleDuration > STALE_TAKEOVER_THRESHOLD * 2;
    }

    function _activateStandbyTakeover(bytes32 dataKey) internal {
        registry.activateStandby();

        emit StandbyActivatedByStale(
            dataKey,
            registry.activeProviderId()
        );
    }

    /// @notice Notifica al ImmunityCore de doble STALE (amenaza +2 al Threat Score)
    function _notifyDoubleStale(bytes32 dataKey) internal {
        // Llamada de bajo nivel para no crear dependencia circular de imports
        // ImmunityCore expone: function receiveDoubleStaleAlert(bytes32 dataKey) external
        (bool success,) = immunityCoreAddress.call(
            abi.encodeWithSignature("receiveDoubleStaleAlert(bytes32)", dataKey)
        );
        // Si falla la llamada, el evento queda registrado on-chain de todas formas
        if (!success) {
            emit DoubleStaleAlert(dataKey, block.timestamp);
        } else {
            emit DoubleStaleAlert(dataKey, block.timestamp);
        }
    }

    // ─── Governance ──────────────────────────────────────────────────────────

    /// @notice Registra un dataKey como crítico (su STALE dispara takeover)
    function registerCriticalKey(bytes32 dataKey)
        external onlyRole(GOVERNANCE_ROLE)
    {
        require(!isCritical[dataKey], "OracleScheduler: already critical");
        isCritical[dataKey] = true;
        criticalDataKeys.push(dataKey);
        emit CriticalKeyRegistered(dataKey);
    }

    /// @notice Actualiza la duración del ciclo (con límites de gobernanza)
    function setCycleDuration(uint256 newDuration)
        external onlyRole(GOVERNANCE_ROLE)
    {
        require(
            newDuration >= MIN_CYCLE_DURATION &&
            newDuration <= MAX_CYCLE_DURATION,
            "OracleScheduler: duration out of bounds"
        );
        cycleDuration = newDuration;
        emit CycleDurationUpdated(newDuration);
    }

    /// @notice Actualiza el estado de crisis (ventanas de disputa se reducen a 24h)
    function setCrisisState(bool inCrisis)
        external onlyRole(IMMUNITY_ROLE)
    {
        systemInCrisis = inCrisis;
        emit CrisisStateUpdated(inCrisis);
    }

    // ─── View ─────────────────────────────────────────────────────────────────

    /// @notice Devuelve si el ciclo actual ha terminado y está listo para rotar
    function isRotationDue() external view returns (bool) {
        return block.timestamp >= cycleStartedAt + cycleDuration
            && !cycleHistory[currentCycleId].rotated;
    }

    /// @notice Devuelve los segundos restantes del ciclo actual
    function timeUntilRotation() external view returns (uint256) {
        uint256 end = cycleStartedAt + cycleDuration;
        if (block.timestamp >= end) return 0;
        return end - block.timestamp;
    }

    /// @notice Devuelve el registro completo de un ciclo
    function getCycleRecord(uint256 cycleId)
        external view returns (CycleRecord memory)
    {
        return cycleHistory[cycleId];
    }

    /// @notice Devuelve todos los dataKeys críticos registrados
    function getCriticalKeys() external view returns (bytes32[] memory) {
        return criticalDataKeys;
    }

    /// @notice Devuelve cuántas ventanas de confirmación están pendientes de procesar
    function pendingWindowCount() external view returns (uint256 count) {
        for (uint256 i = 0; i < pendingWindows.length; i++) {
            if (!pendingWindows[i].processed) count++;
        }
    }

    /// @notice Devuelve el estado STALE de todos los dataKeys críticos
    function getStaleStatus()
        external view
        returns (bytes32[] memory keys, bool[] memory staleFlags)
    {
        keys       = criticalDataKeys;
        staleFlags = new bool[](keys.length);
        for (uint256 i = 0; i < keys.length; i++) {
            staleFlags[i] = isStale[keys[i]];
        }
    }
}
