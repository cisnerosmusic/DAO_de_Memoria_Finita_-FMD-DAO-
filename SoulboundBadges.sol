// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/// @title SoulboundBadges
/// @author Ernesto Cisneros Cino — FMD-DAO HumanLayer
/// @notice NFT no transferibles (soulbound) otorgados por logros verificados.
///         Cada badge representa un hito específico, medible y on-chain.
///
/// @dev TIPOS DE BADGE (11 niveles en 4 categorías):
///
///   COMPRENSIÓN:
///     PROOF_SEEKER_BRONZE   — 5 PoU enviados
///     PROOF_SEEKER_SILVER   — 20 PoU enviados
///     PROOF_SEEKER_GOLD     — 50 PoU válidos
///
///   PROPUESTA:
///     PROPOSER_NOVICE       — primera propuesta aprobada
///     PROPOSER_VETERAN      — 10 propuestas aprobadas
///     PROPOSER_ARCHITECT    — propuesta constitucional aprobada
///
///   RESILIENCIA:
///     VALLEY_GUARDIAN       — participó en resolución de crisis ROJA
///     RITUAL_KEEPER         — triggerRitual() ejecutado 4 veces
///
///   COOPETICIÓN:
///     BRIDGE_BUILDER        — votó en ambos lados en el mismo ciclo con justificación
///     CREDIT_TITAN          — acumuló 1000 créditos en un ciclo
///     CYCLE_COMPLETE        — completó un ciclo completo sin ausencias
///
/// @dev SOULBOUND:
///   _update() restringe transferencias. Solo el contrato puede mover tokens:
///   mint (from=address(0)) y burn (to=address(0)) están permitidos.
///   Toda transferencia entre cuentas es revertida.

contract SoulboundBadges is ERC721, AccessControl {

    using Strings for uint256;

    // ─── Roles ───────────────────────────────────────────────────────────────

    bytes32 public constant MINTER_ROLE    = keccak256("MINTER_ROLE");
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");

    // ─── Badge Types ──────────────────────────────────────────────────────────

    uint8 public constant PROOF_SEEKER_BRONZE   = 0;
    uint8 public constant PROOF_SEEKER_SILVER   = 1;
    uint8 public constant PROOF_SEEKER_GOLD     = 2;
    uint8 public constant PROPOSER_NOVICE       = 3;
    uint8 public constant PROPOSER_VETERAN      = 4;
    uint8 public constant PROPOSER_ARCHITECT    = 5;
    uint8 public constant VALLEY_GUARDIAN       = 6;
    uint8 public constant RITUAL_KEEPER         = 7;
    uint8 public constant BRIDGE_BUILDER        = 8;
    uint8 public constant CREDIT_TITAN          = 9;
    uint8 public constant CYCLE_COMPLETE        = 10;

    uint8 public constant BADGE_TYPE_COUNT = 11;

    // ─── Structs ─────────────────────────────────────────────────────────────

    struct BadgeMetadata {
        uint8   badgeType;
        address owner;
        uint256 awardedAt;
        uint256 cycle;
        string  achievement;  // descripción específica del logro on-chain
    }

    // ─── State ───────────────────────────────────────────────────────────────

    uint256 public totalSupply;
    string  public baseTokenURI;

    mapping(uint256 => BadgeMetadata) public badgeData;

    // owner → badgeType → tokenId (0 = no tiene)
    mapping(address => mapping(uint8 => uint256)) public ownedBadge;

    // owner → lista de tokenIds
    mapping(address => uint256[]) public badgesOf;

    // badgeType → metadata fija del tipo
    mapping(uint8 => string) public badgeTypeName;
    mapping(uint8 => string) public badgeTypeDescription;

    // ─── Events ──────────────────────────────────────────────────────────────

    event BadgeAwarded(
        uint256 indexed tokenId,
        address indexed recipient,
        uint8   indexed badgeType,
        string  achievement,
        uint256 cycle
    );

    event BadgeRevoked(
        uint256 indexed tokenId,
        address indexed from,
        uint8   badgeType,
        string  reason
    );

    event BaseURIUpdated(string newBaseURI);

    // ─── Constructor ─────────────────────────────────────────────────────────

    constructor(address admin, string memory _baseTokenURI)
        ERC721("FMD-DAO Soulbound Badges", "FMDB")
    {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        baseTokenURI = _baseTokenURI;
        _initBadgeTypes();
    }

    // ─── Mint ─────────────────────────────────────────────────────────────────

    /// @notice Otorga un badge a un miembro por un logro verificado
    /// @param recipient   Dirección del recipiente
    /// @param badgeType   Tipo de badge (0–10)
    /// @param achievement Descripción específica del logro (para el historial)
    /// @param cycle       Ciclo en que se otorga
    function awardBadge(
        address        recipient,
        uint8          badgeType,
        string calldata achievement,
        uint256        cycle
    ) external onlyRole(MINTER_ROLE) returns (uint256 tokenId) {
        require(badgeType < BADGE_TYPE_COUNT, "SoulboundBadges: invalid type");
        require(recipient != address(0),      "SoulboundBadges: zero address");
        require(
            ownedBadge[recipient][badgeType] == 0,
            "SoulboundBadges: badge already owned"
        );

        tokenId = ++totalSupply;

        badgeData[tokenId] = BadgeMetadata({
            badgeType:   badgeType,
            owner:       recipient,
            awardedAt:   block.timestamp,
            cycle:       cycle,
            achievement: achievement
        });

        ownedBadge[recipient][badgeType] = tokenId;
        badgesOf[recipient].push(tokenId);

        _mint(recipient, tokenId);

        emit BadgeAwarded(tokenId, recipient, badgeType, achievement, cycle);
    }

    /// @notice Revoca un badge (por circunstancias excepcionales verificadas)
    /// @dev Solo gobernanza puede revocar. El historial del evento permanece.
    function revokeBadge(uint256 tokenId, string calldata reason)
        external onlyRole(GOVERNANCE_ROLE)
    {
        require(_ownerOf(tokenId) != address(0), "SoulboundBadges: nonexistent token");

        BadgeMetadata memory meta = badgeData[tokenId];
        address owner = meta.owner;

        ownedBadge[owner][meta.badgeType] = 0;

        // Limpiar del array de badges del owner
        uint256[] storage ownerBadges = badgesOf[owner];
        for (uint256 i = 0; i < ownerBadges.length; i++) {
            if (ownerBadges[i] == tokenId) {
                ownerBadges[i] = ownerBadges[ownerBadges.length - 1];
                ownerBadges.pop();
                break;
            }
        }

        emit BadgeRevoked(tokenId, owner, meta.badgeType, reason);
        _burn(tokenId);
    }

    // ─── Soulbound enforcement ────────────────────────────────────────────────

    /// @notice Bloquea todas las transferencias entre cuentas
    /// @dev Override de ERC721._update(). Solo permite mint (from=0) y burn (to=0)
    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal override returns (address) {
        address from = _ownerOf(tokenId);

        // Permitir mint (from == address(0)) y burn (to == address(0))
        require(
            from == address(0) || to == address(0),
            "SoulboundBadges: non-transferable"
        );

        return super._update(to, tokenId, auth);
    }

    // ─── Governance ──────────────────────────────────────────────────────────

    /// @notice Actualiza la URI base de los metadatos
    function setBaseURI(string calldata newBaseURI)
        external onlyRole(GOVERNANCE_ROLE)
    {
        baseTokenURI = newBaseURI;
        emit BaseURIUpdated(newBaseURI);
    }

    // ─── View ─────────────────────────────────────────────────────────────────

    /// @notice URI de metadatos de un token (apunta a IPFS o servidor de metadatos)
    function tokenURI(uint256 tokenId)
        public view override returns (string memory)
    {
        require(_ownerOf(tokenId) != address(0), "SoulboundBadges: nonexistent token");
        return string(abi.encodePacked(baseTokenURI, tokenId.toString(), ".json"));
    }

    /// @notice Todos los badges de un miembro
    function getBadgesOf(address member)
        external view returns (uint256[] memory)
    {
        return badgesOf[member];
    }

    /// @notice Verifica si un miembro tiene un tipo específico de badge
    function hasBadge(address member, uint8 badgeType)
        external view returns (bool)
    {
        return ownedBadge[member][badgeType] != 0;
    }

    /// @notice Metadata completa de un badge
    function getBadgeData(uint256 tokenId)
        external view returns (BadgeMetadata memory)
    {
        return badgeData[tokenId];
    }

    /// @notice Nombre legible de un tipo de badge
    function getBadgeTypeName(uint8 badgeType)
        external view returns (string memory)
    {
        return badgeTypeName[badgeType];
    }

    /// @notice Conteo de badges por tipo en el sistema
    function badgeCountByType(uint8 badgeType)
        external view returns (uint256 count)
    {
        // O(n) sobre totalSupply — solo para uso off-chain o subgraph
        for (uint256 i = 1; i <= totalSupply; i++) {
            if (badgeData[i].badgeType == badgeType &&
                _ownerOf(i) != address(0)) {
                count++;
            }
        }
    }

    // ─── supportsInterface ────────────────────────────────────────────────────

    function supportsInterface(bytes4 interfaceId)
        public view override(ERC721, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    // ─── Internal: init badge types ──────────────────────────────────────────

    function _initBadgeTypes() internal {
        badgeTypeName[PROOF_SEEKER_BRONZE]  = "Proof Seeker Bronze";
        badgeTypeName[PROOF_SEEKER_SILVER]  = "Proof Seeker Silver";
        badgeTypeName[PROOF_SEEKER_GOLD]    = "Proof Seeker Gold";
        badgeTypeName[PROPOSER_NOVICE]      = "Proposer Novice";
        badgeTypeName[PROPOSER_VETERAN]     = "Proposer Veteran";
        badgeTypeName[PROPOSER_ARCHITECT]   = "Proposer Architect";
        badgeTypeName[VALLEY_GUARDIAN]      = "Valley Guardian";
        badgeTypeName[RITUAL_KEEPER]        = "Ritual Keeper";
        badgeTypeName[BRIDGE_BUILDER]       = "Bridge Builder";
        badgeTypeName[CREDIT_TITAN]         = "Credit Titan";
        badgeTypeName[CYCLE_COMPLETE]       = "Cycle Complete";

        badgeTypeDescription[PROOF_SEEKER_BRONZE]  = "Enviaste 5 Proof of Understanding";
        badgeTypeDescription[PROOF_SEEKER_SILVER]  = "Enviaste 20 Proof of Understanding";
        badgeTypeDescription[PROOF_SEEKER_GOLD]    = "50 PoU validados positivamente";
        badgeTypeDescription[PROPOSER_NOVICE]      = "Primera propuesta aprobada por C1";
        badgeTypeDescription[PROPOSER_VETERAN]     = "10 propuestas aprobadas";
        badgeTypeDescription[PROPOSER_ARCHITECT]   = "Propuesta constitucional aprobada";
        badgeTypeDescription[VALLEY_GUARDIAN]      = "Participaste en resolución de crisis ROJA";
        badgeTypeDescription[RITUAL_KEEPER]        = "Ejecutaste triggerRitual() 4 veces";
        badgeTypeDescription[BRIDGE_BUILDER]       = "Votaste en ambos lados en un ciclo con justificación";
        badgeTypeDescription[CREDIT_TITAN]         = "Acumulaste 1000 créditos en un ciclo";
        badgeTypeDescription[CYCLE_COMPLETE]       = "Ciclo completo sin ausencias verificadas";
    }
}
