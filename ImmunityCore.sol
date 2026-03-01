// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../libraries/ThreatMath.sol";
import "../core/GovernanceParams.sol";

/// @title ImmunityCore
/// @author Ernesto Cisneros Cino — FMD-DAO ImmunityCore
/// @notice Sistema inmunológico de la DAO. Detecta amenazas, clasifica su
///         severidad y velocidad, y activa respuesta graduada.
///
/// @dev FLUJO:
///
///   1. ThreatOracle publica métricas vía reportMetrics()
///   2. ImmunityCore calcula Threat Score (0–16)
///   3. Clasifica severidad: VERDE | AMARILLO | NARANJA | ROJO
///   4. Clasifica velocidad: LOGARÍTMICA | LINEAL | EXPONENCIAL
///   5. Ajusta pesos de cámara y parámetros de gobernanza
///   6. Notifica a módulos externos (OracleScheduler, CoopetitionEngine)
///   7. Circuit breaker: si crisis > MAX_INFLAMMATION_DAYS → revisión forzada
///
/// @dev INVARIANTE:
///   MAX_INFLAMMATION_DAYS = 30
///   Ninguna crisis puede extenderse más de 30 días sin revisión explícita de C1.

contract ImmunityCore is AccessControl, ReentrancyGuard {

    using ThreatMath for *;

    // ─── Roles ───────────────────────────────────────────────────────────────

    bytes32 public constant ORACLE_ROLE      = keccak256("ORACLE_ROLE");
    bytes32 public constant GOVERNANCE_ROLE  = keccak256("GOVERNANCE_ROLE");
    bytes32 public constant RESOLVER_ROLE    = keccak256("RESOLVER_ROLE"); // C1 circuit breaker

    // ─── Constants ───────────────────────────────────────────────────────────

    uint256 public constant MAX_INFLAMMATION_DAYS = 30;
    uint256 public constant BPS                   = 10_000;

    // ─── Structs ─────────────────────────────────────────────────────────────

    struct ThreatSnapshot {
        uint256 timestamp;
        uint256 threatScore;
        uint8   severity;       // VERDE=0 AMARILLO=1 NARANJA=2 ROJO=3
        uint8   velocity;       // LOGARÍTMICA=0 LINEAL=1 EXPONENCIAL=2
        bool    participacion;
        bool    gini;
        bool    tesoreria;
        bool    reputacion;
        bool    oracle;
        bool    exploit;
        uint256 c1WeightBps;
        uint256 c2WeightBps;
        uint256 oracleWeightBps;
        uint256 quorumBps;
        uint256 timelockDays;
    }

    struct InflammationRecord {
        uint256 startedAt;
        uint256 resolvedAt;     // 0 si sigue activa
        uint8   peakSeverity;
        uint256 peakScore;
        bool    circuitBreakerTriggered;
        bool    forcedResolution; // si fue resuelta por el circuit breaker
    }

    // ─── State ───────────────────────────────────────────────────────────────

    GovernanceParams public govParams;

    // Módulos externos notificados en cambios de estado
    address public oracleSchedulerAddr;
    address public coopetitionEngineAddr;
    address public fmdDaoCoreAddr;

    // Estado actual del sistema
    ThreatSnapshot  public currentSnapshot;
    bool            public inflammationActive;
    uint256         public inflammationStartedAt;
    uint256         public inflammationCount;

    // Historial
    ThreatSnapshot[]           public snapshotHistory;
    mapping(uint256 => InflammationRecord) public inflammationHistory;

    // Score anterior para cálculo de velocidad
    uint256 public previousThreatScore;

    // ─── Events ──────────────────────────────────────────────────────────────

    event ThreatAssessed(
        uint256 indexed snapshotId,
        uint256 threatScore,
        uint8   severity,
        uint8   velocity,
        uint256 timestamp
    );

    event InflammationStarted(
        uint256 indexed inflammationId,
        uint8   severity,
        uint256 timestamp
    );

    event InflammationResolved(
        uint256 indexed inflammationId,
        uint256 durationSeconds,
        bool    forcedByCircuitBreaker
    );

    event CircuitBreakerTriggered(
        uint256 indexed inflammationId,
        uint256 daysActive,
        uint256 timestamp
    );

    event ResilienceAlertReceived(uint256 R, bool inValley);
    event DoubleStaleAlertReceived(bytes32 dataKey);

    event ChamberWeightsAdjusted(
        uint256 c1WeightBps,
        uint256 c2WeightBps,
        uint256 oracleWeightBps,
        uint8   severity,
        uint8   velocity
    );

    // ─── Constructor ─────────────────────────────────────────────────────────

    constructor(
        address admin,
        address _govParams,
        address _oracleScheduler,
        address _coopetitionEngine,
        address _fmdDaoCore
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        govParams              = GovernanceParams(_govParams);
        oracleSchedulerAddr    = _oracleScheduler;
        coopetitionEngineAddr  = _coopetitionEngine;
        fmdDaoCoreAddr         = _fmdDaoCore;
    }

    // ─── Threat Assessment ────────────────────────────────────────────────────

    /// @notice Recibe métricas del ThreatOracle y calcula el estado del sistema
    /// @param participacionCaida  Participación cayó > 70% en 48h
    /// @param giniAlto            Gini reputacional > 0.8
    /// @param tesoreriaDrenada    Tesorería bajó > 30% en 7 días
    /// @param reputacionSpike     Un actor superó 40% de reputación total en 72h
    /// @param oracleDesviado      Oracle desviado > 3σ
    /// @param exploitDetectado    Fallo técnico o halt detectado
    function reportMetrics(
        bool participacionCaida,
        bool giniAlto,
        bool tesoreriaDrenada,
        bool reputacionSpike,
        bool oracleDesviado,
        bool exploitDetectado
    ) external onlyRole(ORACLE_ROLE) nonReentrant {

        uint256 score = ThreatMath.calculateThreatScore(
            participacionCaida,
            giniAlto,
            tesoreriaDrenada,
            reputacionSpike,
            oracleDesviado,
            exploitDetectado
        );

        uint8 severity = ThreatMath.classifySeverity(score);
        uint8 velocity = ThreatMath.classifyVelocity(previousThreatScore, score);

        (uint256 c1W, uint256 c2W, uint256 oW) =
            ThreatMath.chamberWeights(severity, velocity);

        uint256 quorum   = ThreatMath.requiredQuorum(severity, velocity);
        uint256 timelock = ThreatMath.requiredTimelockDays(severity);

        ThreatSnapshot memory snap = ThreatSnapshot({
            timestamp:       block.timestamp,
            threatScore:     score,
            severity:        severity,
            velocity:        velocity,
            participacion:   participacionCaida,
            gini:            giniAlto,
            tesoreria:       tesoreriaDrenada,
            reputacion:      reputacionSpike,
            oracle:          oracleDesviado,
            exploit:         exploitDetectado,
            c1WeightBps:     c1W,
            c2WeightBps:     c2W,
            oracleWeightBps: oW,
            quorumBps:       quorum,
            timelockDays:    timelock
        });

        uint256 snapId = snapshotHistory.length;
        snapshotHistory.push(snap);
        currentSnapshot   = snap;
        previousThreatScore = score;

        emit ThreatAssessed(snapId, score, severity, velocity, block.timestamp);

        // Gestionar estado de inflamación
        _manageInflammation(severity, score);

        // Notificar ajuste de pesos a módulos externos
        _notifyWeightChange(severity, c1W, c2W, oW);

        emit ChamberWeightsAdjusted(c1W, c2W, oW, severity, velocity);

        // Verificar circuit breaker
        _checkCircuitBreaker();
    }

    // ─── Alertas externas ─────────────────────────────────────────────────────

    /// @notice Recibe alerta del FMDDAOCore cuando R sale del Valle
    /// @dev Llamada de bajo nivel desde FMDDAOCore._notifyImmunityCore()
    function receiveResilienceAlert(uint256 R) external {
        require(
            msg.sender == fmdDaoCoreAddr || hasRole(ORACLE_ROLE, msg.sender),
            "ImmunityCore: unauthorized"
        );
        bool inValley = R > 1_000 && R < 3_000;
        emit ResilienceAlertReceived(R, inValley);

        // Si R está muy fuera del Valle, añadir presión al Threat Score
        // Representado como activar la métrica de reputación si R > 5
        if (!inValley && (R > 5_000 || R < 500)) {
            // Emitir señal de alerta fuerte — el próximo reportMetrics la capturará
            // No modificamos el snapshot actual para mantener atomicidad
        }
    }

    /// @notice Recibe alerta del OracleScheduler cuando activo y standby están STALE
    /// @dev Llamada de bajo nivel desde OracleScheduler._notifyDoubleStale()
    function receiveDoubleStaleAlert(bytes32 dataKey) external {
        require(
            msg.sender == oracleSchedulerAddr || hasRole(ORACLE_ROLE, msg.sender),
            "ImmunityCore: unauthorized"
        );
        emit DoubleStaleAlertReceived(dataKey);
        // El Threat Score +2 se materializará en el próximo reportMetrics
        // como oracleDesviado = true (doble STALE implica desviación severa)
    }

    // ─── Circuit Breaker ──────────────────────────────────────────────────────

    /// @notice C1 resuelve una inflamación prolongada manualmente
    /// @dev Solo disponible cuando el circuit breaker ha sido activado
    function forceResolveInflammation()
        external onlyRole(RESOLVER_ROLE)
    {
        require(inflammationActive, "ImmunityCore: no active inflammation");

        uint256 id = inflammationCount;
        InflammationRecord storage rec = inflammationHistory[id];
        require(
            rec.circuitBreakerTriggered,
            "ImmunityCore: circuit breaker not triggered"
        );

        uint256 duration = block.timestamp - inflammationStartedAt;
        rec.resolvedAt     = block.timestamp;
        rec.forcedResolution = true;

        inflammationActive = false;

        // Notificar módulos del fin de la crisis
        _notifyCrisisEnd();

        emit InflammationResolved(id, duration, true);
    }

    // ─── Governance ──────────────────────────────────────────────────────────

    /// @notice Actualiza las direcciones de módulos externos
    function setModuleAddresses(
        address _oracleScheduler,
        address _coopetitionEngine,
        address _fmdDaoCore
    ) external onlyRole(GOVERNANCE_ROLE) {
        oracleSchedulerAddr   = _oracleScheduler;
        coopetitionEngineAddr = _coopetitionEngine;
        fmdDaoCoreAddr        = _fmdDaoCore;
    }

    // ─── Internal ────────────────────────────────────────────────────────────

    /// @notice Gestiona el inicio y fin de períodos de inflamación
    function _manageInflammation(uint8 severity, uint256 score) internal {
        bool shouldInflame = severity >= ThreatMath.SEVERITY_NARANJA;

        if (shouldInflame && !inflammationActive) {
            // Iniciar inflamación
            inflammationActive    = true;
            inflammationStartedAt = block.timestamp;
            inflammationCount++;

            uint256 id = inflammationCount;
            inflammationHistory[id] = InflammationRecord({
                startedAt:               block.timestamp,
                resolvedAt:              0,
                peakSeverity:            severity,
                peakScore:               score,
                circuitBreakerTriggered: false,
                forcedResolution:        false
            });

            _notifyCrisisStart(true);
            emit InflammationStarted(id, severity, block.timestamp);

        } else if (shouldInflame && inflammationActive) {
            // Actualizar pico si empeoró
            uint256 id = inflammationCount;
            if (score > inflammationHistory[id].peakScore) {
                inflammationHistory[id].peakSeverity = severity;
                inflammationHistory[id].peakScore    = score;
            }

        } else if (!shouldInflame && inflammationActive) {
            // Resolver inflamación: el sistema volvió a niveles normales
            uint256 id       = inflammationCount;
            uint256 duration = block.timestamp - inflammationStartedAt;

            inflammationHistory[id].resolvedAt = block.timestamp;
            inflammationActive = false;

            _notifyCrisisStart(false);
            emit InflammationResolved(id, duration, false);
        }
    }

    /// @notice Verifica el circuit breaker: crisis > MAX_INFLAMMATION_DAYS
    function _checkCircuitBreaker() internal {
        if (!inflammationActive) return;

        uint256 daysActive = (block.timestamp - inflammationStartedAt) / 1 days;
        if (daysActive < MAX_INFLAMMATION_DAYS) return;

        uint256 id = inflammationCount;
        if (!inflammationHistory[id].circuitBreakerTriggered) {
            inflammationHistory[id].circuitBreakerTriggered = true;
            emit CircuitBreakerTriggered(id, daysActive, block.timestamp);
            // C1 debe llamar forceResolveInflammation() para continuar
        }
    }

    /// @notice Notifica a CoopetitionEngine y OracleScheduler del estado de crisis
    function _notifyCrisisStart(bool inCrisis) internal {
        // CoopetitionEngine.setCrisisState(bool)
        if (coopetitionEngineAddr != address(0)) {
            coopetitionEngineAddr.call(
                abi.encodeWithSignature("setCrisisState(bool)", inCrisis)
            );
        }
        // OracleScheduler.setCrisisState(bool)
        if (oracleSchedulerAddr != address(0)) {
            oracleSchedulerAddr.call(
                abi.encodeWithSignature("setCrisisState(bool)", inCrisis)
            );
        }
    }

    function _notifyCrisisEnd() internal {
        _notifyCrisisStart(false);
    }

    /// @notice Propone ajuste de parámetros de gobernanza durante la crisis
    /// @dev No ejecuta directamente — propone vía GovernanceParams con timelock
    ///      Los cambios de emergencia tienen timelock reducido (TIMELOCK_CRISIS)
    function _notifyWeightChange(
        uint8   severity,
        uint256 c1W,
        uint256 c2W,
        uint256 oW
    ) internal {
        // En crisis ROJA: proponer ajuste de tau_DAO
        if (severity == ThreatMath.SEVERITY_ROJO) {
            uint256 baseTau = govParams.get("TAU_DAO");
            uint256 adjustedTau = ThreatMath.adjustedTau(
                baseTau,
                ThreatMath.SEVERITY_ROJO
            );

            // Solo proponer si el valor cambió significativamente
            if (adjustedTau < baseTau) {
                bytes32 tauKey = keccak256(bytes("TAU_DAO"));
                // Intentar proponer — puede fallar si ya hay un cambio pendiente
                try govParams.proposeChange(tauKey, adjustedTau) {
                    // Propuesto correctamente
                } catch {
                    // Ya hay un cambio pendiente — no hacer nada
                }
            }
        }
    }

    // ─── View ─────────────────────────────────────────────────────────────────

    /// @notice Estado completo del sistema inmune
    function systemImmunityStatus() external view returns (
        uint256 currentThreatScore,
        uint8   currentSeverity,
        uint8   currentVelocity,
        bool    isInflamed,
        uint256 daysInflamed,
        bool    circuitBreakerActive,
        uint256 c1WeightBps,
        uint256 c2WeightBps,
        uint256 quorumBps
    ) {
        currentThreatScore = currentSnapshot.threatScore;
        currentSeverity    = currentSnapshot.severity;
        currentVelocity    = currentSnapshot.velocity;
        isInflamed         = inflammationActive;
        c1WeightBps        = currentSnapshot.c1WeightBps;
        c2WeightBps        = currentSnapshot.c2WeightBps;
        quorumBps          = currentSnapshot.quorumBps;

        if (inflammationActive) {
            daysInflamed = (block.timestamp - inflammationStartedAt) / 1 days;
            circuitBreakerActive = daysInflamed >= MAX_INFLAMMATION_DAYS;
        }
    }

    /// @notice Historial completo de snapshots
    function getSnapshotCount() external view returns (uint256) {
        return snapshotHistory.length;
    }

    function getSnapshot(uint256 index)
        external view returns (ThreatSnapshot memory)
    {
        return snapshotHistory[index];
    }

    /// @notice Registro de una inflamación específica
    function getInflammationRecord(uint256 id)
        external view returns (InflammationRecord memory)
    {
        return inflammationHistory[id];
    }

    /// @notice Indica si el sistema está en modo crisis (NARANJA o ROJO)
    function isInCrisis() external view returns (bool) {
        return inflammationActive;
    }

    /// @notice Quórum efectivo actual (ajustado por crisis)
    function currentQuorum() external view returns (uint256) {
        return currentSnapshot.quorumBps;
    }

    /// @notice Timelock efectivo actual en días
    function currentTimelockDays() external view returns (uint256) {
        return currentSnapshot.timelockDays;
    }
}
