//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/WKR.sol";
import "../src/WKRGovernor.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";

contract WKRGovernanceTest is Test {
    WKR public wkr;
    TimelockController public timelock;
    WKRGovernor public governor;

    address public owner = address(this);
    address public alice = address(0xA11CE);
    address public bob = address(0xB0B);

    uint256 public constant MINT_AMOUNT = 1_000e18;
    uint256 public constant ALICE_ALLOCATION = 10_000e18;
    event LimitsEnabledUpdated(bool oldValue, bool newValue);
    event MaxTxAmountUpdated(uint256 oldValue, uint256 newValue);
    event MaxWalletAmountUpdated(uint256 oldValue, uint256 newValue);
    event PresaleExemptUpdated(address account, bool oldValue, bool newValue);
    uint256 internal constant WALLET_CAP = 10_000e18;

    function setUp() public {
        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](0);

        timelock = new TimelockController(1 days, proposers, executors, owner);
        wkr = new WKR(owner, address(timelock));
        governor = new WKRGovernor(
            wkr,
            timelock,
            1, // voting delay (blocks)
            10, // voting period (blocks)
            10_000e18, // proposal threshold
            1 // quorum %
        );

        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(governor));
        timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), owner);

        wkr.transfer(alice, ALICE_ALLOCATION);
    }

    function testInitialSupplyAndOwner() public view {
        assertEq(wkr.totalSupply(), 1_000_000e18);
        assertEq(wkr.owner(), owner);
        assertEq(wkr.INITIAL_OWNER(), owner);
        assertEq(wkr.DAO_OWNER(), address(timelock));
        assertEq(wkr.maxTxAmount(), 10_005e18);
        assertEq(wkr.maxWalletAmount(), 10_005e18);
        assertTrue(wkr.limitsEnabled());
    }

    function testInitialOwnerCanMintBeforeDaoHandover() public {
        uint256 beforeSupply = wkr.totalSupply();
        uint256 beforeBob = wkr.balanceOf(bob);

        wkr.mint(bob, MINT_AMOUNT);

        assertEq(wkr.balanceOf(bob), beforeBob + MINT_AMOUNT);
        assertEq(wkr.totalSupply(), beforeSupply + MINT_AMOUNT);
    }

    function testRevert_DeployWKR_WhenOwnerIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new WKR(address(0), address(timelock));
    }

    function testRevert_DeployWKR_WhenDaoOwnerIsZero() public {
        vm.expectRevert("DAO owner zero address");
        new WKR(owner, address(0));
    }

    function testRevert_DeployWKR_WhenDaoOwnerMatchesInitialOwner() public {
        vm.expectRevert("DAO owner must differ from initial owner");
        new WKR(owner, owner);
    }

    function testRevert_Mint_WhenRecipientIsZero() public {
        vm.expectRevert("Mint to zero");
        wkr.mint(address(0), 1e18);
    }

    function testRevert_Mint_WhenAmountIsZero() public {
        vm.expectRevert("Mint zero");
        wkr.mint(bob, 0);
    }

    function testRevert_TransferOwnership_WhenNewOwnerIsNotDao() public {
        vm.expectRevert("Ownership can only move to DAO owner");
        wkr.transferOwnership(bob);
    }

    function testRevert_SetMaxTxAmount_WhenAmountIsZero() public {
        vm.expectRevert("Max tx zero");
        wkr.setMaxTxAmount(0);
    }

    function testRevert_SetMaxWalletAmount_WhenAmountIsZero() public {
        vm.expectRevert("Max wallet zero");
        wkr.setMaxWalletAmount(0);
    }

    function testRevert_SetPresaleExempt_WhenAccountIsZero() public {
        vm.expectRevert("Presale exempt zero");
        wkr.setPresaleExempt(address(0), true);
    }

    function testLimitsDisabledAllowTransferAboveInitialLimits() public {
        address recipient = address(0xCA02);
        uint256 amount = 20_000e18;
        wkr.setLimitsEnabled(false);

        wkr.transfer(recipient, amount);

        assertEq(wkr.balanceOf(recipient), amount);
    }

    function testNoncesStartsAtZero() public view {
        assertEq(wkr.nonces(alice), 0);
    }

    function testBurnReducesSupply() public {
        uint256 beforeSupply = wkr.totalSupply();
        uint256 burnAmount = 5_000e18;

        wkr.burn(burnAmount);

        assertEq(wkr.totalSupply(), beforeSupply - burnAmount);
    }

    function testDelegateActivatesVotes() public {
        vm.prank(alice);
        wkr.delegate(alice);

        assertEq(wkr.getVotes(alice), wkr.balanceOf(alice));
    }

    function testTransferAboveMaxTxRevertsForNonExemptAccounts() public {
        address carol = address(0xCA01);
        vm.prank(alice);
        vm.expectRevert(bytes("Transfer exceeds max tx"));
        wkr.transfer(carol, 10_006e18);
    }

    function testTransferThatExceedsRecipientMaxWalletReverts() public {
        address carol = address(0xCA01);
        vm.prank(alice);
        wkr.transfer(carol, 8_000e18);

        vm.prank(owner);
        vm.expectRevert(bytes("Recipient exceeds max wallet"));
        wkr.transfer(carol, 3_000e18);
    }

    function testInitialOwnerCanManageLimitsBeforeDaoHandover() public {
        vm.expectEmit(true, true, true, true, address(wkr));
        emit LimitsEnabledUpdated(true, false);
        wkr.setLimitsEnabled(false);

        vm.expectEmit(true, true, true, true, address(wkr));
        emit MaxTxAmountUpdated(10_005e18, 9_500e18);
        wkr.setMaxTxAmount(9_500e18);

        vm.expectEmit(true, true, true, true, address(wkr));
        emit MaxWalletAmountUpdated(10_005e18, 9_750e18);
        wkr.setMaxWalletAmount(9_750e18);
    }

    function testInitialOwnerCanSetPresaleExemptionBeforeDaoHandover() public {
        address presaleAddress = address(0xABCD);

        vm.expectEmit(true, true, true, true, address(wkr));
        emit PresaleExemptUpdated(presaleAddress, false, true);
        wkr.setPresaleExempt(presaleAddress, true);

        assertTrue(wkr.isPresaleExempt(presaleAddress));
    }

    function testPresaleExemptRecipientCanReceiveAboveLimits() public {
        address presaleAddress = address(0xABCD);
        uint256 presaleAllocation = 100_000e18;

        wkr.setPresaleExempt(presaleAddress, true);
        wkr.transfer(presaleAddress, presaleAllocation);

        assertEq(wkr.balanceOf(presaleAddress), presaleAllocation);
    }

    function testNonOwnerCannotSetPresaleExemption() public {
        vm.prank(alice);
        vm.expectRevert();
        wkr.setPresaleExempt(address(0xABCD), true);
    }

    function testDaoOwnerCanUpdateLimitsAndEmitEvents() public {
        wkr.transferOwnership(address(timelock));
        vm.prank(address(timelock));
        wkr.acceptOwnership();

        vm.prank(address(timelock));
        vm.expectEmit(true, true, true, true, address(wkr));
        emit LimitsEnabledUpdated(true, false);
        wkr.setLimitsEnabled(false);

        vm.prank(address(timelock));
        vm.expectEmit(true, true, true, true, address(wkr));
        emit MaxTxAmountUpdated(10_005e18, 9_500e18);
        wkr.setMaxTxAmount(9_500e18);

        vm.prank(address(timelock));
        vm.expectEmit(true, true, true, true, address(wkr));
        emit MaxWalletAmountUpdated(10_005e18, 9_750e18);
        wkr.setMaxWalletAmount(9_750e18);
    }

    function testTimelockAdminRoleIsNotHeldByEoaAfterBootstrap() public view {
        bytes32 adminRole = timelock.DEFAULT_ADMIN_ROLE();
        assertFalse(timelock.hasRole(adminRole, owner));
        assertTrue(timelock.hasRole(adminRole, address(timelock)));
    }

    function testExecutorRoleIsRestrictedToGovernor() public view {
        bytes32 executorRole = timelock.EXECUTOR_ROLE();
        assertFalse(timelock.hasRole(executorRole, address(0)));
        assertTrue(timelock.hasRole(executorRole, address(governor)));
        assertFalse(timelock.hasRole(executorRole, owner));
    }

    function testOnlyTimelockCanAcceptOwnershipDuringHandover() public {
        wkr.transferOwnership(address(timelock));

        vm.prank(alice);
        vm.expectRevert();
        wkr.acceptOwnership();
    }

    function testNonProposerCannotScheduleOperation() public {
        address target = address(wkr);
        uint256 value = 0;
        bytes memory data = abi.encodeCall(wkr.mint, (bob, 1e18));
        bytes32 predecessor = bytes32(0);
        bytes32 salt = keccak256("unauthorized-schedule");
        uint256 delay = timelock.getMinDelay();

        vm.prank(alice);
        vm.expectRevert();
        timelock.schedule(target, value, data, predecessor, salt, delay);
    }

    function testNonExecutorCannotExecuteReadyOperation() public {
        // Migrate ownership so mint can be a valid timelock operation target.
        wkr.transferOwnership(address(timelock));
        vm.prank(address(timelock));
        wkr.acceptOwnership();

        address target = address(wkr);
        uint256 value = 0;
        bytes memory data = abi.encodeCall(wkr.mint, (bob, 1e18));
        bytes32 predecessor = bytes32(0);
        bytes32 salt = keccak256("governor-only-execute");
        uint256 delay = timelock.getMinDelay();

        vm.prank(address(governor));
        timelock.schedule(target, value, data, predecessor, salt, delay);

        vm.warp(block.timestamp + delay + 1);

        vm.prank(alice);
        vm.expectRevert();
        timelock.execute(target, value, data, predecessor, salt);
    }

    function testCannotExecuteBeforeTimelockDelay() public {
        vm.prank(alice);
        wkr.delegate(alice);
        vm.roll(block.number + 1);

        uint256 newThreshold = 150_000e18;
        string memory description = "Delay enforcement";

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(governor);
        values[0] = 0;
        calldatas[0] = abi.encodeCall(governor.setProposalThreshold, (newThreshold));

        vm.prank(alice);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        vm.roll(block.number + governor.votingDelay() + 1);
        vm.prank(alice);
        governor.castVote(proposalId, 1);
        vm.roll(block.number + governor.votingPeriod() + 1);

        bytes32 descriptionHash = keccak256(bytes(description));
        governor.queue(targets, values, calldatas, descriptionHash);

        vm.expectRevert();
        governor.execute(targets, values, calldatas, descriptionHash);
    }

    function testDefeatedProposalCannotBeQueuedOrExecuted() public {
        vm.prank(alice);
        wkr.delegate(alice);
        vm.roll(block.number + 1);

        uint256 newThreshold = 150_000e18;
        string memory description = "Defeated proposal path";

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(governor);
        values[0] = 0;
        calldatas[0] = abi.encodeCall(governor.setProposalThreshold, (newThreshold));

        vm.prank(alice);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        vm.roll(block.number + governor.votingDelay() + 1);
        vm.prank(alice);
        governor.castVote(proposalId, 0); // Against
        vm.roll(block.number + governor.votingPeriod() + 1);

        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Defeated));

        bytes32 descriptionHash = keccak256(bytes(description));
        vm.expectRevert();
        governor.queue(targets, values, calldatas, descriptionHash);

        vm.expectRevert();
        governor.execute(targets, values, calldatas, descriptionHash);
    }

    function testGovernorProposalsRequireTimelockQueue() public view {
        assertTrue(governor.proposalNeedsQueuing(0));
    }

    function testProposerCanCancelPendingProposal() public {
        vm.prank(alice);
        wkr.delegate(alice);
        vm.roll(block.number + 1);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(governor);
        calldatas[0] = abi.encodeCall(governor.setProposalThreshold, (20_000e18));
        string memory description = "Cancel pending proposal";

        vm.prank(alice);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        vm.prank(alice);
        governor.cancel(targets, values, calldatas, keccak256(bytes(description)));

        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Canceled));
    }

    function testOperationCannotBeExecutedTwice() public {
        vm.prank(alice);
        wkr.delegate(alice);
        vm.roll(block.number + 1);

        uint256 newThreshold = 150_000e18;
        string memory description = "No replay execution";

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(governor);
        values[0] = 0;
        calldatas[0] = abi.encodeCall(governor.setProposalThreshold, (newThreshold));

        vm.prank(alice);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        vm.roll(block.number + governor.votingDelay() + 1);
        vm.prank(alice);
        governor.castVote(proposalId, 1);
        vm.roll(block.number + governor.votingPeriod() + 1);

        bytes32 descriptionHash = keccak256(bytes(description));
        governor.queue(targets, values, calldatas, descriptionHash);
        vm.warp(block.timestamp + timelock.getMinDelay() + 1);
        governor.execute(targets, values, calldatas, descriptionHash);

        vm.expectRevert();
        governor.execute(targets, values, calldatas, descriptionHash);
    }

    function testGovernorProposalLifecycleChangesThreshold() public {
        uint256 newThreshold = 150_000e18;
        string memory description = "Raise proposal threshold";

        vm.prank(alice);
        wkr.delegate(alice);
        vm.roll(block.number + 1);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(governor);
        values[0] = 0;
        calldatas[0] = abi.encodeCall(governor.setProposalThreshold, (newThreshold));

        vm.prank(alice);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        vm.roll(block.number + governor.votingDelay() + 1);

        vm.prank(alice);
        governor.castVote(proposalId, 1); // For

        vm.roll(block.number + governor.votingPeriod() + 1);

        bytes32 descriptionHash = keccak256(bytes(description));
        governor.queue(targets, values, calldatas, descriptionHash);

        vm.warp(block.timestamp + timelock.getMinDelay() + 1);
        governor.execute(targets, values, calldatas, descriptionHash);

        assertEq(governor.proposalThreshold(), newThreshold);
    }

    function testEndToEnd_DAOMintsAfterOwnershipMigratesToTimelock() public {
        // 1) Migrate WKR ownership to Timelock via 2-step ownable flow.
        wkr.transferOwnership(address(timelock));
        vm.prank(address(timelock));
        wkr.acceptOwnership();
        assertEq(wkr.owner(), address(timelock));

        // 2) Give Alice voting power and move one block for snapshot accounting.
        vm.prank(alice);
        wkr.delegate(alice);
        vm.roll(block.number + 1);

        // 3) Build proposal: Timelock (as owner) will call WKR.mint(bob, amount).
        uint256 mintAmount = 2_500e18;
        string memory description = "DAO mint to Bob";

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(wkr);
        values[0] = 0;
        calldatas[0] = abi.encodeCall(wkr.mint, (bob, mintAmount));

        vm.prank(alice);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        vm.roll(block.number + governor.votingDelay() + 1);

        vm.prank(alice);
        governor.castVote(proposalId, 1); // For

        vm.roll(block.number + governor.votingPeriod() + 1);

        bytes32 descriptionHash = keccak256(bytes(description));
        governor.queue(targets, values, calldatas, descriptionHash);

        vm.warp(block.timestamp + timelock.getMinDelay() + 1);

        uint256 bobBefore = wkr.balanceOf(bob);
        uint256 supplyBefore = wkr.totalSupply();

        governor.execute(targets, values, calldatas, descriptionHash);

        // 4) End-to-end assertions: mint executed through DAO + timelock.
        assertEq(wkr.balanceOf(bob), bobBefore + mintAmount);
        assertEq(wkr.totalSupply(), supplyBefore + mintAmount);

        // Final owner stays as Timelock once migrated.
        assertEq(wkr.owner(), address(timelock));
    }

    function testAttack_250kDelegatedCannotStealOwnerBeforeHandover() public {
        address attacker = address(0xBEEF);
        _fundAndDelegate(attacker, 25, WALLET_CAP, 7000); // 250k delegated votes
        vm.roll(block.number + 1);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(wkr);
        values[0] = 0;
        calldatas[0] = abi.encodeCall(wkr.transferOwnership, (attacker));
        string memory description = "Malicious owner takeover before handover";

        vm.prank(attacker);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        vm.roll(block.number + governor.votingDelay() + 1);
        vm.prank(attacker);
        governor.castVote(proposalId, 1);
        vm.roll(block.number + governor.votingPeriod() + 1);

        bytes32 descriptionHash = keccak256(bytes(description));
        governor.queue(targets, values, calldatas, descriptionHash);
        vm.warp(block.timestamp + timelock.getMinDelay() + 1);

        vm.expectRevert();
        governor.execute(targets, values, calldatas, descriptionHash);
        assertEq(wkr.owner(), owner);
    }

    function testAttack_250kDelegatedCannotSetNonDaoOwnerAfterHandover() public {
        address attacker = address(0xBEEF);
        _fundAndDelegate(attacker, 25, WALLET_CAP, 8000); // 250k delegated votes

        wkr.transferOwnership(address(timelock));
        vm.prank(address(timelock));
        wkr.acceptOwnership();
        assertEq(wkr.owner(), address(timelock));
        vm.roll(block.number + 1);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(wkr);
        values[0] = 0;
        calldatas[0] = abi.encodeCall(wkr.transferOwnership, (attacker));
        string memory description = "Malicious owner takeover after handover";

        vm.prank(attacker);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        vm.roll(block.number + governor.votingDelay() + 1);
        vm.prank(attacker);
        governor.castVote(proposalId, 1);
        vm.roll(block.number + governor.votingPeriod() + 1);

        bytes32 descriptionHash = keccak256(bytes(description));
        governor.queue(targets, values, calldatas, descriptionHash);
        vm.warp(block.timestamp + timelock.getMinDelay() + 1);

        vm.expectRevert();
        governor.execute(targets, values, calldatas, descriptionHash);
        assertEq(wkr.owner(), address(timelock));
    }

    function testAttack_250kDelegatedCannotMintBeforeHandover() public {
        address attacker = address(0xBEEF);
        address rogueReceiver = address(0xD00D);
        _fundAndDelegate(attacker, 25, WALLET_CAP, 9000); // 250k delegated votes
        vm.roll(block.number + 1);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(wkr);
        values[0] = 0;
        calldatas[0] = abi.encodeCall(wkr.mint, (rogueReceiver, 1_000e18));
        string memory description = "Malicious mint before handover";

        vm.prank(attacker);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        vm.roll(block.number + governor.votingDelay() + 1);
        vm.prank(attacker);
        governor.castVote(proposalId, 1);
        vm.roll(block.number + governor.votingPeriod() + 1);

        bytes32 descriptionHash = keccak256(bytes(description));
        governor.queue(targets, values, calldatas, descriptionHash);
        vm.warp(block.timestamp + timelock.getMinDelay() + 1);

        vm.expectRevert();
        governor.execute(targets, values, calldatas, descriptionHash);
        assertEq(wkr.balanceOf(rogueReceiver), 0);
    }

    function testAttack_AfterHandoverOldMultisigCannotMintDirectly() public {
        wkr.transferOwnership(address(timelock));
        vm.prank(address(timelock));
        wkr.acceptOwnership();

        vm.expectRevert();
        wkr.mint(bob, 1e18);
    }

    function testAttack_AfterHandoverGovernorCannotMintDirectly() public {
        wkr.transferOwnership(address(timelock));
        vm.prank(address(timelock));
        wkr.acceptOwnership();

        vm.prank(address(governor));
        vm.expectRevert();
        wkr.mint(bob, 1e18);
    }

    function testAttack_AfterHandoverCannotExecuteMintWithoutSchedule() public {
        wkr.transferOwnership(address(timelock));
        vm.prank(address(timelock));
        wkr.acceptOwnership();

        address target = address(wkr);
        uint256 value = 0;
        bytes memory data = abi.encodeCall(wkr.mint, (bob, 1e18));
        bytes32 predecessor = bytes32(0);
        bytes32 salt = keccak256("unscheduled-mint");

        vm.prank(address(governor));
        vm.expectRevert();
        timelock.execute(target, value, data, predecessor, salt);
    }

    function testVotingRule_ForBeatsAgainst_WithQuorumMet() public {
        address voterFor = address(0xF0);
        address voterAgainst = address(0xA6A1);
        address voterAbstain = address(0xAB57);

        // 15 + 10 + 5 = 30% turnout (quorum 25%), with For > Against.
        _fundAndDelegate(voterFor, 15, WALLET_CAP, 1000);
        _fundAndDelegate(voterAgainst, 10, WALLET_CAP, 2000);
        _fundAndDelegate(voterAbstain, 5, WALLET_CAP, 3000);
        vm.roll(block.number + 1);

        uint256 newThreshold = 20_000e18;
        string memory description = "For wins with quorum";
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(governor);
        values[0] = 0;
        calldatas[0] = abi.encodeCall(governor.setProposalThreshold, (newThreshold));

        vm.prank(voterFor);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        vm.roll(block.number + governor.votingDelay() + 1);
        vm.prank(voterFor);
        governor.castVote(proposalId, 1); // For
        vm.prank(voterAgainst);
        governor.castVote(proposalId, 0); // Against
        vm.prank(voterAbstain);
        governor.castVote(proposalId, 2); // Abstain
        vm.roll(block.number + governor.votingPeriod() + 1);

        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Succeeded));
    }

    function testVotingRule_AbstainHelpsQuorumButDoesNotBeatAgainst() public {
        address voterFor = address(0xF1);
        address voterAgainst = address(0xA6A2);
        address voterAbstain = address(0xAB58);

        // 10 + 15 + 5 = 30% turnout (quorum met), but For < Against => Defeated.
        _fundAndDelegate(voterFor, 10, WALLET_CAP, 4000);
        _fundAndDelegate(voterAgainst, 15, WALLET_CAP, 5000);
        _fundAndDelegate(voterAbstain, 5, WALLET_CAP, 6000);
        vm.roll(block.number + 1);

        uint256 newThreshold = 20_000e18;
        string memory description = "Against beats For even with abstain";
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(governor);
        values[0] = 0;
        calldatas[0] = abi.encodeCall(governor.setProposalThreshold, (newThreshold));

        vm.prank(voterFor);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        vm.roll(block.number + governor.votingDelay() + 1);
        vm.prank(voterFor);
        governor.castVote(proposalId, 1); // For
        vm.prank(voterAgainst);
        governor.castVote(proposalId, 0); // Against
        vm.prank(voterAbstain);
        governor.castVote(proposalId, 2); // Abstain
        vm.roll(block.number + governor.votingPeriod() + 1);

        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Defeated));
    }

    function _fundAndDelegate(address delegatee, uint256 wallets, uint256 amountPerWallet, uint256 seedStart) internal {
        for (uint256 i = 0; i < wallets; i++) {
            address holder = vm.addr(seedStart + i);
            wkr.transfer(holder, amountPerWallet);
            vm.prank(holder);
            wkr.delegate(delegatee);
        }
        assertEq(wkr.getVotes(delegatee), wallets * amountPerWallet);
    }
}
