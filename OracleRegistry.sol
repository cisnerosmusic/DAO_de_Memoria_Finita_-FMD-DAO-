// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title OracleRegistry
/// @author Ernesto Cisneros Cino — FMD-DAO OracleLayer
/// @notice Registro y gestión de reputación de proveedores de oráculo.
///         Punto de verdad sobre qué proveedores existen, cuál está activo,
///         cuál está en standby y cuáles están suspendidos o eliminados.
///
/// @dev ESTADOS DE PROVEEDOR:
///   INACTIVE   — registrado pero aún no ha rotado a activo
///   ACTIVE     — proveedor actual publicando datos
///   STANDBY    — proveedor de respaldo, toma el control ante STALE > 24h
///   SUSPENDED  — score < 3000 BPS, no elegible para rotación
///   ELIMINATED — score < 1000 BPS, removido permanentemente
///
/// @dev ROTACIÓN:
///   Ningún proveedor puede ser ACTIVE dos ciclos consecutivos.
///   eligibilityScore = score + waitBonus (máx +3000 BPS, +1000 por ciclo de espera)
///   El proveedor con mayor eligibilityScore pasa a ACTIVE.
///   El segundo pasa a STANDBY.
///
/// @dev SCORE:
///   Rango 0–10_000 BPS
///   Auto-confirmación:   +100 BPS
///   Disputa refutada:    -300 BPS
///   Dato STALE:          -50 BPS/hora (aplicado por OracleScheduler)
///   Suspensión:          < 3000 BPS
///   Eliminación:         < 1000 BPS

contract OracleRegistry is AccessControl, ReentrancyGuard {

    // ─── Roles ───────────────────────────────────────────────────────────────

    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");
    bytes32 public constant SCHEDULER_ROLE  = keccak256("SCHEDULER_ROLE");  // OracleScheduler
    bytes32 public constant DISPUTE_ROLE    = keccak256("DISPUTE_ROLE");    // OracleDispute

    // ─── Constants ───────────────────────────────────────────────────────────

    uint256 public constant BPS           = 10_000;
    uint256 public constant MAX_SCORE     = 10_000;
    uint256 public constant SUSPEND_THRESHOLD   = 3_000;
    uint256 public constant ELIMINATE_THRESHOLD = 1_000;
    uint256 public constant WAIT_BONUS_PER_CYCLE = 1_000; // +1000 BPS por ciclo de espera
    uint256 public constant MAX_WAIT_BONUS       = 3_000; // cap en +3000 BPS

    // Ajustes de score por evento
    uint256 public constant SCORE_CONFIRM   = 100;
    uint256 public constant SCORE_REFUTED   = 300;
    uint256 public constant SCORE_STALE_HR  = 50;

    // ─── Enums ───────────────────────────────────────────────────────────────

    enum ProviderStatus { INACTIVE, ACTIVE, STANDBY, SUSPENDED, ELIMINATED }

    // ─── Structs ─────────────────────────────────────────────────────────────

    struct Provider {
        bytes32        id;
        string         name;
        address        endpoint;
        uint256        score;
        ProviderStatus status;
        uint256        registeredAt;
        uint256        lastActiveAt;    // timestamp del último ciclo como ACTIVE
        uint256        cyclesWaiting;   // ciclos consecutivos sin ser ACTIVE
        uint256        totalConfirmed;
        uint256        totalRefuted;
        uint256        totalStale;
        bool           exists;
    }

    // ─── State ───────────────────────────────────────────────────────────────

    mapping(bytes32 => Provider) public providers;
    bytes32[]                    public providerIds;

    bytes32 public activeProviderId;
    bytes32 public standbyProviderId;
    uint256 public currentCycle;

    // Previene rotación doble en el mismo ciclo
    mapping(uint256 => bool) public rotatedThisCycle;

    // ─── Events ──────────────────────────────────────────────────────────────

    event ProviderRegistered(
        bytes32 indexed providerId,
        string  name,
        address endpoint,
        uint256 initialScore
    );

    event ProviderRotated(
        bytes32 indexed newActive,
        bytes32 indexed newStandby,
        bytes32 indexed prevActive,
        uint256 cycle
    );

    event ScoreAdjusted(
        bytes32 indexed providerId,
        uint256 scoreBefore,
        uint256 scoreAfter,
        string  reason
    );

    event ProviderSuspended(bytes32 indexed providerId, uint256 score);
    event ProviderEliminated(bytes32 indexed providerId, uint256 score);

    event StandbyActivated(
        bytes32 indexed providerId,
        bytes32 indexed replacedId,
        string  reason
    );

    // ─── Constructor ─────────────────────────────────────────────────────────

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(GOVERNANCE_ROLE,    admin);
    }

    // ─── Registration ────────────────────────────────────────────────────────

    /// @notice Registra un nuevo proveedor de oráculo
    /// @param providerId    Identificador único (bytes32, e.g. keccak256("CHAINLINK"))
    /// @param name          Nombre legible
    /// @param endpoint      Dirección del contrato o EOA del proveedor
    /// @param initialScore  Score inicial (0–10000 BPS)
    function registerProvider(
        bytes32        providerId,
        string calldata name,
        address        endpoint,
        uint256        initialScore
    ) external onlyRole(GOVERNANCE_ROLE) {
        require(!providers[providerId].exists,  "OracleRegistry: already registered");
        require(endpoint != address(0),         "OracleRegistry: zero address");
        require(initialScore <= MAX_SCORE,      "OracleRegistry: score exceeds max");

        providers[providerId] = Provider({
            id:             providerId,
            name:           name,
            endpoint:       endpoint,
            score:          initialScore,
            status:         ProviderStatus.INACTIVE,
            registeredAt:   block.timestamp,
            lastActiveAt:   0,
            cyclesWaiting:  0,
            totalConfirmed: 0,
            totalRefuted:   0,
            totalStale:     0,
            exists:         true
        });

        providerIds.push(providerId);
        emit ProviderRegistered(providerId, name, endpoint, initialScore);
    }

    // ─── Rotation ────────────────────────────────────────────────────────────

    /// @notice Ejecuta la rotación de ciclo: elige nuevo ACTIVE y STANDBY
    /// @dev Callable por SCHEDULER_ROLE o cualquier cuenta (fallback sin rol).
    ///      Ningún proveedor puede ser ACTIVE dos ciclos consecutivos.
    function rotateCycle()
        external
    {
        require(
            hasRole(SCHEDULER_ROLE, msg.sender) ||
            hasRole(GOVERNANCE_ROLE, msg.sender) ||
            true, // cualquiera puede llamar — el scheduler es el árbitro preferido
            "OracleRegistry: not authorized"
        );
        require(!rotatedThisCycle[currentCycle], "OracleRegistry: already rotated");

        rotatedThisCycle[currentCycle] = true;

        // Aumentar ciclesWaiting para todos los no-ACTIVE actuales
        bytes32 prevActive  = activeProviderId;
        bytes32 prevStandby = standbyProviderId;

        for (uint256 i = 0; i < providerIds.length; i++) {
            bytes32 pid = providerIds[i];
            Provider storage p = providers[pid];
            if (p.status == ProviderStatus.ACTIVE ||
                p.status == ProviderStatus.STANDBY ||
                p.status == ProviderStatus.INACTIVE) {
                if (pid != prevActive) {
                    p.cyclesWaiting++;
                }
            }
        }

        // Degradar el activo actual
        if (prevActive != bytes32(0)) {
            providers[prevActive].status        = ProviderStatus.INACTIVE;
            providers[prevActive].lastActiveAt  = block.timestamp;
            providers[prevActive].cyclesWaiting = 0; // reset: acaba de ser activo
        }
        if (prevStandby != bytes32(0)) {
            providers[prevStandby].status = ProviderStatus.INACTIVE;
        }

        // Elegir nuevo ACTIVE y STANDBY por eligibilityScore
        (bytes32 newActive, bytes32 newStandby) = _selectNextPair(prevActive);

        require(newActive != bytes32(0), "OracleRegistry: no eligible providers");

        providers[newActive].status   = ProviderStatus.ACTIVE;
        providers[newActive].cyclesWaiting = 0;
        activeProviderId = newActive;

        if (newStandby != bytes32(0)) {
            providers[newStandby].status = ProviderStatus.STANDBY;
            standbyProviderId = newStandby;
        } else {
            standbyProviderId = bytes32(0);
        }

        currentCycle++;
        emit ProviderRotated(newActive, newStandby, prevActive, currentCycle);
    }

    /// @notice Activa el standby cuando el activo tiene STALE > 24h
    function activateStandby(string calldata reason)
        external onlyRole(SCHEDULER_ROLE)
    {
        require(standbyProviderId != bytes32(0), "OracleRegistry: no standby");

        bytes32 prev    = activeProviderId;
        bytes32 standby = standbyProviderId;

        providers[prev].status    = ProviderStatus.SUSPENDED; // STALE activo → suspendido
        providers[standby].status = ProviderStatus.ACTIVE;
        activeProviderId          = standby;
        standbyProviderId         = bytes32(0);

        emit StandbyActivated(standby, prev, reason);
    }

    // ─── Score Adjustment ────────────────────────────────────────────────────

    /// @notice Ajusta el score de un proveedor
    /// @param providerId  ID del proveedor
    /// @param delta       Ajuste en BPS (positivo = boost, negativo = penalización)
    /// @param reason      Razón del ajuste ("CONFIRMED", "REFUTED", "STALE", etc.)
    function adjustScore(
        bytes32        providerId,
        int256         delta,
        string calldata reason
    ) external {
        require(
            hasRole(DISPUTE_ROLE,    msg.sender) ||
            hasRole(SCHEDULER_ROLE,  msg.sender) ||
            hasRole(GOVERNANCE_ROLE, msg.sender),
            "OracleRegistry: not authorized"
        );
        require(providers[providerId].exists, "OracleRegistry: not found");

        Provider storage p  = providers[providerId];
        uint256 before      = p.score;

        if (delta > 0) {
            uint256 boost = uint256(delta);
            p.score = p.score + boost > MAX_SCORE ? MAX_SCORE : p.score + boost;
            p.totalConfirmed++;
        } else if (delta < 0) {
            uint256 penalty = uint256(-delta);
            p.score = p.score > penalty ? p.score - penalty : 0;
            p.totalRefuted++;
        }

        emit ScoreAdjusted(providerId, before, p.score, reason);

        // Verificar umbrales de suspensión / eliminación
        _checkThresholds(providerId);
    }

    /// @notice Registra un evento STALE y aplica penalización horaria
    function recordStale(bytes32 providerId, uint256 staleHours)
        external onlyRole(SCHEDULER_ROLE)
    {
        require(providers[providerId].exists, "OracleRegistry: not found");

        Provider storage p = providers[providerId];
        uint256 before     = p.score;
        uint256 penalty    = SCORE_STALE_HR * staleHours;

        p.score    = p.score > penalty ? p.score - penalty : 0;
        p.totalStale++;

        emit ScoreAdjusted(providerId, before, p.score, "STALE");
        _checkThresholds(providerId);
    }

    // ─── View ─────────────────────────────────────────────────────────────────

    /// @notice Score de elegibilidad para la próxima rotación
    /// @dev eligibilityScore = score + min(cyclesWaiting × 1000, 3000)
    function eligibilityScore(bytes32 providerId)
        external view returns (uint256)
    {
        Provider storage p = providers[providerId];
        if (!p.exists) return 0;
        if (p.status == ProviderStatus.SUSPENDED ||
            p.status == ProviderStatus.ELIMINATED) return 0;

        uint256 bonus = p.cyclesWaiting * WAIT_BONUS_PER_CYCLE;
        if (bonus > MAX_WAIT_BONUS) bonus = MAX_WAIT_BONUS;
        return p.score + bonus;
    }

    /// @notice Datos completos de un proveedor
    function getProvider(bytes32 providerId)
        external view returns (Provider memory)
    {
        return providers[providerId];
    }

    /// @notice Lista completa de IDs de proveedores
    function getProviderIds() external view returns (bytes32[] memory) {
        return providerIds;
    }

    /// @notice Número de proveedores registrados
    function getProviderCount() external view returns (uint256) {
        return providerIds.length;
    }

    // ─── Internal ────────────────────────────────────────────────────────────

    /// @notice Selecciona el par (newActive, newStandby) por eligibilityScore
    /// @dev El prevActive queda excluido (no puede repetir ciclo consecutivo)
    function _selectNextPair(bytes32 excluded)
        internal view
        returns (bytes32 first, bytes32 second)
    {
        uint256 firstScore  = 0;
        uint256 secondScore = 0;

        for (uint256 i = 0; i < providerIds.length; i++) {
            bytes32 pid = providerIds[i];
            if (pid == excluded) continue;

            Provider storage p = providers[pid];
            if (p.status == ProviderStatus.SUSPENDED ||
                p.status == ProviderStatus.ELIMINATED) continue;

            uint256 bonus = p.cyclesWaiting * WAIT_BONUS_PER_CYCLE;
            if (bonus > MAX_WAIT_BONUS) bonus = MAX_WAIT_BONUS;
            uint256 es = p.score + bonus;

            if (es > firstScore) {
                second      = first;
                secondScore = firstScore;
                first       = pid;
                firstScore  = es;
            } else if (es > secondScore) {
                second      = pid;
                secondScore = es;
            }
        }
    }

    /// @notice Verifica umbrales y cambia estado si corresponde
    function _checkThresholds(bytes32 providerId) internal {
        Provider storage p = providers[providerId];

        if (p.score < ELIMINATE_THRESHOLD) {
            p.status = ProviderStatus.ELIMINATED;
            emit ProviderEliminated(providerId, p.score);
        } else if (p.score < SUSPEND_THRESHOLD &&
                   p.status != ProviderStatus.ELIMINATED) {
            p.status = ProviderStatus.SUSPENDED;
            emit ProviderSuspended(providerId, p.score);
        }
    }
}
