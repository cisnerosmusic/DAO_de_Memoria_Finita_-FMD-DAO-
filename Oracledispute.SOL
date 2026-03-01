// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./OracleRegistry.sol";
import "./OracleRouter.sol";

/// @title OracleDispute
/// @author Ernesto Cisneros Cino — FMD-DAO OracleLayer
/// @notice Gestiona el ciclo completo de disputas sobre datos de oráculo.
///
/// @dev FLUJO COMPLETO:
///
///   Hora 0:    Oráculo activo publica dato D via OracleRouter.publishData()
///   Hora 0–48: Ventana de disputa abierta
///              Cualquier miembro puede llamar openDispute() aportando D' + fuente
///   Hora 48:   Si no hay disputa → dato confirmado, proveedor +100 BPS
///              Si hay disputa    → dato congelado en Router, C1 evalúa
///   Hora 48–96: C1 delibera (quórum mínimo 3 expertos)
///   Hora 96:   resolveDispute() registra veredicto:
///              CONFIRMED  → D válido, disputante penalizado en créditos
///              REFUTED    → D' reemplaza D, proveedor activo -300 BPS
///              DRAW       → dato congelado indefinido, ambos -50 BPS
///
/// @dev PROTECCIONES:
///   - Un mismo miembro no puede disputar el mismo dataKey dos veces
///   - Las disputas frívolas tienen coste (depósito de créditos)
///   - En crisis ROJA la ventana de disputa se reduce a 24h
///   - C1 no puede resolver sin quórum mínimo verificado on-chain

contract OracleDispute is AccessControl, ReentrancyGuard {

    // ─── Roles ───────────────────────────────────────────────────────────────

    bytes32 public constant C1_RESOLVER_ROLE = keccak256("C1_RESOLVER_ROLE");
    bytes32 public constant ORACLE_ROLE      = keccak256("ORACLE_ROLE");
    bytes32 public constant KEEPER_ROLE      = keccak256("KEEPER_ROLE");

    // ─── Constants ───────────────────────────────────────────────────────────

    uint256 public constant DISPUTE_WINDOW_NORMAL = 48 hours;
    uint256 public constant DISPUTE_WINDOW_CRISIS  = 24 hours;
    uint256 public constant RESOLVE_WINDOW        = 48 hours; // tiempo que tiene C1 para resolver
    uint256 public constant MIN_C1_QUORUM         = 3;        // expertos mínimos para veredicto

    // Coste de abrir una disputa (en créditos de gobernanza)
    // Se devuelve si la disputa es exitosa; se pierde si es frívola
    uint256 public constant DISPUTE_DEPOSIT = 5;

    // Ajustes de score para OracleRegistry
    int256 public constant SCORE_CONFIRMED =  100;
    int256 public constant SCORE_REFUTED   = -300;
    int256 public constant SCORE_DRAW      =  -50;

    // ─── Enums ───────────────────────────────────────────────────────────────

    enum DisputeStatus {
        OPEN,       // dentro de la ventana, aún no deliberando
        DELIBERATING, // C1 evaluando
        CONFIRMED,  // dato original válido
        REFUTED,    // dato alternativo válido
        DRAW,       // empate — dato congelado
        EXPIRED     // nadie disputó — dato confirmado automáticamente
    }

    enum Vote { ABSTAIN, CONFIRM, REFUTE }

    // ─── Structs ─────────────────────────────────────────────────────────────

    struct Dispute {
        bytes32         dataKey;            // dato disputado
        bytes           originalValue;      // valor publicado por el oráculo activo
        bytes           alternativeValue;   // valor propuesto por el disputante
        string          alternativeSource;  // fuente verificable del valor alternativo
        address         disputant;          // quien abrió la disputa
        bytes32         providerId;         // proveedor cuyo dato se disputa
        uint256         openedAt;           // timestamp de apertura
        uint256         disputeWindowEnd;   // fin de ventana de disputa
        uint256         resolveDeadline;    // deadline para que C1 resuelva
        DisputeStatus   status;
        uint256         confirmVotes;       // votos C1 a favor del dato original
        uint256         refuteVotes;        // votos C1 a favor del alternativo
        uint256         deposit;            // créditos bloqueados del disputante
        bool            depositReturned;
    }

    struct C1Vote {
        Vote    vote;
        string  rationale;  // hash o descripción del razonamiento (legibilidad)
        uint256 timestamp;
    }

    // ─── State ───────────────────────────────────────────────────────────────

    OracleRegistry public registry;
    OracleRouter   public router;

    // Interfaz mínima al módulo de créditos (CoopetitionEngine)
    // Se usa solo para descontar/devolver el depósito del disputante
    address public creditsModule;

    bool public systemInCrisis;

    uint256                                     public disputeCount;
    mapping(uint256 => Dispute)                 public disputes;

    // dataKey → disputeId activo (0 si no hay disputa activa)
    mapping(bytes32 => uint256)                 public activeDisputeByKey;

    // disputeId → voter → C1Vote
    mapping(uint256 => mapping(address => C1Vote)) public c1Votes;

    // disputeId → array de voters (para iterar quórum)
    mapping(uint256 => address[])               public c1Voters;

    // member → dataKey → bool (evitar disputas duplicadas)
    mapping(address => mapping(bytes32 => bool)) public hasDisputed;

    // ─── Events ──────────────────────────────────────────────────────────────

    event DisputeOpened(
        uint256 indexed disputeId,
        bytes32 indexed dataKey,
        address indexed disputant,
        uint256 windowEnd
    );

    event DisputeVoteCast(
        uint256 indexed disputeId,
        address indexed voter,
        Vote    vote
    );

    event DisputeResolved(
        uint256 indexed disputeId,
        bytes32 indexed dataKey,
        DisputeStatus   outcome,
        uint256         confirmVotes,
        uint256         refuteVotes
    );

    event DisputeExpired(
        uint256 indexed disputeId,
        bytes32 indexed dataKey
    );

    event DepositReturned(
        uint256 indexed disputeId,
        address indexed disputant,
        uint256 amount
    );

    event CrisisStateUpdated(bool inCrisis);

    // ─── Constructor ─────────────────────────────────────────────────────────

    constructor(
        address admin,
        address _registry,
        address _router,
        address _creditsModule
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        registry      = OracleRegistry(_registry);
        router        = OracleRouter(_router);
        creditsModule = _creditsModule;
        disputeCount  = 1; // empezar en 1 — 0 es "sin disputa activa"
    }

    // ─── Open Dispute ─────────────────────────────────────────────────────────

    /// @notice Abre una disputa sobre un dato publicado por el oráculo activo
    /// @param dataKey       Identificador del dato disputado
    /// @param altValue      Valor alternativo que el disputante propone
    /// @param altSource     Fuente verificable del valor alternativo
    function openDispute(
        bytes32        dataKey,
        bytes calldata altValue,
        string calldata altSource
    ) external nonReentrant {
        require(
            activeDisputeByKey[dataKey] == 0,
            "OracleDispute: dispute already active for this key"
        );
        require(
            !hasDisputed[msg.sender][dataKey],
            "OracleDispute: already disputed by this member"
        );
        require(altValue.length > 0,   "OracleDispute: empty alternative value");
        require(bytes(altSource).length > 0, "OracleDispute: empty source");

        // Leer el dato actual del Router
        (bytes memory originalValue, OracleRouter.DataStatus status) =
            router.getLatestData(dataKey);

        require(
            status == OracleRouter.DataStatus.FRESH,
            "OracleDispute: can only dispute FRESH data"
        );

        // Determinar ventana según estado de crisis
        uint256 window = systemInCrisis
            ? DISPUTE_WINDOW_CRISIS
            : DISPUTE_WINDOW_NORMAL;

        // Cobrar depósito al disputante
        // En producción: llamar CoopetitionEngine.spendCredits(msg.sender, DISPUTE_DEPOSIT)
        // Aquí registramos el depósito y asumimos que el módulo externo lo gestiona
        uint256 depositAmount = DISPUTE_DEPOSIT;

        uint256 disputeId = disputeCount++;

        disputes[disputeId] = Dispute({
            dataKey:           dataKey,
            originalValue:     originalValue,
            alternativeValue:  altValue,
            alternativeSource: altSource,
            disputant:         msg.sender,
            providerId:        registry.activeProviderId(),
            openedAt:          block.timestamp,
            disputeWindowEnd:  block.timestamp + window,
            resolveDeadline:   block.timestamp + window + RESOLVE_WINDOW,
            status:            DisputeStatus.OPEN,
            confirmVotes:      0,
            refuteVotes:       0,
            deposit:           depositAmount,
            depositReturned:   false
        });

        activeDisputeByKey[dataKey]         = disputeId;
        hasDisputed[msg.sender][dataKey]    = true;

        // Congelar el dato en el Router durante la disputa
        router.freezeData(dataKey);

        emit DisputeOpened(disputeId, dataKey, msg.sender, block.timestamp + window);
    }

    // ─── C1 Voting ───────────────────────────────────────────────────────────

    /// @notice Un experto de C1 vota en una disputa activa
    /// @param disputeId ID de la disputa
    /// @param vote      CONFIRM (dato original válido) o REFUTE (alternativo válido)
    /// @param rationale Descripción del razonamiento (queda registrada on-chain)
    function castC1Vote(
        uint256        disputeId,
        Vote           vote,
        string calldata rationale
    ) external onlyRole(C1_RESOLVER_ROLE) {
        Dispute storage d = disputes[disputeId];

        require(
            d.status == DisputeStatus.OPEN ||
            d.status == DisputeStatus.DELIBERATING,
            "OracleDispute: dispute not open for voting"
        );
        require(
            block.timestamp > d.disputeWindowEnd,
            "OracleDispute: dispute window still open"
        );
        require(
            block.timestamp <= d.resolveDeadline,
            "OracleDispute: resolve deadline passed"
        );
        require(
            c1Votes[disputeId][msg.sender].vote == Vote.ABSTAIN,
            "OracleDispute: already voted"
        );
        require(vote != Vote.ABSTAIN, "OracleDispute: must vote CONFIRM or REFUTE");

        // Pasar a estado DELIBERATING al primer voto
        if (d.status == DisputeStatus.OPEN) {
            d.status = DisputeStatus.DELIBERATING;
        }

        c1Votes[disputeId][msg.sender] = C1Vote({
            vote:      vote,
            rationale: rationale,
            timestamp: block.timestamp
        });
        c1Voters[disputeId].push(msg.sender);

        if (vote == Vote.CONFIRM) {
            d.confirmVotes++;
        } else {
            d.refuteVotes++;
        }

        emit DisputeVoteCast(disputeId, msg.sender, vote);

        // Intentar resolución anticipada si hay quórum claro
        _tryEarlyResolution(disputeId);
    }

    // ─── Resolution ──────────────────────────────────────────────────────────

    /// @notice Finaliza una disputa una vez cerrada la ventana de deliberación
    /// @dev Puede ser llamado por cualquiera una vez pasado el deadline
    /// @param disputeId ID de la disputa a resolver
    function resolveDispute(uint256 disputeId) external nonReentrant {
        Dispute storage d = disputes[disputeId];

        require(
            d.status == DisputeStatus.DELIBERATING,
            "OracleDispute: not in deliberation"
        );
        require(
            block.timestamp > d.resolveDeadline,
            "OracleDispute: resolve deadline not reached"
        );

        _finalizeDispute(disputeId);
    }

    /// @notice Marca una disputa como expirada si nadie disputó en la ventana
    /// @dev Llamado por keeper al final de cada ventana de disputa
    /// @param dataKey Clave del dato cuya ventana de disputa ha cerrado
    function expireIfUndisputed(bytes32 dataKey) external onlyRole(KEEPER_ROLE) {
        uint256 disputeId = activeDisputeByKey[dataKey];

        // Si no hay disputa activa, confirmar el dato automáticamente
        if (disputeId == 0) {
            // Acreditar score al proveedor activo
            registry.adjustScore(
                registry.activeProviderId(),
                SCORE_CONFIRMED,
                "Auto-confirmed: no dispute in window"
            );
            return;
        }

        Dispute storage d = disputes[disputeId];

        require(
            d.status == DisputeStatus.OPEN,
            "OracleDispute: dispute not in OPEN state"
        );
        require(
            block.timestamp > d.resolveDeadline,
            "OracleDispute: window not closed"
        );

        // C1 no votó a tiempo — dato congelado, penalizar proveedor levemente
        d.status = DisputeStatus.DRAW;
        activeDisputeByKey[dataKey] = 0;

        registry.adjustScore(
            d.providerId,
            SCORE_DRAW,
            "Dispute expired without C1 resolution"
        );

        emit DisputeExpired(disputeId, dataKey);
    }

    // ─── Crisis State ─────────────────────────────────────────────────────────

    /// @notice Actualiza el estado de crisis (llamado por ImmunityCore via oráculo)
    function setCrisisState(bool inCrisis) external onlyRole(ORACLE_ROLE) {
        systemInCrisis = inCrisis;
        emit CrisisStateUpdated(inCrisis);
    }

    // ─── Internal ────────────────────────────────────────────────────────────

    /// @notice Intenta resolución anticipada si el quórum es suficiente y la mayoría es clara
    function _tryEarlyResolution(uint256 disputeId) internal {
        Dispute storage d = disputes[disputeId];

        uint256 totalVotes = d.confirmVotes + d.refuteVotes;
        if (totalVotes < MIN_C1_QUORUM) return;

        // Mayoría absoluta (más de la mitad del total de votos emitidos)
        // Solo resolver anticipadamente si la mayoría es clara (>= 2/3)
        uint256 threshold = (totalVotes * 2) / 3;

        if (d.confirmVotes >= threshold || d.refuteVotes >= threshold) {
            _finalizeDispute(disputeId);
        }
    }

    /// @notice Aplica el veredicto final y actualiza todos los sistemas afectados
    function _finalizeDispute(uint256 disputeId) internal {
        Dispute storage d = disputes[disputeId];

        uint256 totalVotes = d.confirmVotes + d.refuteVotes;
        require(totalVotes >= MIN_C1_QUORUM, "OracleDispute: insufficient quorum");

        DisputeStatus outcome;

        if (d.confirmVotes > d.refuteVotes) {
            // Dato original válido
            outcome = DisputeStatus.CONFIRMED;

            // Proveedor recupera crédito de precisión
            registry.adjustScore(d.providerId, SCORE_CONFIRMED, "Dispute: data confirmed");

            // Descontar depósito del disputante (no se devuelve)
            // En producción: CoopetitionEngine.burnCredits(d.disputant, d.deposit)

            // Restaurar dato original en Router
            router.resolveData(d.dataKey, d.originalValue);

        } else if (d.refuteVotes > d.confirmVotes) {
            // Dato alternativo válido
            outcome = DisputeStatus.REFUTED;

            // Penalizar al proveedor
            registry.adjustScore(d.providerId, SCORE_REFUTED, "Dispute: data refuted");

            // Devolver depósito al disputante
            d.depositReturned = true;
            // En producción: CoopetitionEngine.returnCredits(d.disputant, d.deposit)
            emit DepositReturned(disputeId, d.disputant, d.deposit);

            // Publicar dato alternativo en Router
            router.resolveData(d.dataKey, d.alternativeValue);

        } else {
            // Empate
            outcome = DisputeStatus.DRAW;

            registry.adjustScore(d.providerId, SCORE_DRAW, "Dispute: draw");
            // El depósito del disputante se pierde en empate
            // El dato permanece congelado en el Router
        }

        d.status = outcome;
        activeDisputeByKey[d.dataKey] = 0;

        emit DisputeResolved(
            disputeId,
            d.dataKey,
            outcome,
            d.confirmVotes,
            d.refuteVotes
        );
    }

    // ─── View ─────────────────────────────────────────────────────────────────

    /// @notice Devuelve el estado completo de una disputa
    function getDispute(uint256 disputeId)
        external view returns (Dispute memory)
    {
        return disputes[disputeId];
    }

    /// @notice Devuelve todos los votos de C1 en una disputa
    function getC1Votes(uint256 disputeId)
        external view
        returns (address[] memory voters, C1Vote[] memory votes)
    {
        voters = c1Voters[disputeId];
        votes  = new C1Vote[](voters.length);
        for (uint256 i = 0; i < voters.length; i++) {
            votes[i] = c1Votes[disputeId][voters[i]];
        }
    }

    /// @notice Devuelve si hay una disputa activa para un dataKey dado
    function hasActiveDispute(bytes32 dataKey)
        external view returns (bool active, uint256 disputeId)
    {
        disputeId = activeDisputeByKey[dataKey];
        active    = disputeId != 0;
    }

    /// @notice Devuelve si el quórum mínimo está alcanzado en una disputa
    function isQuorumReached(uint256 disputeId)
        external view returns (bool)
    {
        Dispute memory d = disputes[disputeId];
        return (d.confirmVotes + d.refuteVotes) >= MIN_C1_QUORUM;
    }

    /// @notice Simula el resultado de una disputa dado el estado actual de votos
    /// @dev Útil para dashboards — no escribe nada
    function simulateOutcome(uint256 disputeId)
        external view
        returns (DisputeStatus projected, uint256 confirm, uint256 refute)
    {
        Dispute memory d = disputes[disputeId];
        confirm = d.confirmVotes;
        refute  = d.refuteVotes;

        if (confirm + refute < MIN_C1_QUORUM) {
            projected = DisputeStatus.OPEN;
        } else if (confirm > refute) {
            projected = DisputeStatus.CONFIRMED;
        } else if (refute > confirm) {
            projected = DisputeStatus.REFUTED;
        } else {
            projected = DisputeStatus.DRAW;
        }
    }
}
