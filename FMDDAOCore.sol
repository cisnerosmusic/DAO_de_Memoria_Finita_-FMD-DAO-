// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./GovernanceParams.sol";
import "./ReputationModule.sol";

/// @title FMDDAOCore
/// @author Ernesto Cisneros Cino — FMD-DAO Core
/// @notice Núcleo central de la DAO de Memoria Finita.
///         Coordina el ciclo completo de gobernanza bicameral:
///         propuestas C2 → escalado C1 → ejecución → Ritual Trimestral.
///
/// @dev ARQUITECTURA:
///
///   FMDDAOCore es el contrato orquestador. No implementa lógica compleja
///   por sí mismo — delega en módulos especializados y coordina su interacción.
///   Es el único contrato que conoce la dirección de todos los módulos.
///   Los módulos no se conocen entre sí — solo conocen a Core.
///
///   Módulos coordinados:
///     GovernanceParams   → parámetros del sistema (τ, Ω, λ, quórums)
///     ReputationModule   → decay y elegibilidad de C1
///     ImmunityCore       → sistema inmunológico (externo, interfaz mínima)
///     OracleRouter       → datos externos (externo, interfaz mínima)
///     HumanLayer modules → CoopetitionEngine, GranularReputation (externos)
///
/// @dev FLUJO DE UNA PROPUESTA:
///
///   1. C2: createProposal()      — cualquier miembro verificado
///   2. C2: voteProposal()        — deliberación y quórum C2
///   3. C2: escalateToC1()        — si quórum C2 alcanzado
///   4. C1: c1Vote()              — validación técnica con quórum C1
///   5.   : executeProposal()     — si aprobada por C1, tras timelock
///   6. RITUAL: triggerRitual()   — cada ~90 días, mantenimiento del sistema
///
/// @dev INVARIANTE ABSOLUTO:
///   No execution without trace.
///   No rule change without delay.
///   No authority without exposure.

contract FMDDAOCore is AccessControl, ReentrancyGuard, Pausable {

    // ─── Roles ───────────────────────────────────────────────────────────────

    bytes32 public constant C1_ROLE       = keccak256("C1_ROLE");
    bytes32 public constant C2_ROLE       = keccak256("C2_ROLE");
    bytes32 public constant ORACLE_ROLE   = keccak256("ORACLE_ROLE");
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE"); // circuit breaker

    // ─── Enums ───────────────────────────────────────────────────────────────

    enum ProposalStatus {
        PENDING,        // creada, en deliberación C2
        C2_APPROVED,    // quórum C2 alcanzado, escalada a C1
        C1_APPROVED,    // aprobada por C1, en timelock
        EXECUTED,       // ejecutada
        REJECTED,       // rechazada por C1
        CANCELLED,      // cancelada por proponente o gobernanza
        EXPIRED         // sin actividad en plazo máximo
    }

    enum ProposalType {
        STANDARD,       // propuesta operativa normal
        CONSTITUTIONAL, // modifica invariantes — requiere superquórum
        EMERGENCY       // respuesta a crisis — ventanas reducidas
    }

    // ─── Structs ─────────────────────────────────────────────────────────────

    struct Proposal {
        uint256        id;
        address        proposer;
        string         title;
        string         descriptionHash; // IPFS hash del documento completo
        bytes          callData;        // datos de ejecución on-chain
        address        target;          // contrato destino de la ejecución
        ProposalType   proposalType;
        ProposalStatus status;
        uint256        createdAt;
        uint256        c2VotesFor;
        uint256        c2VotesAgainst;
        uint256        c1VotesFor;
        uint256        c1VotesAgainst;
        uint256        escalatedAt;
        uint256        approvedAt;      // cuando C1 aprueba — inicia timelock
        uint256        executedAt;
        uint256        cycle;
    }

    struct RitualRecord {
        uint256 cycleId;
        uint256 executedAt;
        uint256 expertsRemoved;
        uint256 expertsRotated;
        uint256 resilienceR;
        bool    inValley;
    }

    // ─── State ───────────────────────────────────────────────────────────────

    GovernanceParams public govParams;
    ReputationModule public repModule;

    // Interfaces mínimas a módulos externos (sin import directo)
    address public immunityCoreAddr;
    address public oracleRouterAddr;

    uint256 public proposalCount;
    uint256 public currentCycle;
    uint256 public lastRitualAt;

    mapping(uint256 => Proposal)   public proposals;
    mapping(uint256 => RitualRecord) public ritualHistory;

    // proposalId → voter → voted
    mapping(uint256 => mapping(address => bool)) public c2Voted;
    mapping(uint256 => mapping(address => bool)) public c1Voted;

    // ─── Events ──────────────────────────────────────────────────────────────

    event ProposalCreated(
        uint256 indexed id,
        address indexed proposer,
        ProposalType    proposalType,
        uint256         cycle
    );

    event C2VoteCast(
        uint256 indexed proposalId,
        address indexed voter,
        bool            inFavor,
        uint256         c2VotesFor,
        uint256         c2VotesAgainst
    );

    event ProposalEscalated(
        uint256 indexed proposalId,
        uint256         c2VotesFor,
        uint256         c2VotesAgainst
    );

    event C1VoteCast(
        uint256 indexed proposalId,
        address indexed voter,
        bool            inFavor,
        uint256         c1VotesFor,
        uint256         c1VotesAgainst
    );

    event ProposalApproved(uint256 indexed proposalId, uint256 executableAt);
    event ProposalRejected(uint256 indexed proposalId);
    event ProposalExecuted(uint256 indexed proposalId, bool success);
    event ProposalCancelled(uint256 indexed proposalId);
    event ProposalExpired(uint256 indexed proposalId);

    event RitualExecuted(
        uint256 indexed cycleId,
        uint256         expertsRemoved,
        uint256         resilienceR,
        bool            inValley
    );

    event EmergencyPause(address indexed triggeredBy, uint256 timestamp);
    event EmergencyUnpause(address indexed triggeredBy, uint256 timestamp);

    // ─── Constructor ─────────────────────────────────────────────────────────

    constructor(
        address admin,
        address _govParams,
        address _repModule,
        address _immunityCore,
        address _oracleRouter
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(GUARDIAN_ROLE,      admin);

        govParams        = GovernanceParams(_govParams);
        repModule        = ReputationModule(_repModule);
        immunityCoreAddr = _immunityCore;
        oracleRouterAddr = _oracleRouter;

        currentCycle = 1;
        lastRitualAt = block.timestamp;
    }

    // ─── Proposal Lifecycle ───────────────────────────────────────────────────

    /// @notice C2: Crea una nueva propuesta
    /// @param title          Título breve de la propuesta
    /// @param descriptionHash Hash IPFS del documento completo
    /// @param callData       Datos de ejecución (vacío si es señal sin ejecución)
    /// @param target         Contrato destino (address(0) si no hay ejecución)
    /// @param proposalType   Tipo de propuesta
    function createProposal(
        string calldata title,
        string calldata descriptionHash,
        bytes  calldata callData,
        address         target,
        ProposalType    proposalType
    ) external onlyRole(C2_ROLE) whenNotPaused returns (uint256 proposalId) {
        proposalId = ++proposalCount;

        proposals[proposalId] = Proposal({
            id:               proposalId,
            proposer:         msg.sender,
            title:            title,
            descriptionHash:  descriptionHash,
            callData:         callData,
            target:           target,
            proposalType:     proposalType,
            status:           ProposalStatus.PENDING,
            createdAt:        block.timestamp,
            c2VotesFor:       0,
            c2VotesAgainst:   0,
            c1VotesFor:       0,
            c1VotesAgainst:   0,
            escalatedAt:      0,
            approvedAt:       0,
            executedAt:       0,
            cycle:            currentCycle
        });

        emit ProposalCreated(proposalId, msg.sender, proposalType, currentCycle);
    }

    /// @notice C2: Vota una propuesta en deliberación
    function voteProposal(uint256 proposalId, bool inFavor)
        external onlyRole(C2_ROLE) whenNotPaused
    {
        Proposal storage p = proposals[proposalId];
        require(p.status == ProposalStatus.PENDING, "FMDDAOCore: not in C2 deliberation");
        require(!c2Voted[proposalId][msg.sender],   "FMDDAOCore: already voted");

        c2Voted[proposalId][msg.sender] = true;

        if (inFavor) { p.c2VotesFor++;     }
        else          { p.c2VotesAgainst++; }

        emit C2VoteCast(proposalId, msg.sender, inFavor, p.c2VotesFor, p.c2VotesAgainst);
    }

    /// @notice C2: Escala la propuesta a C1 si se alcanzó el quórum
    /// @dev Cualquier miembro C2 puede disparar el escalado una vez hay quórum
    function escalateToC1(uint256 proposalId) external whenNotPaused {
        Proposal storage p = proposals[proposalId];
        require(p.status == ProposalStatus.PENDING, "FMDDAOCore: not pending");

        uint256 totalC2Votes = p.c2VotesFor + p.c2VotesAgainst;
        require(totalC2Votes > 0, "FMDDAOCore: no votes");

        uint256 quorumBps = _getQuorum(p.proposalType);
        uint256 approvalBps = (p.c2VotesFor * 10_000) / totalC2Votes;

        require(approvalBps >= quorumBps, "FMDDAOCore: C2 quorum not reached");

        p.status      = ProposalStatus.C2_APPROVED;
        p.escalatedAt = block.timestamp;

        emit ProposalEscalated(proposalId, p.c2VotesFor, p.c2VotesAgainst);
    }

    /// @notice C1: Vota una propuesta escalada
    function c1Vote(uint256 proposalId, bool inFavor)
        external onlyRole(C1_ROLE) whenNotPaused
    {
        Proposal storage p = proposals[proposalId];
        require(p.status == ProposalStatus.C2_APPROVED, "FMDDAOCore: not in C1 review");
        require(!c1Voted[proposalId][msg.sender],        "FMDDAOCore: already voted");

        // C1 solo puede votar si tiene reputación activa por encima del umbral
        uint256 rep = repModule.getCurrentReputation(msg.sender);
        require(rep >= govParams.get("RENEWAL_THRESHOLD"), "FMDDAOCore: rep below threshold");

        c1Voted[proposalId][msg.sender] = true;

        if (inFavor) { p.c1VotesFor++;     }
        else          { p.c1VotesAgainst++; }

        emit C1VoteCast(proposalId, msg.sender, inFavor, p.c1VotesFor, p.c1VotesAgainst);

        // Intentar resolución anticipada
        _tryC1Resolution(proposalId);
    }

    /// @notice Ejecuta una propuesta aprobada una vez pasado el timelock
    function executeProposal(uint256 proposalId)
        external nonReentrant whenNotPaused
    {
        Proposal storage p = proposals[proposalId];
        require(p.status == ProposalStatus.C1_APPROVED, "FMDDAOCore: not approved");

        uint256 timelockDays = p.proposalType == ProposalType.CONSTITUTIONAL
            ? govParams.get("TIMELOCK_CRISIS")   // más largo para constitucionales
            : govParams.get("TIMELOCK_NORMAL");

        require(
            block.timestamp >= p.approvedAt + timelockDays * 1 days,
            "FMDDAOCore: timelock not elapsed"
        );

        p.status     = ProposalStatus.EXECUTED;
        p.executedAt = block.timestamp;

        bool success = true;
        if (p.target != address(0) && p.callData.length > 0) {
            (success,) = p.target.call(p.callData);
        }

        emit ProposalExecuted(proposalId, success);
    }

    /// @notice Cancela una propuesta (proponente o gobernanza)
    function cancelProposal(uint256 proposalId) external {
        Proposal storage p = proposals[proposalId];
        require(
            msg.sender == p.proposer || hasRole(DEFAULT_ADMIN_ROLE, msg.sender),
            "FMDDAOCore: not authorized"
        );
        require(
            p.status == ProposalStatus.PENDING ||
            p.status == ProposalStatus.C2_APPROVED,
            "FMDDAOCore: cannot cancel"
        );

        p.status = ProposalStatus.CANCELLED;
        emit ProposalCancelled(proposalId);
    }

    // ─── Ritual Trimestral ────────────────────────────────────────────────────

    /// @notice Ejecuta el Ritual Trimestral de mantenimiento del sistema
    /// @dev Puede ser llamado por cualquiera una vez pasado el plazo del ciclo.
    ///      No requiere rol especial — el tiempo es el único requisito.
    function triggerRitual() external nonReentrant whenNotPaused {
        uint256 cycleDays = govParams.get("CYCLE_DAYS");
        require(
            block.timestamp >= lastRitualAt + cycleDays * 1 days,
            "FMDDAOCore: ritual not due"
        );

        // 1. Aplicar decay en lote a todos los expertos C1
        repModule.updateDecayBatch();

        // 2. Contar expertos removidos automáticamente por umbral
        //    (ya ocurrió dentro de updateDecayBatch)
        (address[] memory activeExperts, uint256[] memory reps) =
            repModule.getActiveExperts();

        uint256 removedCount = 0;
        for (uint256 i = 0; i < reps.length; i++) {
            if (reps[i] < govParams.get("RENEWAL_THRESHOLD")) {
                removedCount++;
            }
        }

        // 3. Calcular R y verificar Valle de Resiliencia
        (bool inValley, uint256 R) = repModule.isInResilienceValley();

        // 4. Registrar el ritual
        RitualRecord memory record = RitualRecord({
            cycleId:         currentCycle,
            executedAt:      block.timestamp,
            expertsRemoved:  removedCount,
            expertsRotated:  0, // la rotación por lotería se gestiona off-chain con C1
            resilienceR:     R,
            inValley:        inValley
        });
        ritualHistory[currentCycle] = record;

        // 5. Avanzar ciclo
        repModule.advanceCycle();
        currentCycle++;
        lastRitualAt = block.timestamp;

        // 6. Notificar al sistema inmune si R está fuera del Valle
        if (!inValley) {
            _notifyImmunityCore(R);
        }

        emit RitualExecuted(currentCycle - 1, removedCount, R, inValley);
    }

    // ─── Emergency ────────────────────────────────────────────────────────────

    /// @notice Pausa de emergencia — solo GUARDIAN_ROLE
    function emergencyPause() external onlyRole(GUARDIAN_ROLE) {
        _pause();
        emit EmergencyPause(msg.sender, block.timestamp);
    }

    /// @notice Reanuda el sistema tras pausa
    function emergencyUnpause() external onlyRole(GUARDIAN_ROLE) {
        _unpause();
        emit EmergencyUnpause(msg.sender, block.timestamp);
    }

    // ─── Internal ────────────────────────────────────────────────────────────

    /// @notice Intenta resolver la votación de C1 si hay mayoría clara
    function _tryC1Resolution(uint256 proposalId) internal {
        Proposal storage p = proposals[proposalId];
        uint256 total = p.c1VotesFor + p.c1VotesAgainst;
        if (total == 0) return;

        uint256 quorumBps = _getQuorum(p.proposalType);

        // Necesitamos al menos quórum de votos para resolver
        // (simplificado: quórum sobre el total de C1 activos no implementado aquí
        //  por costo de gas — se gestiona off-chain con verificación del oráculo)
        uint256 approvalBps = (p.c1VotesFor * 10_000) / total;

        if (approvalBps >= quorumBps) {
            p.status     = ProposalStatus.C1_APPROVED;
            p.approvedAt = block.timestamp;

            uint256 timelockDays = p.proposalType == ProposalType.CONSTITUTIONAL
                ? govParams.get("TIMELOCK_CRISIS")
                : govParams.get("TIMELOCK_NORMAL");

            emit ProposalApproved(proposalId, block.timestamp + timelockDays * 1 days);

        } else if ((p.c1VotesAgainst * 10_000) / total > 10_000 - quorumBps) {
            p.status = ProposalStatus.REJECTED;
            emit ProposalRejected(proposalId);
        }
    }

    /// @notice Devuelve el quórum requerido según tipo de propuesta
    function _getQuorum(ProposalType proposalType) internal view returns (uint256) {
        if (proposalType == ProposalType.CONSTITUTIONAL) {
            return 7_500; // superquórum: 75%
        } else if (proposalType == ProposalType.EMERGENCY) {
            return govParams.get("QUORUM_CRISIS_BPS");
        }
        return govParams.get("QUORUM_BPS");
    }

    /// @notice Notifica al ImmunityCore cuando R sale del Valle
    function _notifyImmunityCore(uint256 R) internal {
        // Llamada de bajo nivel para evitar dependencia circular
        // ImmunityCore.receiveResilienceAlert(uint256 R)
        (bool success,) = immunityCoreAddr.call(
            abi.encodeWithSignature("receiveResilienceAlert(uint256)", R)
        );
        // El fallo no revierte — el evento on-chain es suficiente como registro
        if (!success) { /* silencioso — el ritual igual se completa */ }
    }

    // ─── View ─────────────────────────────────────────────────────────────────

    /// @notice Estado completo de una propuesta
    function getProposal(uint256 proposalId)
        external view returns (Proposal memory)
    {
        return proposals[proposalId];
    }

    /// @notice Devuelve si una propuesta está lista para ejecutar
    function isExecutable(uint256 proposalId) external view returns (bool) {
        Proposal memory p = proposals[proposalId];
        if (p.status != ProposalStatus.C1_APPROVED) return false;

        uint256 timelockDays = p.proposalType == ProposalType.CONSTITUTIONAL
            ? govParams.get("TIMELOCK_CRISIS")
            : govParams.get("TIMELOCK_NORMAL");

        return block.timestamp >= p.approvedAt + timelockDays * 1 days;
    }

    /// @notice Devuelve si el Ritual Trimestral está pendiente
    function isRitualDue() external view returns (bool) {
        uint256 cycleDays = govParams.get("CYCLE_DAYS");
        return block.timestamp >= lastRitualAt + cycleDays * 1 days;
    }

    /// @notice Segundos hasta el próximo Ritual Trimestral
    function timeUntilRitual() external view returns (uint256) {
        uint256 cycleDays = govParams.get("CYCLE_DAYS");
        uint256 nextRitual = lastRitualAt + cycleDays * 1 days;
        if (block.timestamp >= nextRitual) return 0;
        return nextRitual - block.timestamp;
    }

    /// @notice Historial completo de rituales ejecutados
    function getRitualRecord(uint256 cycleId)
        external view returns (RitualRecord memory)
    {
        return ritualHistory[cycleId];
    }

    /// @notice Resumen del estado actual del sistema
    function systemStatus() external view returns (
        uint256 cycle,
        uint256 activeExperts,
        uint256 resilienceR,
        bool    inValley,
        bool    paused_,
        bool    ritualDue
    ) {
        cycle = currentCycle;
        (address[] memory experts,) = repModule.getActiveExperts();
        activeExperts = experts.length;
        (inValley, resilienceR) = repModule.isInResilienceValley();
        paused_    = paused();
        uint256 cycleDays = govParams.get("CYCLE_DAYS");
        ritualDue  = block.timestamp >= lastRitualAt + cycleDays * 1 days;
    }
}
