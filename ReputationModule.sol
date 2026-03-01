// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "./GovernanceParams.sol";

/// @title ReputationModule
/// @author Ernesto Cisneros Cino — FMD-DAO Core
/// @notice Gestiona el decay exponencial de reputación de expertos C1.
///         Implementa escritura virtualizada: el decay se calcula al leer,
///         solo se escribe cuando hay una actualización real.
///
/// @dev RELACIÓN CON GranularReputation.sol:
///      ReputationModule gestiona la reputación GLOBAL de expertos C1
///      (un único score agregado usado para elegibilidad, rotación y remoción).
///      GranularReputation gestiona el vector MULTIDIMENSIONAL del HumanLayer
///      (cinco dimensiones para visibilidad pública y peso de voto).
///      Son complementarios — no redundantes.
///
/// @dev MODELO DE DECAY:
///      rep(t) = rep(t0) × e^(−λ × Δt)
///      λ = LAMBDA_BPS / 10^7 por segundo  (≈ ln2/60días → vida media 60 días)
///      Escritura diferida: solo al boost, penalización o remoción.
///      Keeper/Oracle aplica decay en lote periódicamente si drift > umbral.

contract ReputationModule is AccessControl {

    // ─── Roles ───────────────────────────────────────────────────────────────

    bytes32 public constant BOOSTER_ROLE   = keccak256("BOOSTER_ROLE");   // puede subir rep
    bytes32 public constant ORACLE_ROLE    = keccak256("ORACLE_ROLE");    // decay en lote
    bytes32 public constant GOVERNANCE_ROLE= keccak256("GOVERNANCE_ROLE");

    // ─── Constants ───────────────────────────────────────────────────────────

    uint256 public constant PRECISION    = 1e18;
    uint256 public constant MAX_REP      = 10_000; // BPS — reputación máxima
    uint256 public constant LAMBDA_DEN   = 10_000_000; // denominador de lambda

    // ─── Structs ─────────────────────────────────────────────────────────────

    struct Expert {
        address addr;
        uint256 rawRep;         // reputación antes de decay (0–10000)
        uint256 lastUpdate;     // timestamp de la última escritura
        uint256 contributions;  // acumulado histórico de boosts
        bool    active;
    }

    struct BoostRecord {
        uint256 amount;
        string  reason;         // descripción verificable del mérito
        uint256 timestamp;
        uint256 cycle;
    }

    // ─── State ───────────────────────────────────────────────────────────────

    GovernanceParams public govParams;

    mapping(address => Expert)       public experts;
    mapping(address => BoostRecord[]) public boostHistory;
    address[]                        public expertList;

    uint256 public currentCycle;

    // ─── Events ──────────────────────────────────────────────────────────────

    event ExpertAdded(address indexed expert, uint256 initialRep, uint256 cycle);
    event ReputationBoosted(address indexed expert, uint256 amount, string reason, uint256 cycle);
    event ReputationDecayed(address indexed expert, uint256 before, uint256 after_);
    event ExpertRemoved(address indexed expert, uint256 finalRep, uint256 cycle);
    event DecayAppliedBatch(uint256 expertCount, uint256 timestamp);
    event CycleAdvanced(uint256 newCycle);

    // ─── Constructor ─────────────────────────────────────────────────────────

    constructor(address admin, address _govParams) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        govParams    = GovernanceParams(_govParams);
        currentCycle = 1;
    }

    // ─── Expert Management ───────────────────────────────────────────────────

    /// @notice Añade un nuevo experto a C1
    /// @param expert Dirección del experto
    /// @param initialRep Reputación inicial (0–10000 BPS)
    function addExpert(address expert, uint256 initialRep)
        external onlyRole(GOVERNANCE_ROLE)
    {
        require(!experts[expert].active, "ReputationModule: already active");
        require(initialRep <= MAX_REP,   "ReputationModule: rep exceeds max");

        experts[expert] = Expert({
            addr:          expert,
            rawRep:        initialRep,
            lastUpdate:    block.timestamp,
            contributions: 0,
            active:        true
        });

        expertList.push(expert);
        emit ExpertAdded(expert, initialRep, currentCycle);
    }

    /// @notice Elimina un experto de C1 (manual — por remoción governance)
    function removeExpert(address expert)
        external onlyRole(GOVERNANCE_ROLE)
    {
        require(experts[expert].active, "ReputationModule: not active");
        uint256 finalRep = getCurrentReputation(expert);
        experts[expert].active = false;
        emit ExpertRemoved(expert, finalRep, currentCycle);
    }

    // ─── Boost ───────────────────────────────────────────────────────────────

    /// @notice Aumenta la reputación de un experto por contribución verificada
    /// @param expert  Dirección del experto
    /// @param amount  Cantidad a añadir (0–MAX_REP)
    /// @param reason  Descripción específica y medible del mérito
    function boostReputation(
        address        expert,
        uint256        amount,
        string calldata reason
    ) external onlyRole(BOOSTER_ROLE) {
        require(experts[expert].active, "ReputationModule: not active");

        // Aplicar decay acumulado antes de escribir el nuevo valor
        uint256 current = getCurrentReputation(expert);
        uint256 newRep  = current + amount;
        if (newRep > MAX_REP) newRep = MAX_REP;

        experts[expert].rawRep      = newRep;
        experts[expert].lastUpdate  = block.timestamp;
        experts[expert].contributions += amount;

        boostHistory[expert].push(BoostRecord({
            amount:    amount,
            reason:    reason,
            timestamp: block.timestamp,
            cycle:     currentCycle
        }));

        emit ReputationBoosted(expert, amount, reason, currentCycle);

        // Auto-remoción si la rep cae por debajo del umbral tras larga inactividad
        // (el boost puede haber venido después de mucho decay)
        _checkRemovalThreshold(expert, newRep);
    }

    // ─── Decay ───────────────────────────────────────────────────────────────

    /// @notice Aplica decay en lote para todos los expertos activos
    /// @dev Llamado por keeper/oracle al inicio de cada ciclo o cuando drift > umbral
    function updateDecayBatch() external onlyRole(ORACLE_ROLE) {
        uint256 count = 0;
        for (uint256 i = 0; i < expertList.length; i++) {
            address addr = expertList[i];
            if (!experts[addr].active) continue;

            uint256 before  = experts[addr].rawRep;
            uint256 current = getCurrentReputation(addr);

            // Solo escribir si el drift es significativo (> 1% de diferencia)
            if (before > current && (before - current) * 100 / before >= 1) {
                experts[addr].rawRep     = current;
                experts[addr].lastUpdate = block.timestamp;
                emit ReputationDecayed(addr, before, current);
                count++;
            }

            // Verificar umbral de remoción automática
            _checkRemovalThreshold(addr, current);
        }
        emit DecayAppliedBatch(count, block.timestamp);
    }

    /// @notice Aplica decay a un experto específico (puede llamarlo cualquiera)
    function updateDecay(address expert) external {
        require(experts[expert].active, "ReputationModule: not active");

        uint256 before  = experts[expert].rawRep;
        uint256 current = getCurrentReputation(expert);

        if (before != current) {
            experts[expert].rawRep     = current;
            experts[expert].lastUpdate = block.timestamp;
            emit ReputationDecayed(expert, before, current);
        }

        _checkRemovalThreshold(expert, current);
    }

    // ─── Cycle ───────────────────────────────────────────────────────────────

    /// @notice Avanza el ciclo (llamado por FMDDAOCore en el Ritual Trimestral)
    function advanceCycle() external onlyRole(ORACLE_ROLE) {
        currentCycle++;
        emit CycleAdvanced(currentCycle);
    }

    // ─── Internal ────────────────────────────────────────────────────────────

    /// @notice Verifica si un experto debe ser removido automáticamente
    function _checkRemovalThreshold(address expert, uint256 currentRep) internal {
        uint256 threshold = govParams.get("RENEWAL_THRESHOLD"); // BPS
        if (currentRep < threshold && experts[expert].active) {
            experts[expert].active = false;
            emit ExpertRemoved(expert, currentRep, currentCycle);
        }
    }

    /// @notice Calcula el decay acumulado usando serie de Taylor truncada
    function _applyDecay(uint256 rawRep, uint256 elapsed) internal view returns (uint256) {
        if (rawRep == 0 || elapsed == 0) return rawRep;

        uint256 lambdaBps = govParams.get("LAMBDA_BPS");

        // λt en unidades de PRECISION
        uint256 lambdaT = (lambdaBps * elapsed * PRECISION) / LAMBDA_DEN;

        uint256 decayFactor;
        if (lambdaT <= PRECISION) {
            uint256 x  = lambdaT;
            uint256 x2 = (x * x) / PRECISION;
            uint256 x3 = (x2 * x) / PRECISION;
            uint256 x4 = (x3 * x) / PRECISION;
            uint256 pos = PRECISION + x2 / 2 + x4 / 24;
            uint256 neg = x + x3 / 6;
            decayFactor = pos > neg ? pos - neg : 0;
        } else {
            // Períodos muy largos: mínimo 1% (no llega a cero absoluto)
            decayFactor = PRECISION / 100;
        }

        return (rawRep * decayFactor) / PRECISION;
    }

    // ─── View ─────────────────────────────────────────────────────────────────

    /// @notice Reputación efectiva actual con decay aplicado (sin escritura)
    function getCurrentReputation(address expert)
        public view returns (uint256)
    {
        Expert memory e = experts[expert];
        if (!e.active || e.rawRep == 0) return 0;
        uint256 elapsed = block.timestamp - e.lastUpdate;
        return _applyDecay(e.rawRep, elapsed);
    }

    /// @notice Devuelve si el sistema está en el Valle de Resiliencia
    function isInResilienceValley() external view returns (bool inValley, uint256 R) {
        uint256 tau   = govParams.get("TAU_DAO");
        uint256 omega = govParams.get("OMEGA"); // ×1000
        R = (tau * omega) / 1000;
        inValley = R > 1 && R < 3;
    }

    /// @notice Calcula el Índice de Resiliencia actual
    function calculateResilienceIndex() external view returns (uint256) {
        uint256 tau   = govParams.get("TAU_DAO");
        uint256 omega = govParams.get("OMEGA");
        return (tau * omega) / 1000;
    }

    /// @notice Lista de expertos activos con su reputación efectiva actual
    function getActiveExperts()
        external view
        returns (address[] memory addrs, uint256[] memory reps)
    {
        uint256 count = 0;
        for (uint256 i = 0; i < expertList.length; i++) {
            if (experts[expertList[i]].active) count++;
        }

        addrs = new address[](count);
        reps  = new uint256[](count);
        uint256 idx = 0;

        for (uint256 i = 0; i < expertList.length; i++) {
            address addr = expertList[i];
            if (experts[addr].active) {
                addrs[idx] = addr;
                reps[idx]  = getCurrentReputation(addr);
                idx++;
            }
        }
    }

    /// @notice Historial de boosts de un experto
    function getBoostHistory(address expert)
        external view returns (BoostRecord[] memory)
    {
        return boostHistory[expert];
    }

    /// @notice Índice Gini de la distribución de reputación en C1
    /// @dev Usado por ImmunityCore para detectar concentración de poder
    function calculateGini() external view returns (uint256 giniBps) {
        uint256 n = expertList.length;
        if (n == 0) return 0;

        uint256[] memory reps  = new uint256[](n);
        uint256 total = 0;
        uint256 active = 0;

        for (uint256 i = 0; i < n; i++) {
            if (experts[expertList[i]].active) {
                reps[active] = getCurrentReputation(expertList[i]);
                total += reps[active];
                active++;
            }
        }

        if (active == 0 || total == 0) return 0;

        uint256 sumAbsDiff = 0;
        for (uint256 i = 0; i < active; i++) {
            for (uint256 j = i + 1; j < active; j++) {
                uint256 diff = reps[i] > reps[j]
                    ? reps[i] - reps[j]
                    : reps[j] - reps[i];
                sumAbsDiff += diff * 2;
            }
        }

        giniBps = (sumAbsDiff * 10_000) / (2 * active * total);
    }
}
