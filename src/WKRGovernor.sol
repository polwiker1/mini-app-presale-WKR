// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Governor} from "@openzeppelin/contracts/governance/Governor.sol";
import {GovernorSettings} from "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import {GovernorCountingSimple} from "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import {GovernorVotes} from "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import {
    GovernorVotesQuorumFraction
} from "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import {GovernorTimelockControl} from "@openzeppelin/contracts/governance/extensions/GovernorTimelockControl.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

/**
 * @title WKRGovernor
 * @notice Contrato de gobernanza para el token WKR.
 * @dev
 * - Usa votos de un token IVotes (WKR con ERC20Votes)
 * - Define delay, periodo de votacion y threshold configurables en constructor
 * - Ejecuta propuestas a traves de TimelockController (con delay de seguridad)
 */
contract WKRGovernor is
    Governor,
    GovernorSettings,
    GovernorCountingSimple,
    GovernorVotes,
    GovernorVotesQuorumFraction,
    GovernorTimelockControl
{
    /**
     * @notice Delay antes de que una propuesta pase a estado Activa.
     * @dev Override requerido por herencia multiple.
     */
    function votingDelay() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.votingDelay();
    }

    /**
     * @notice Duracion de la ventana de votacion.
     * @dev Override requerido por herencia multiple.
     */
    function votingPeriod() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.votingPeriod();
    }

    /**
     * @notice Votos minimos necesarios para crear propuestas.
     * @dev Override requerido por herencia multiple.
     */
    function proposalThreshold() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.proposalThreshold();
    }

    /**
     * @param tokenAddress Token con soporte IVotes (WKR).
     * @param timelockAddress Timelock que ejecuta las propuestas aprobadas.
     * @param initialVotingDelay Retraso para iniciar votacion (en bloques).
     * @param initialVotingPeriod Duracion de votacion (en bloques).
     * @param initialProposalThreshold Minimo de votos para poder proponer.
     * @param initialQuorumPercent Quorum en porcentaje (ejemplo 4 = 4%).
     */
    constructor(
        IVotes tokenAddress,
        TimelockController timelockAddress,
        uint48 initialVotingDelay,
        uint32 initialVotingPeriod,
        uint256 initialProposalThreshold,
        uint256 initialQuorumPercent
    )
        Governor("WKR Governor")
        GovernorSettings(initialVotingDelay, initialVotingPeriod, initialProposalThreshold)
        GovernorVotes(tokenAddress)
        GovernorVotesQuorumFraction(initialQuorumPercent)
        GovernorTimelockControl(timelockAddress)
    {}

    /**
     * @notice Estado de una propuesta.
     * @dev Override requerido por herencia multiple.
     */
    function state(uint256 proposalId) public view override(Governor, GovernorTimelockControl) returns (ProposalState) {
        return super.state(proposalId);
    }

    /**
     * @notice Indica si la propuesta requiere cola en timelock antes de ejecutarse.
     * @dev Override requerido por herencia multiple.
     */
    function proposalNeedsQueuing(uint256 proposalId)
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (bool)
    {
        return super.proposalNeedsQueuing(proposalId);
    }

    /**
     * @dev Encola operaciones aprobadas en el timelock.
     */
    function _queueOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint48) {
        return super._queueOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    /**
     * @dev Ejecuta operaciones desde el timelock una vez cumplido el delay.
     */
    function _executeOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) {
        super._executeOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    /**
     * @dev Cancela propuestas (incluyendo la operacion timelock asociada).
     */
    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint256) {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }

    /**
     * @dev Define al timelock como ejecutor final de acciones de gobernanza.
     */
    function _executor() internal view override(Governor, GovernorTimelockControl) returns (address) {
        return super._executor();
    }
}
