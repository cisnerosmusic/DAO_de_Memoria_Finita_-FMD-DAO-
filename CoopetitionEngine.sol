// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title CoopetitionEngine
/// @author Ernesto Cisneros Cino — FMD-DAO HumanLayer
/// @notice Motor de coopetición: competencia que requiere colaboración para ganar.
///         Gestiona créditos de gobernanza, voto cuadrático por intensidad
///         e incentivos acoplados entre C1 y C2.
/// @dev    No modifica contratos externos. Solo lee de:
///         ResilienceIndex, ImmunityCore, IdeologicalOscillator, ProofOfUnderstanding.
contract CoopetitionEngine is AccessControl, ReentrancyGuard {

    // ─── Roles ───────────────────────────────────────────────────────────────

    bytes32 public constant ORACLE_ROLE  = keccak256("ORACLE_ROLE");
    bytes32 public constant KEEPER_ROLE  = keccak256("KEEPER_ROLE");
    bytes32 public constant MINTER_ROLE  = keccak256("MINTER_ROLE"); // acredita participación

    // ─── Constants ───────────────────────────────────────────────────────────

    uint256 public constant BPS              = 10_000;
    uint256 public constant MAX_INTENSITY    = 5;
    uint256 public constant MAX_INTENSITY_CRISIS = 3; // en crisis ROJA del sistema inmune
    uint256 public constant PRECISION        = 1e18;

    // Generación de créditos por acción
    uint256 public constant CREDITS_PROOF_COMPLETION  = 3;
    uint256 public constant CREDITS_PROPOSAL_APPROVED = 10;
    uint256 public constant CREDITS_CONTRIBUTION      = 5;
    uint256 public constant CREDITS_CYCLE_FULL        = 2;

    // Decay de créditos: λ = ln(2) / 60 días ≈ 0.01155 / día
    // Representado como fracción: LAMBDA_NUM / LAMBDA_DEN por segundo
    uint256 public constant LAMBDA_NUM = 1155;        // ×10^-7 por segundo
    uint256 public constant LAMBDA_DEN = 1_000_000_0; // denominador

    // ─── Structs ─────────────────────────────────────────────────────────────

    /// @notice Balance de créditos de un miembro con timestamp para decay virtualizado
    struct GovernanceCredits {
        uint256 rawBalance;     // balance antes de aplicar decay
        uint256 lastUpdate;     // timestamp de la última escritura
    }

    /// @notice Registro de un voto individual
    struct VoteRecord {
        uint256 proposalId;
        uint8   intensity;      // 1–5
        uint256 cost;           // intensity²
        uint256 adjustedWeight; // peso final tras oscilador + PoU
        uint256 timestamp;
        bool    inFavor;
    }

    /// @notice Métricas de rendimiento de un ciclo (para cálculo de bonus C1)
    struct CyclePerformance {
        uint256 cycleId;
        uint256 successRateBps;       // tasa de propuestas aprobadas exitosamente
        uint256 participationRateBps; // tasa de participación C2
        uint256 resilienceR;          // R al cierre del ciclo (×1000)
        uint256 jointScoreBps;        // puntuación conjunta calculada
        bool    finalized;
    }

    /// @notice Registro de bonus por ciclo para un miembro de C1
    struct C1Bonus {
        uint256 cycleId;
        uint256 baseAmount;    // contribución individual
        uint256 bonusAmount;   // fracción del joint score
        bool    claimed;
    }

    // ─── State ───────────────────────────────────────────────────────────────

    // Créditos por miembro
    mapping(address => GovernanceCredits) public credits;

    // Historial de votos por miembro
    mapping(address => VoteRecord[]) public voteHistory;

    // Métricas por ciclo
    mapping(uint256 => CyclePerformance) public cyclePerformance;

    // Bonus de C1 por miembro por ciclo
    mapping(address => mapping(uint256 => C1Bonus)) public c1Bonus;

    // Ciclo actual
    uint256 public currentCycle;

    // En crisis del sistema inmune (leído del ImmunityCore)
    bool public systemInCrisis;

    // Parámetro de bonus del ciclo (definido en GovernanceParams)
    uint256 public bonusPercentBps; // fracción del jointScore que va a bonus

    // ─── Events ──────────────────────────────────────────────────────────────

    event VoteCast(
        address indexed member,
        uint256 indexed proposalId,
        uint8   intensity,
        uint256 cost,
        uint256 adjustedWeight,
        bool    inFavor
    );

    event CreditsEarned(
        address indexed member,
        uint256 amount,
        string  reason
    );

    event CreditsDecayApplied(
        address indexed member,
        uint256 before,
        uint256 after_
    );

    event CycleFinalized(
        uint256 indexed cycleId,
        uint256 jointScoreBps
    );

    event BonusCalculated(
        address indexed member,
        uint256 indexed cycleId,
        uint256 bonusAmount
    );

    event CrisisStateUpdated(bool inCrisis);

    // ─── Constructor ─────────────────────────────────────────────────────────

    constructor(address admin, uint256 _bonusPercentBps) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        bonusPercentBps = _bonusPercentBps;
        currentCycle = 1;
    }

    // ─── Vote ─────────────────────────────────────────────────────────────────

    /// @notice Emite un voto con intensidad cuadrática
    /// @param proposalId ID de la propuesta
    /// @param intensity Intensidad del voto [1, 5] (máx 3 en crisis)
    /// @param inFavor Dirección del voto
    /// @param adjustedWeight Peso ajustado calculado off-chain por IdeologicalOscillator + PoU
    ///        y firmado por el oráculo. En producción: verificar firma on-chain.
    function castVote(
        uint256 proposalId,
        uint8   intensity,
        bool    inFavor,
        uint256 adjustedWeight
    ) external nonReentrant {
        uint8 maxIntensity = systemInCrisis ? uint8(MAX_INTENSITY_CRISIS) : uint8(MAX_INTENSITY);
        require(intensity >= 1 && intensity <= maxIntensity, "CoopetitionEngine: invalid intensity");

        uint256 cost = _quadraticCost(intensity);
        uint256 effectiveCredits = getEffectiveCredits(msg.sender);

        require(effectiveCredits >= cost, "CoopetitionEngine: insufficient credits");

        // Aplicar coste: escribir balance actualizado con decay ya aplicado
        credits[msg.sender] = GovernanceCredits({
            rawBalance: effectiveCredits - cost,
            lastUpdate: block.timestamp
        });

        voteHistory[msg.sender].push(VoteRecord({
            proposalId:     proposalId,
            intensity:      intensity,
            cost:           cost,
            adjustedWeight: adjustedWeight,
            timestamp:      block.timestamp,
            inFavor:        inFavor
        }));

        emit VoteCast(msg.sender, proposalId, intensity, cost, adjustedWeight, inFavor);
    }

    // ─── Credits ──────────────────────────────────────────────────────────────

    /// @notice Acredita créditos por participación verificada
    /// @param member Dirección del miembro
    /// @param amount Cantidad de créditos a acreditar
    /// @param reason Descripción legible del motivo
    function earnCredits(
        address memory,
        uint256 amount,
        string calldata reason
    ) external onlyRole(MINTER_ROLE) {
        // Primero aplicar decay acumulado, luego sumar nuevos créditos
        uint256 current = getEffectiveCredits(member);
        credits[member] = GovernanceCredits({
            rawBalance: current + amount,
            lastUpdate: block.timestamp
        });
        emit CreditsEarned(member, amount, reason);
    }

    /// @notice Aplica decay en lote para un array de miembros (llamado por keeper)
    /// @param members Array de direcciones a actualizar
    function applyCreditsDecay(address[] calldata members)
        external onlyRole(KEEPER_ROLE)
    {
        for (uint256 i = 0; i < members.length; i++) {
            address m = members[i];
            uint256 before = credits[m].rawBalance;
            uint256 effective = getEffectiveCredits(m);

            credits[m] = GovernanceCredits({
                rawBalance: effective,
                lastUpdate: block.timestamp
            });

            if (before != effective) {
                emit CreditsDecayApplied(m, before, effective);
            }
        }
    }

    /// @notice Lectura virtualizada: devuelve créditos con decay aplicado sin escribir
    /// @param member Dirección del miembro
    /// @return Créditos efectivos actuales
    function getEffectiveCredits(address member)
        public view returns (uint256)
    {
        GovernanceCredits memory c = credits[member];
        if (c.rawBalance == 0) return 0;

        uint256 elapsed = block.timestamp - c.lastUpdate;
        if (elapsed == 0) return c.rawBalance;

        // Aproximación de e^(-λ×t) usando serie de Taylor truncada (4 términos)
        // Suficientemente precisa para ventanas de 0–180 días
        // λ×t en unidades de PRECISION para evitar overflow
        uint256 lambdaT = (LAMBDA_NUM * elapsed * PRECISION) / (LAMBDA_DEN);

        // e^(-x) ≈ 1 - x + x²/2 - x³/6 + x⁴/24  (para x pequeño)
        // Para x grande usamos aproximación iterativa más conservadora
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
            // Para períodos largos: decay a mínimo del 5% del balance original
            decayFactor = PRECISION / 20; // 5%
        }

        return (c.rawBalance * decayFactor) / PRECISION;
    }

    // ─── Cycle Performance ───────────────────────────────────────────────────

    /// @notice Registra métricas al cierre de un ciclo (llamado por oráculo)
    /// @param cycleId ID del ciclo que cierra
    /// @param successRateBps Tasa de éxito de propuestas (0–BPS)
    /// @param participationRateBps Tasa de participación (0–BPS)
    /// @param resilienceR R actual escalado ×1000
    function recordCycleMetrics(
        uint256 cycleId,
        uint256 successRateBps,
        uint256 participationRateBps,
        uint256 resilienceR
    ) external onlyRole(ORACLE_ROLE) {
        require(!cyclePerformance[cycleId].finalized, "CoopetitionEngine: already finalized");

        uint256 rContribution = (resilienceR >= 1000 && resilienceR <= 3000)
            ? BPS
            : BPS / 2;

        uint256 jointScore = (
            successRateBps      * 4 +
            participationRateBps * 3 +
            rContribution        * 3
        ) / 10;

        cyclePerformance[cycleId] = CyclePerformance({
            cycleId:              cycleId,
            successRateBps:       successRateBps,
            participationRateBps: participationRateBps,
            resilienceR:          resilienceR,
            jointScoreBps:        jointScore,
            finalized:            true
        });

        currentCycle = cycleId + 1;

        emit CycleFinalized(cycleId, jointScore);
    }

    /// @notice Calcula y registra el bonus de C1 para un miembro en un ciclo dado
    /// @param member Miembro de C1
    /// @param cycleId Ciclo de referencia
    /// @param baseContribution Contribución individual verificada (en unidades base)
    function calculateBonus(
        address member,
        uint256 cycleId,
        uint256 baseContribution
    ) external onlyRole(ORACLE_ROLE) {
        require(cyclePerformance[cycleId].finalized, "CoopetitionEngine: cycle not finalized");
        require(!c1Bonus[member][cycleId].claimed, "CoopetitionEngine: bonus already calculated");

        uint256 jointScore  = cyclePerformance[cycleId].jointScoreBps;
        uint256 bonusAmount = (baseContribution * bonusPercentBps * jointScore) / (BPS * BPS);

        c1Bonus[member][cycleId] = C1Bonus({
            cycleId:     cycleId,
            baseAmount:  baseContribution,
            bonusAmount: bonusAmount,
            claimed:     true
        });

        emit BonusCalculated(member, cycleId, bonusAmount);
    }

    // ─── Crisis State ─────────────────────────────────────────────────────────

    /// @notice Actualiza el estado de crisis (llamado por ImmunityCore via oráculo)
    /// @param inCrisis true si el sistema está en alerta ROJA
    function setCrisisState(bool inCrisis) external onlyRole(ORACLE_ROLE) {
        systemInCrisis = inCrisis;
        emit CrisisStateUpdated(inCrisis);
    }

    // ─── Admin ────────────────────────────────────────────────────────────────

    /// @notice Actualiza el porcentaje de bonus del ciclo
    function setBonusPercent(uint256 newBonusPercentBps)
        external onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(newBonusPercentBps <= BPS, "CoopetitionEngine: exceeds 100%");
        bonusPercentBps = newBonusPercentBps;
    }

    // ─── Internal ────────────────────────────────────────────────────────────

    /// @notice Calcula el coste cuadrático de un voto
    function _quadraticCost(uint8 intensity) internal pure returns (uint256) {
        return uint256(intensity) * uint256(intensity);
    }

    // ─── View ─────────────────────────────────────────────────────────────────

    /// @notice Devuelve el historial de votos de un miembro
    function getVoteHistory(address member)
        external view returns (VoteRecord[] memory)
    {
        return voteHistory[member];
    }

    /// @notice Devuelve el bonus total acumulado de un miembro en un rango de ciclos
    function getTotalBonus(address member, uint256 fromCycle, uint256 toCycle)
        external view returns (uint256 total)
    {
        for (uint256 i = fromCycle; i <= toCycle; i++) {
            total += c1Bonus[member][i].bonusAmount;
        }
    }

    /// @notice Simula el coste de votar con una intensidad dada
    function simulateVoteCost(uint8 intensity) external pure returns (uint256) {
        require(intensity >= 1 && intensity <= 5, "CoopetitionEngine: invalid intensity");
        return uint256(intensity) * uint256(intensity);
    }
}
