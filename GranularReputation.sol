// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../libraries/HumanMath.sol";

/// @title GranularReputation
/// @author Ernesto Cisneros Cino — FMD-DAO HumanLayer
/// @notice Vector reputacional 5D de miembros C2 con decay diferenciado por dimensión.
///
/// @dev CINCO DIMENSIONES:
///   0 — PROPUESTA     λ × 0.80  (decae moderado-rápido)
///   1 — VALIDACION    λ × 0.50  (decae lento — rigor acumulado)
///   2 — COMPRENSION   λ × 1.20  (decae rápido — requiere esfuerzo continuo)
///   3 — OSCILACION    λ × 0.90  (decae moderado)
///   4 — COLABORACION  λ × 0.60  (decae lento — relaciones duraderas)
///
/// @dev ESCRITURA VIRTUALIZADA:
///   El decay se calcula en getCurrentVector() (view, cero gas).
///   Solo se escribe al boost/penalización, o en batch si drift > 1%.
///
/// @dev RELACIÓN CON ReputationModule:
///   GranularReputation → vector 5D, visibilidad pública C2, peso de voto
///   ReputationModule   → score global C1, elegibilidad, remoción
///   Complementarios — no redundantes.
contract GranularReputation is AccessControl, ReentrancyGuard {

    // ─── Roles ───────────────────────────────────────────────────────────────

    bytes32 public constant BOOSTER_ROLE    = keccak256("BOOSTER_ROLE");
    bytes32 public constant ORACLE_ROLE     = keccak256("ORACLE_ROLE");
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");

    // ─── Constants ───────────────────────────────────────────────────────────

    uint256 public constant BPS       = 10_000;
    uint256 public constant MAX_DIM   = 10_000;
    uint8   public constant DIM_COUNT = 5;

    uint8 public constant DIM_PROPUESTA    = 0;
    uint8 public constant DIM_VALIDACION   = 1;
    uint8 public constant DIM_COMPRENSION  = 2;
    uint8 public constant DIM_OSCILACION   = 3;
    uint8 public constant DIM_COLABORACION = 4;

    // Umbral de drift mínimo para escribir en batch (1%)
    uint256 public constant DRIFT_THRESHOLD_BPS = 100;

    // ─── Structs ─────────────────────────────────────────────────────────────

    struct MemberRecord {
        uint256[5] rawScores;    // scores sin decay
        uint256[5] lastUpdated;  // timestamp de última escritura por dimensión
        bool        active;
        uint256     joinedAt;
        uint256     joinedCycle;
    }

    struct RepEvent {
        uint8   dimension;
        int256  delta;           // positivo = boost, negativo = penalización
        string  description;
        uint256 timestamp;
        uint256 cycle;
    }

    // ─── State ───────────────────────────────────────────────────────────────

    mapping(address => MemberRecord) public members;
    mapping(address => RepEvent[])   public repHistory;
    address[]                        public memberList;

    uint256 public currentCycle;

    // ─── Events ──────────────────────────────────────────────────────────────

    event MemberRegistered(address indexed member, uint256 cycle);

    event DimensionBoosted(
        address indexed member,
        uint8   indexed dimension,
        uint256 amount,
        string  description,
        uint256 cycle
    );

    event DimensionPenalized(
        address indexed member,
        uint8   indexed dimension,
        uint256 amount,
        string  description,
        uint256 cycle
    );

    event DecayApplied(
        address indexed member,
        uint256[5] scoresBefore,
        uint256[5] scoresAfter
    );

    event CycleAdvanced(uint256 newCycle);

    // ─── Constructor ─────────────────────────────────────────────────────────

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    // ─── Registration ────────────────────────────────────────────────────────

    /// @notice Registra un nuevo miembro con scores iniciales en cero
    function registerMember(address member)
        external onlyRole(GOVERNANCE_ROLE)
    {
        require(!members[member].active, "GranularReputation: already registered");
        require(member != address(0),    "GranularReputation: zero address");

        uint256 ts = block.timestamp;
        uint256[5] memory times = [ts, ts, ts, ts, ts];

        members[member] = MemberRecord({
            rawScores:   [uint256(0), 0, 0, 0, 0],
            lastUpdated: times,
            active:      true,
            joinedAt:    ts,
            joinedCycle: currentCycle
        });

        memberList.push(member);
        emit MemberRegistered(member, currentCycle);
    }

    // ─── Boost & Penalize ────────────────────────────────────────────────────

    /// @notice Boost en una dimensión por contribución verificada
    /// @param member      Dirección del miembro
    /// @param dimension   Índice (0–4)
    /// @param amount      BPS a añadir (cap en MAX_DIM)
    /// @param description Razón pública del boost
    function boostDimension(
        address         member,
        uint8           dimension,
        uint256         amount,
        string calldata description
    ) external onlyRole(BOOSTER_ROLE) nonReentrant {
        require(members[member].active, "GranularReputation: not active");
        require(dimension < DIM_COUNT,  "GranularReputation: invalid dimension");
        require(amount > 0,             "GranularReputation: zero amount");

        _materialize(member, dimension);

        uint256 newScore = members[member].rawScores[dimension] + amount;
        if (newScore > MAX_DIM) newScore = MAX_DIM;

        members[member].rawScores[dimension]   = newScore;
        members[member].lastUpdated[dimension] = block.timestamp;

        repHistory[member].push(RepEvent({
            dimension:   dimension,
            delta:       int256(amount),
            description: description,
            timestamp:   block.timestamp,
            cycle:       currentCycle
        }));

        emit DimensionBoosted(member, dimension, amount, description, currentCycle);
    }

    /// @notice Penalización en una dimensión por comportamiento verificado
    function penalizeDimension(
        address         member,
        uint8           dimension,
        uint256         amount,
        string calldata description
    ) external onlyRole(BOOSTER_ROLE) nonReentrant {
        require(members[member].active, "GranularReputation: not active");
        require(dimension < DIM_COUNT,  "GranularReputation: invalid dimension");
        require(amount > 0,             "GranularReputation: zero amount");

        _materialize(member, dimension);

        uint256 current  = members[member].rawScores[dimension];
        uint256 newScore = current > amount ? current - amount : 0;

        members[member].rawScores[dimension]   = newScore;
        members[member].lastUpdated[dimension] = block.timestamp;

        repHistory[member].push(RepEvent({
            dimension:   dimension,
            delta:       -int256(amount),
            description: description,
            timestamp:   block.timestamp,
            cycle:       currentCycle
        }));

        emit DimensionPenalized(member, dimension, amount, description, currentCycle);
    }

    // ─── Batch Decay ─────────────────────────────────────────────────────────

    /// @notice Aplica decay a un miembro si alguna dimensión tiene drift > 1%
    /// @dev Sin rol especial — cualquiera puede pagar el gas.
    function applyDecay(address member) external {
        require(members[member].active, "GranularReputation: not active");

        MemberRecord storage rec = members[member];
        uint256[5] memory before = rec.rawScores;
        bool anyDrift = false;

        for (uint8 d = 0; d < DIM_COUNT; d++) {
            if (rec.rawScores[d] == 0) continue;

            uint256 elapsed = block.timestamp - rec.lastUpdated[d];
            uint256 decayed = HumanMath.decayDimension(rec.rawScores[d], elapsed, d);

            uint256 drift = ((rec.rawScores[d] - decayed) * BPS) / rec.rawScores[d];

            if (drift >= DRIFT_THRESHOLD_BPS) {
                rec.rawScores[d]   = decayed;
                rec.lastUpdated[d] = block.timestamp;
                anyDrift = true;
            }
        }

        if (anyDrift) emit DecayApplied(member, before, rec.rawScores);
    }

    // ─── Cycle ───────────────────────────────────────────────────────────────

    /// @notice Avanza el ciclo (llamado por FMDDAOCore en el Ritual Trimestral)
    function advanceCycle() external onlyRole(GOVERNANCE_ROLE) {
        currentCycle++;
        emit CycleAdvanced(currentCycle);
    }

    // ─── View ─────────────────────────────────────────────────────────────────

    /// @notice Vector actual con decay aplicado — sin escribir (view puro)
    function getCurrentVector(address member)
        external view returns (uint256[5] memory scores)
    {
        MemberRecord storage rec = members[member];
        for (uint8 d = 0; d < DIM_COUNT; d++) {
            if (rec.rawScores[d] == 0) { scores[d] = 0; continue; }
            uint256 elapsed = block.timestamp - rec.lastUpdated[d];
            scores[d] = HumanMath.decayDimension(rec.rawScores[d], elapsed, d);
        }
    }

    /// @notice Score agregado: media aritmética de las 5 dimensiones con decay
    function getAggregatedScore(address member)
        external view returns (uint256 aggregated)
    {
        uint256[5] memory scores = this.getCurrentVector(member);
        uint256 total = 0;
        for (uint8 d = 0; d < DIM_COUNT; d++) total += scores[d];
        aggregated = total / DIM_COUNT;
    }

    /// @notice Historial completo de eventos de reputación de un miembro
    function getRepHistory(address member)
        external view returns (RepEvent[] memory)
    {
        return repHistory[member];
    }

    /// @notice Número total de miembros registrados
    function getMemberCount() external view returns (uint256) {
        return memberList.length;
    }

    function isActive(address member) external view returns (bool) {
        return members[member].active;
    }

    function getRawScore(address member, uint8 dimension)
        external view returns (uint256)
    {
        require(dimension < DIM_COUNT, "GranularReputation: invalid dimension");
        return members[member].rawScores[dimension];
    }

    // ─── Internal ────────────────────────────────────────────────────────────

    /// @notice Materializa el decay de UNA dimensión antes de escribir sobre ella
    function _materialize(address member, uint8 dimension) internal {
        MemberRecord storage rec = members[member];
        if (rec.rawScores[dimension] == 0) return;

        uint256 elapsed = block.timestamp - rec.lastUpdated[dimension];
        rec.rawScores[dimension]   = HumanMath.decayDimension(
            rec.rawScores[dimension], elapsed, dimension
        );
        rec.lastUpdated[dimension] = block.timestamp;
    }
}
