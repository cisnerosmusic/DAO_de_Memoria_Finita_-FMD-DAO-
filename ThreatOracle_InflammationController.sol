// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "../libraries/ThreatMath.sol";

/// @title ThreatOracle
/// @author Ernesto Cisneros Cino — FMD-DAO ImmunityCore
/// @notice Publicador de métricas de amenaza hacia ImmunityCore.
///         Recibe datos del OracleRouter, los evalúa contra umbrales
///         y propaga flags de amenaza binarios.
///
/// @dev RESPONSABILIDADES:
///   - Leer datos del OracleRouter (participación, Gini, tesorería, etc.)
///   - Comparar contra umbrales configurados por gobernanza
///   - Calcular flags binarios (bool) para cada métrica
///   - Llamar ImmunityCore.reportMetrics() con el resultado
///   - Registrar historial de evaluaciones para el subgraph
///
/// @dev SEPARACIÓN DE RESPONSABILIDADES:
///   ThreatOracle  → qué es amenaza (comparación contra umbrales)
///   ImmunityCore  → qué significa (clasificación y respuesta)
///   InflammationController → qué cambia (ajuste de parámetros)

contract ThreatOracle is AccessControl {

    // ─── Roles ───────────────────────────────────────────────────────────────

    bytes32 public constant KEEPER_ROLE     = keccak256("KEEPER_ROLE");
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");

    // ─── Umbrales de amenaza (configurables por gobernanza) ──────────────────

    // Participación: caída > PARTICIPATION_DROP_BPS en 48h
    uint256 public participationDropThreshold = 7_000; // 70%

    // Gini: concentración > GINI_THRESHOLD_BPS
    uint256 public giniThreshold = 8_000; // 0.8

    // Tesorería: drenaje > TREASURY_DROP_BPS en 7 días
    uint256 public treasuryDropThreshold = 3_000; // 30%

    // Reputación: spike de un actor > REPUTATION_SPIKE_BPS del total en 72h
    uint256 public reputationSpikeThreshold = 4_000; // 40%

    // Oracle: desviación > 3σ (flag directo del OracleRouter)
    // Exploit: flag directo (halt, fallo técnico)

    // ─── State ───────────────────────────────────────────────────────────────

    address public immunityCoreAddr;
    address public oracleRouterAddr;

    uint256 public evaluationCount;

    // Snapshot de métricas anterior (para calcular caídas)
    uint256 public prevParticipationBps;
    uint256 public prevTreasuryBps;
    uint256 public lastEvaluationAt;

    // ─── Structs ─────────────────────────────────────────────────────────────

    struct EvaluationRecord {
        uint256 timestamp;
        uint256 participationBps;
        uint256 giniBps;
        uint256 treasuryBps;
        uint256 reputationMaxShareBps;
        bool    oracleDeviated;
        bool    exploitDetected;
        bool    flagParticipacion;
        bool    flagGini;
        bool    flagTesoreria;
        bool    flagReputacion;
        bool    flagOracle;
        bool    flagExploit;
        uint256 threatScore;
    }

    mapping(uint256 => EvaluationRecord) public evaluations;

    // ─── Events ──────────────────────────────────────────────────────────────

    event MetricsEvaluated(
        uint256 indexed evalId,
        uint256 threatScore,
        bool[6] flags,
        uint256 timestamp
    );

    event ThresholdUpdated(string metric, uint256 newValue);

    // ─── Constructor ─────────────────────────────────────────────────────────

    constructor(
        address admin,
        address _immunityCore,
        address _oracleRouter
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        immunityCoreAddr = _immunityCore;
        oracleRouterAddr = _oracleRouter;
    }

    // ─── Evaluation ──────────────────────────────────────────────────────────

    /// @notice Evalúa métricas actuales y propaga flags a ImmunityCore
    /// @dev Llamado por keeper periódicamente (cada 6–12h)
    /// @param currentParticipationBps  Participación actual C2 (0–10000)
    /// @param currentGiniBps           Gini reputacional C1 (0–10000)
    /// @param currentTreasuryBps       Tesorería como % del máximo histórico (0–10000)
    /// @param reputationMaxShareBps    Mayor share de reputación de un actor (0–10000)
    /// @param oracleDeviated           Flag directo: oracle desviado > 3σ
    /// @param exploitDetected          Flag directo: fallo técnico detectado
    function evaluate(
        uint256 currentParticipationBps,
        uint256 currentGiniBps,
        uint256 currentTreasuryBps,
        uint256 reputationMaxShareBps,
        bool    oracleDeviated,
        bool    exploitDetected
    ) external onlyRole(KEEPER_ROLE) {

        // Calcular caídas relativas
        bool flagParticipacion = _checkDrop(
            prevParticipationBps,
            currentParticipationBps,
            participationDropThreshold
        );

        bool flagGini      = currentGiniBps >= giniThreshold;

        bool flagTesoreria = _checkDrop(
            prevTreasuryBps,
            currentTreasuryBps,
            treasuryDropThreshold
        );

        bool flagReputacion = reputationMaxShareBps >= reputationSpikeThreshold;
        bool flagOracle     = oracleDeviated;
        bool flagExploit    = exploitDetected;

        // Calcular threat score localmente para el registro
        uint256 score = ThreatMath.calculateThreatScore(
            flagParticipacion,
            flagGini,
            flagTesoreria,
            flagReputacion,
            flagOracle,
            flagExploit
        );

        // Registrar evaluación
        uint256 evalId = ++evaluationCount;
        evaluations[evalId] = EvaluationRecord({
            timestamp:             block.timestamp,
            participationBps:      currentParticipationBps,
            giniBps:               currentGiniBps,
            treasuryBps:           currentTreasuryBps,
            reputationMaxShareBps: reputationMaxShareBps,
            oracleDeviated:        oracleDeviated,
            exploitDetected:       exploitDetected,
            flagParticipacion:     flagParticipacion,
            flagGini:              flagGini,
            flagTesoreria:         flagTesoreria,
            flagReputacion:        flagReputacion,
            flagOracle:            flagOracle,
            flagExploit:           flagExploit,
            threatScore:           score
        });

        // Actualizar snapshots anteriores
        prevParticipationBps = currentParticipationBps;
        prevTreasuryBps      = currentTreasuryBps;
        lastEvaluationAt     = block.timestamp;

        emit MetricsEvaluated(
            evalId,
            score,
            [flagParticipacion, flagGini, flagTesoreria,
             flagReputacion, flagOracle, flagExploit],
            block.timestamp
        );

        // Propagar a ImmunityCore
        (bool success,) = immunityCoreAddr.call(
            abi.encodeWithSignature(
                "reportMetrics(bool,bool,bool,bool,bool,bool)",
                flagParticipacion,
                flagGini,
                flagTesoreria,
                flagReputacion,
                flagOracle,
                flagExploit
            )
        );
        require(success, "ThreatOracle: ImmunityCore call failed");
    }

    // ─── Governance ──────────────────────────────────────────────────────────

    function setParticipationDropThreshold(uint256 bps)
        external onlyRole(GOVERNANCE_ROLE)
    {
        participationDropThreshold = bps;
        emit ThresholdUpdated("participacion", bps);
    }

    function setGiniThreshold(uint256 bps)
        external onlyRole(GOVERNANCE_ROLE)
    {
        giniThreshold = bps;
        emit ThresholdUpdated("gini", bps);
    }

    function setTreasuryDropThreshold(uint256 bps)
        external onlyRole(GOVERNANCE_ROLE)
    {
        treasuryDropThreshold = bps;
        emit ThresholdUpdated("tesoreria", bps);
    }

    function setReputationSpikeThreshold(uint256 bps)
        external onlyRole(GOVERNANCE_ROLE)
    {
        reputationSpikeThreshold = bps;
        emit ThresholdUpdated("reputacion", bps);
    }

    // ─── Internal ────────────────────────────────────────────────────────────

    /// @notice Verifica si un valor cayó más de un umbral respecto al anterior
    function _checkDrop(
        uint256 prev,
        uint256 curr,
        uint256 thresholdBps
    ) internal pure returns (bool) {
        if (prev == 0) return false;
        if (curr >= prev) return false;
        uint256 dropBps = ((prev - curr) * 10_000) / prev;
        return dropBps >= thresholdBps;
    }

    // ─── View ─────────────────────────────────────────────────────────────────

    function getEvaluation(uint256 evalId)
        external view returns (EvaluationRecord memory)
    {
        return evaluations[evalId];
    }

    function getLatestEvaluation()
        external view returns (EvaluationRecord memory)
    {
        if (evaluationCount == 0) revert("ThreatOracle: no evaluations");
        return evaluations[evaluationCount];
    }
}


// ═══════════════════════════════════════════════════════════════════════════════


/// @title InflammationController
/// @author Ernesto Cisneros Cino — FMD-DAO ImmunityCore
/// @notice Ajusta parámetros de gobernanza durante períodos de crisis.
///         Responde a señales de ImmunityCore de forma gradual y reversible.
///
/// @dev PRINCIPIO:
///   Los ajustes son PROPUESTAS, no ejecuciones directas.
///   Toda modificación de GovernanceParams pasa por su timelock.
///   En crisis ROJA el timelock es reducido (TIMELOCK_CRISIS = 2 días por defecto),
///   pero nunca eliminado. No hay ejecución instantánea.
///
/// @dev AJUSTES POR SEVERIDAD:
///
///   AMARILLO:  quórum +5%, timelock +1 día (señal de alerta)
///   NARANJA:   quórum +15%, timelock +5 días, tau_DAO al 60%
///   ROJO:      quórum +30%, timelock +12 días, tau_DAO al 25%
///
///   Recuperación: parámetros vuelven en 3 ciclos tras fin de inflamación

contract InflammationController is AccessControl {

    // ─── Roles ───────────────────────────────────────────────────────────────

    bytes32 public constant IMMUNITY_ROLE   = keccak256("IMMUNITY_ROLE");
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");

    // ─── Constants ───────────────────────────────────────────────────────────

    uint256 public constant BPS               = 10_000;
    uint256 public constant RECOVERY_CYCLES   = 3;

    // ─── State ───────────────────────────────────────────────────────────────

    address public govParamsAddr;
    address public immunityCoreAddr;

    uint8   public lastSeverity;
    uint256 public lastAdjustmentAt;
    uint256 public recoveryStartedAt;
    bool    public inRecovery;
    uint256 public recoveryStep;        // 0–RECOVERY_CYCLES

    // Valores base (antes de crisis) para restauración gradual
    uint256 public baseQuorumBps;
    uint256 public baseTimelockDays;
    uint256 public baseTauDays;

    // ─── Events ──────────────────────────────────────────────────────────────

    event AdjustmentProposed(
        uint8   severity,
        uint256 newQuorumBps,
        uint256 newTimelockDays,
        uint256 newTauDays,
        uint256 timestamp
    );

    event RecoveryStep(
        uint256 step,
        uint256 restoredQuorumBps,
        uint256 restoredTimelockDays,
        uint256 timestamp
    );

    event RecoveryComplete(uint256 timestamp);

    // ─── Constructor ─────────────────────────────────────────────────────────

    constructor(
        address admin,
        address _govParams,
        address _immunityCore,
        uint256 _baseQuorumBps,
        uint256 _baseTimelockDays,
        uint256 _baseTauDays
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(IMMUNITY_ROLE, _immunityCore);

        govParamsAddr    = _govParams;
        immunityCoreAddr = _immunityCore;
        baseQuorumBps    = _baseQuorumBps;     // e.g. 1000 (10%)
        baseTimelockDays = _baseTimelockDays;  // e.g. 2
        baseTauDays      = _baseTauDays;       // e.g. 60
    }

    // ─── Adjustment ──────────────────────────────────────────────────────────

    /// @notice Recibe señal de ImmunityCore y propone ajustes a GovernanceParams
    /// @param severity  Severidad actual (0=VERDE … 3=ROJO)
    function onSeverityChange(uint8 severity)
        external onlyRole(IMMUNITY_ROLE)
    {
        lastSeverity      = severity;
        lastAdjustmentAt  = block.timestamp;

        (uint256 newQuorum, uint256 newTimelock, uint256 newTau) =
            _targetParams(severity);

        // Proponer cambios en GovernanceParams (con su timelock propio)
        _proposeParam("QUORUM_BPS",    newQuorum);
        _proposeParam("TIMELOCK_NORMAL", newTimelock);
        _proposeParam("TAU_DAO",       newTau);

        emit AdjustmentProposed(severity, newQuorum, newTimelock, newTau, block.timestamp);

        // Si volvemos a VERDE o AMARILLO → iniciar recuperación gradual
        if (severity <= 1 && !inRecovery) {
            inRecovery        = true;
            recoveryStartedAt = block.timestamp;
            recoveryStep      = 0;
        }
    }

    /// @notice Avanza un paso de recuperación gradual
    /// @dev Llamado por keeper cada ciclo durante la recuperación
    function stepRecovery() external {
        require(inRecovery, "InflammationController: not in recovery");
        require(recoveryStep < RECOVERY_CYCLES, "InflammationController: recovery complete");

        recoveryStep++;

        // Interpolación lineal hacia los valores base
        uint256 progress = (recoveryStep * BPS) / RECOVERY_CYCLES; // 0→BPS

        uint256 currentQuorum   = _lerp(_inflatedQuorum(), baseQuorumBps, progress);
        uint256 currentTimelock = _lerp(_inflatedTimelock(), baseTimelockDays, progress);

        _proposeParam("QUORUM_BPS",      currentQuorum);
        _proposeParam("TIMELOCK_NORMAL", currentTimelock);

        emit RecoveryStep(recoveryStep, currentQuorum, currentTimelock, block.timestamp);

        if (recoveryStep == RECOVERY_CYCLES) {
            // Restaurar valores base exactos
            _proposeParam("QUORUM_BPS",      baseQuorumBps);
            _proposeParam("TIMELOCK_NORMAL", baseTimelockDays);
            _proposeParam("TAU_DAO",         baseTauDays);
            inRecovery = false;
            emit RecoveryComplete(block.timestamp);
        }
    }

    // ─── Governance ──────────────────────────────────────────────────────────

    /// @notice Actualiza valores base (cuando gobernanza cambia los parámetros base)
    function updateBaseValues(
        uint256 newBaseQuorumBps,
        uint256 newBaseTimelockDays,
        uint256 newBaseTauDays
    ) external onlyRole(GOVERNANCE_ROLE) {
        baseQuorumBps    = newBaseQuorumBps;
        baseTimelockDays = newBaseTimelockDays;
        baseTauDays      = newBaseTauDays;
    }

    // ─── Internal ────────────────────────────────────────────────────────────

    function _targetParams(uint8 severity)
        internal view
        returns (uint256 quorum, uint256 timelock, uint256 tau)
    {
        if (severity == 0) { // VERDE — normal
            return (baseQuorumBps, baseTimelockDays, baseTauDays);
        }
        if (severity == 1) { // AMARILLO
            return (
                baseQuorumBps    + 500,    // +5%
                baseTimelockDays + 1,
                baseTauDays
            );
        }
        if (severity == 2) { // NARANJA
            return (
                baseQuorumBps    + 1500,   // +15%
                baseTimelockDays + 5,
                (baseTauDays * 6_000) / BPS // 60%
            );
        }
        // ROJO
        return (
            baseQuorumBps    + 3000,       // +30%
            baseTimelockDays + 12,
            (baseTauDays * 2_500) / BPS    // 25%
        );
    }

    function _inflatedQuorum() internal view returns (uint256) {
        (uint256 q,,) = _targetParams(lastSeverity);
        return q;
    }

    function _inflatedTimelock() internal view returns (uint256) {
        (, uint256 t,) = _targetParams(lastSeverity);
        return t;
    }

    /// @notice Interpolación lineal entre dos valores
    function _lerp(uint256 from, uint256 to, uint256 progressBps)
        internal pure returns (uint256)
    {
        if (progressBps >= BPS) return to;
        if (from <= to) {
            return from + ((to - from) * progressBps) / BPS;
        }
        return from - ((from - to) * progressBps) / BPS;
    }

    /// @notice Propone un cambio a GovernanceParams (silencioso si ya hay pendiente)
    function _proposeParam(string memory key, uint256 value) internal {
        bytes32 k = keccak256(bytes(key));
        (bool success,) = govParamsAddr.call(
            abi.encodeWithSignature(
                "proposeChange(bytes32,uint256)",
                k,
                value
            )
        );
        // Si falla (pendiente, no autorizado) → no revertir, solo ignorar
        if (!success) {}
    }

    // ─── View ─────────────────────────────────────────────────────────────────

    function getRecoveryStatus() external view returns (
        bool   active,
        uint256 step,
        uint256 totalSteps,
        uint256 startedAt
    ) {
        return (inRecovery, recoveryStep, RECOVERY_CYCLES, recoveryStartedAt);
    }
}
