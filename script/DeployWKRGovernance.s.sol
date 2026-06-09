// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {WKR} from "../src/WKR.sol";
import {WKRGovernor} from "../src/WKRGovernor.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

/**
 * @title DeployWKRGovernance
 * @notice Deploy integral: WKR + Timelock + Governor.
 * @dev
 * Variables de entorno esperadas:
 * - PRIVATE_KEY                -> deployer
 * - MULTISIG_OWNER             -> multisig que recibe 1,000,000 WKR y queda owner inicial de WKR
 * - MIN_DELAY_SECONDS          -> delay del timelock (ej 86400 = 1 dia)
 * - VOTING_DELAY_BLOCKS        -> delay de votacion en bloques
 * - VOTING_PERIOD_BLOCKS       -> periodo de votacion en bloques
 * - PROPOSAL_THRESHOLD_TOKENS  -> threshold (sin decimales, se multiplica por 1e18)
 * - QUORUM_PERCENT             -> quorum % (ej 25 = 25%)
 * - TRANSFER_WKR_TO_TIMELOCK   -> true para iniciar handover (pendingOwner=timelock). Requiere acceptOwnership posterior.
 */
contract DeployWKRGovernance is Script {
    uint256 internal constant MIN_TIMELOCK_DELAY_SECONDS = 1 days;
    uint256 internal constant MIN_VOTING_DELAY_BLOCKS = 3_456_000; // ~10 days at 0.25s/block
    uint256 internal constant MIN_VOTING_PERIOD_BLOCKS = 2_419_200; // ~7 days at 0.25s/block
    uint256 internal constant REQUIRED_QUORUM_PERCENT = 25;

    function run() external {
        uint256 deployerPk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPk);
        address multisigOwner = vm.envAddress("MULTISIG_OWNER");

        uint256 minDelaySeconds = vm.envUint("MIN_DELAY_SECONDS");
        uint48 votingDelayBlocks = uint48(vm.envUint("VOTING_DELAY_BLOCKS"));
        uint32 votingPeriodBlocks = uint32(vm.envUint("VOTING_PERIOD_BLOCKS"));
        uint256 proposalThresholdTokens = vm.envUint("PROPOSAL_THRESHOLD_TOKENS");
        uint256 quorumPercent = vm.envUint("QUORUM_PERCENT");
        bool transferWkrToTimelock = vm.envBool("TRANSFER_WKR_TO_TIMELOCK");
        bool strictGovGuardrails = vm.envOr("STRICT_GOV_GUARDRAILS", true);

        require(proposalThresholdTokens == 10_000, "PROPOSAL_THRESHOLD_TOKENS must be 10000");
        if (strictGovGuardrails) {
            require(quorumPercent == REQUIRED_QUORUM_PERCENT, "QUORUM_PERCENT must be 25");
            require(minDelaySeconds >= MIN_TIMELOCK_DELAY_SECONDS, "MIN_DELAY_SECONDS must be >= 1 day");
            require(votingDelayBlocks >= MIN_VOTING_DELAY_BLOCKS, "VOTING_DELAY_BLOCKS must be >= 10 days");
            require(votingPeriodBlocks >= MIN_VOTING_PERIOD_BLOCKS, "VOTING_PERIOD_BLOCKS must be >= 7 days");
        } else {
            require(quorumPercent > 0 && quorumPercent <= 100, "QUORUM_PERCENT out of range");
            require(minDelaySeconds > 0, "MIN_DELAY_SECONDS must be > 0");
            require(votingDelayBlocks > 0, "VOTING_DELAY_BLOCKS must be > 0");
            require(votingPeriodBlocks > 0, "VOTING_PERIOD_BLOCKS must be > 0");
        }

        vm.startBroadcast(deployerPk);

        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](0);

        TimelockController timelock = new TimelockController(minDelaySeconds, proposers, executors, deployer);
        WKR wkr = new WKR(multisigOwner, address(timelock));

        WKRGovernor governor = new WKRGovernor(
            IVotes(address(wkr)),
            timelock,
            votingDelayBlocks,
            votingPeriodBlocks,
            proposalThresholdTokens * 1e18,
            quorumPercent
        );

        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(governor));
        timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), deployer);

        if (transferWkrToTimelock) {
            wkr.transferOwnership(address(timelock));
        }

        vm.stopBroadcast();
    }
}
