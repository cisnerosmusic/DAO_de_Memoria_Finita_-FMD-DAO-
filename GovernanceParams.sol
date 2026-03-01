// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";

/// @title GovernanceParams
/// @author Ernesto Cisneros Cino — FMD-DAO Core
/// @notice Repositorio central de parámetros de gobernanza.
///         Todos los módulos leen de aquí — ninguno hardcodea valores críticos.
///         Los cambios pasan por timelock obligatorio.
contract GovernanceParams is AccessControl {

    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");
    bytes32 public constant TIMELOCK_ROLE   = keccak256("TIMELOCK_ROLE");

    uint256 public constant MIN_TIMELOCK = 2 days;
    uint256 public constant MAX_TIMELOCK = 30 days;

    struct Param {
        uint256 value;
        uint256 proposedValue;
        uint256 proposedAt;
        uint256 timelockDuration;
        bool    pendingChange;
        string  description;
    }

    mapping(bytes32 => Param) public params;
    bytes32[] public paramKeys;

    event ParamProposed(bytes32 indexed key, uint256 oldValue, uint256 newValue, uint256 executableAt);
    event ParamExecuted(bytes32 indexed key, uint256 newValue);
    event ParamCancelled(bytes32 indexed key);

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        // Inicializar parámetros base del sistema
        _initParam("TAU_DAO",             60,    14 days, "Memoria DAO en dias");
        _initParam("TAU_IA",              990,   14 days, "Memoria IA en dias (33 meses)");
        _initParam("OMEGA",               1667,  7  days, "Frecuencia ciclos x1000 (1/60 dias)");
        _initParam("LAMBDA_BPS",          1155,  14 days, "Lambda decay x10^7 por segundo");
        _initParam("QUORUM_BPS",          1000,  7  days, "Quorum normal en BPS (10%)");
        _initParam("QUORUM_CRISIS_BPS",   4000,  2  days, "Quorum crisis en BPS (40%)");
        _initParam("TIMELOCK_NORMAL",     2,     7  days, "Timelock normal en dias");
        _initParam("TIMELOCK_CRISIS",     14,    2  days, "Timelock crisis en dias");
        _initParam("RENEWAL_THRESHOLD",   500,   14 days, "Umbral remocion reputacion BPS (5%)");
        _initParam("CYCLE_DAYS",          90,    14 days, "Duracion ciclo trimestral en dias");
        _initParam("NOISE_AMPLITUDE_BPS", 300,   7  days, "Amplitud ruido estabilizador BPS (3%)");
        _initParam("BONUS_PERCENT_BPS",   2000,  7  days, "Porcentaje bonus coopeticion BPS (20%)");
    }

    function _initParam(
        string memory key,
        uint256 value,
        uint256 timelockDuration,
        string memory description
    ) internal {
        bytes32 k = keccak256(bytes(key));
        params[k] = Param({
            value:            value,
            proposedValue:    0,
            proposedAt:       0,
            timelockDuration: timelockDuration,
            pendingChange:    false,
            description:      description
        });
        paramKeys.push(k);
    }

    /// @notice Propone un cambio de parámetro — inicia el timelock
    function proposeChange(bytes32 key, uint256 newValue)
        external onlyRole(GOVERNANCE_ROLE)
    {
        Param storage p = params[key];
        require(p.timelockDuration > 0, "GovernanceParams: unknown key");
        require(!p.pendingChange,       "GovernanceParams: change already pending");

        p.proposedValue  = newValue;
        p.proposedAt     = block.timestamp;
        p.pendingChange  = true;

        emit ParamProposed(key, p.value, newValue, block.timestamp + p.timelockDuration);
    }

    /// @notice Ejecuta el cambio una vez pasado el timelock
    function executeChange(bytes32 key) external {
        Param storage p = params[key];
        require(p.pendingChange, "GovernanceParams: no pending change");
        require(
            block.timestamp >= p.proposedAt + p.timelockDuration,
            "GovernanceParams: timelock not elapsed"
        );

        p.value         = p.proposedValue;
        p.pendingChange = false;

        emit ParamExecuted(key, p.value);
    }

    /// @notice Cancela un cambio pendiente (gobernanza puede vetar)
    function cancelChange(bytes32 key) external onlyRole(GOVERNANCE_ROLE) {
        Param storage p = params[key];
        require(p.pendingChange, "GovernanceParams: no pending change");
        p.pendingChange = false;
        emit ParamCancelled(key);
    }

    /// @notice Lectura directa de un parámetro por clave string
    function get(string calldata key) external view returns (uint256) {
        return params[keccak256(bytes(key))].value;
    }

    function getByKey(bytes32 key) external view returns (uint256) {
        return params[key].value;
    }

    function getAllKeys() external view returns (bytes32[] memory) {
        return paramKeys;
    }
}
