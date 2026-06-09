//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/presale.sol";
import "../src/WKR.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockAggregator.sol";

contract RejectEtherReceiver {
    receive() external payable {
        revert("no eth");
    }
}

contract ReentrantEtherReceiver {
    Presale public presale;
    bool public attemptedReentry;

    function setPresale(Presale presale_) external {
        presale = presale_;
    }

    receive() external payable {
        if (!attemptedReentry) {
            attemptedReentry = true;
            try presale.buyWithEth{value: presale.MIN_ETH_PURCHASE()}() {} catch {}
        }
    }
}

contract StaleRoundAggregator {
    uint8 public constant decimals = 8;

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (2, 3_000e8, 0, block.timestamp, 1);
    }
}

contract UnsupportedDecimalsAggregator {
    uint8 public constant decimals = 19;

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (1, 3_000e19, 0, block.timestamp, 1);
    }
}

contract IncompleteRoundAggregator {
    uint8 public constant decimals = 8;

    function latestRoundData() external pure returns (uint80, int256, uint256, uint256, uint80) {
        return (1, 3_000e8, 0, 0, 1);
    }
}

contract PresaleTest is Test {
    Presale public presale;
    MockERC20 public saleToken;
    MockERC20 public usdt;
    MockERC20 public usdc;
    MockAggregator public feed;

    address public owner = address(this);
    address public buyer = address(0xBEEF);
    address public buyerTwo = address(0xBEE2);
    address public buyerThree = address(0xBEE3);
    address public buyerFour = address(0xBEE4);
    address public treasury = address(0xCAFE);
    address public attacker = address(0xBAD);

    uint256 public constant TOTAL_SUPPLY = 1_000_000e18;
    uint256 public constant PRESALE_SUPPLY = 100_000e18;

    // USD6 prices
    uint256 public constant P1 = 60_000; // 0.06
    uint256 public constant P2 = 75_000; // 0.075
    uint256 public constant P3 = 90_000; // 0.09

    receive() external payable {}

    function setUp() public {
        saleToken = new MockERC20("WKR", "WKR", 18);
        usdt = new MockERC20("Tether USD", "USDT", 6);
        usdc = new MockERC20("USD Coin", "USDC", 6);
        feed = new MockAggregator(3_000e8); // 3000 USD with 8 decimals

        saleToken.mint(owner, TOTAL_SUPPLY);
        usdt.mint(buyer, 1_000_000e6);
        usdc.mint(buyer, 1_000_000e6);
        usdt.mint(buyerTwo, 1_000_000e6);
        usdt.mint(buyerThree, 1_000_000e6);
        usdt.mint(buyerFour, 1_000_000e6);

        uint256 start = block.timestamp + 1;
        uint256 t1 = start + 30 days;
        uint256 t2 = t1 + 30 days;
        uint256 t3 = t2 + 30 days;

        uint256[][3] memory phases;
        phases[0] = new uint256[](3);
        phases[1] = new uint256[](3);
        phases[2] = new uint256[](3);

        // cap is overwritten in constructor to 33.33/33.33/33.34 distribution
        phases[0][0] = 0;
        phases[1][0] = 0;
        phases[2][0] = 0;

        phases[0][1] = P1;
        phases[1][1] = P2;
        phases[2][1] = P3;

        phases[0][2] = t1;
        phases[1][2] = t2;
        phases[2][2] = t3;

        uint256 deployerNonce = vm.getNonce(address(this));
        address predictedPresale = vm.computeCreateAddress(address(this), deployerNonce);
        saleToken.approve(predictedPresale, PRESALE_SUPPLY);
        presale = new Presale(
            address(saleToken), address(usdt), address(usdc), treasury, address(feed), PRESALE_SUPPLY, start, t3, phases
        );

        vm.prank(buyer);
        usdt.approve(address(presale), type(uint256).max);

        vm.prank(buyer);
        usdc.approve(address(presale), type(uint256).max);

        vm.prank(buyerTwo);
        usdt.approve(address(presale), type(uint256).max);

        vm.prank(buyerThree);
        usdt.approve(address(presale), type(uint256).max);

        vm.prank(buyerFour);
        usdt.approve(address(presale), type(uint256).max);
    }

    function testPhase1PriceWithUSDT() public {
        vm.warp(presale.startingTime() + 1);

        uint256 payAmount = 600e6; // 600 USDT
        vm.prank(buyer);
        presale.buyWithStable(address(usdt), payAmount);

        uint256 expected = 10_000e18; // 600 / 0.06 = 10,000 WKR
        assertEq(presale.userTokenBalance(buyer), expected);
        assertEq(presale.currentPhase(), 0);
    }

    function testPhaseCapsAreCumulativeAndTotalIs100000Wkr() public view {
        uint256 phaseAmount = PRESALE_SUPPLY / 3;

        assertEq(presale.phases(0, 0), phaseAmount);
        assertEq(presale.phases(1, 0), phaseAmount * 2);
        assertEq(presale.phases(2, 0), PRESALE_SUPPLY);
        assertEq(presale.maxSellingAmount(), PRESALE_SUPPLY);
    }

    function testPhasePricesAreConfiguredCorrectly() public view {
        assertEq(presale.phases(0, 1), P1);
        assertEq(presale.phases(1, 1), P2);
        assertEq(presale.phases(2, 1), P3);
    }

    function testPresaleScheduleIsThreeThirtyDayPhases() public view {
        uint256 start = presale.startingTime();

        assertEq(presale.phases(0, 2), start + 30 days);
        assertEq(presale.phases(1, 2), start + 60 days);
        assertEq(presale.phases(2, 2), start + 90 days);
        assertEq(presale.endingTime(), start + 90 days);
    }

    function testRevert_Deploy_WhenPhase3EndDoesNotMatchPresaleEnd() public {
        uint256 start = block.timestamp + 1;
        uint256[][3] memory phases = _buildPhases(start);

        vm.expectRevert("Phase 3 end mismatch");
        new Presale(
            address(saleToken),
            address(usdt),
            address(usdc),
            treasury,
            address(feed),
            PRESALE_SUPPLY,
            start,
            start + 90 days + 1,
            phases
        );
    }

    function testRevert_Deploy_WhenEndIsNotAfterStart() public {
        uint256 start = block.timestamp + 1;
        uint256[][3] memory phases = _buildPhases(start);

        vm.expectRevert("Ending time must be greater than starting time");
        new Presale(
            address(saleToken),
            address(usdt),
            address(usdc),
            treasury,
            address(feed),
            PRESALE_SUPPLY,
            start,
            start,
            phases
        );
    }

    function testRevert_Deploy_WhenPhaseArrayIsTooShort() public {
        uint256 start = block.timestamp + 1;
        uint256[][3] memory phases = _buildPhases(start);
        phases[1] = new uint256[](2);

        vm.expectRevert("Invalid phases");
        new Presale(
            address(saleToken),
            address(usdt),
            address(usdc),
            treasury,
            address(feed),
            PRESALE_SUPPLY,
            start,
            start + 90 days,
            phases
        );
    }

    function testRevert_Deploy_WhenPhasePriceIsZero() public {
        uint256 start = block.timestamp + 1;
        uint256[][3] memory phases = _buildPhases(start);
        phases[1][1] = 0;

        vm.expectRevert("Invalid phase price");
        new Presale(
            address(saleToken),
            address(usdt),
            address(usdc),
            treasury,
            address(feed),
            PRESALE_SUPPLY,
            start,
            start + 90 days,
            phases
        );
    }

    function testRevert_Deploy_WhenPhaseEndsAreNotIncreasing() public {
        uint256 start = block.timestamp + 1;
        uint256[][3] memory phases = _buildPhases(start);
        phases[1][2] = phases[0][2];

        vm.expectRevert("Invalid phase 2 end");
        new Presale(
            address(saleToken),
            address(usdt),
            address(usdc),
            treasury,
            address(feed),
            PRESALE_SUPPLY,
            start,
            start + 90 days,
            phases
        );
    }

    function testRevert_Deploy_WhenDataFeedIsZero() public {
        uint256 start = block.timestamp + 1;
        uint256[][3] memory phases = _buildPhases(start);

        vm.expectRevert("Data feed zero");
        new Presale(
            address(saleToken),
            address(usdt),
            address(usdc),
            treasury,
            address(0),
            PRESALE_SUPPLY,
            start,
            start + 90 days,
            phases
        );
    }

    function testMoveToPhase2ByTime() public {
        vm.warp(presale.startingTime() + 30 days + 1);

        uint256 payAmount = 750e6; // 750 USDT
        vm.prank(buyer);
        presale.buyWithStable(address(usdt), payAmount);

        uint256 expected = 10_000e18; // 750 / 0.075 = 10,000 WKR
        assertEq(presale.userTokenBalance(buyer), expected);
        assertEq(presale.currentPhase(), 1);
    }

    function testPhase3PriceWithUSDT() public {
        vm.warp(presale.startingTime() + 60 days + 1);

        uint256 payAmount = 900e6; // 900 / 0.09 = 10,000
        vm.prank(buyer);
        presale.buyWithStable(address(usdt), payAmount);

        assertEq(presale.userTokenBalance(buyer), 10_000e18);
        assertEq(presale.currentPhase(), 2);
    }

    function testMoveToPhase2ByCap() public {
        vm.warp(presale.startingTime() + 1);

        vm.prank(buyer);
        presale.buyWithStable(address(usdt), 600e6);

        vm.prank(buyerTwo);
        presale.buyWithStable(address(usdt), 600e6);

        vm.prank(buyerThree);
        presale.buyWithStable(address(usdt), 600e6);

        vm.prank(buyerFour);
        presale.buyWithStable(address(usdt), 300e6);

        assertEq(presale.userTokenBalance(buyerFour), 4_000e18);
        assertEq(presale.currentPhase(), 1);
    }

    function testRevert_BuyWithStable_WhenExceedsMaxPresalePerWallet() public {
        vm.warp(presale.startingTime() + 1);

        vm.prank(buyer);
        vm.expectRevert("Exceeds max presale per wallet");
        presale.buyWithStable(address(usdt), 601e6);
    }

    function testRevert_BuyWithStable_WhenCumulativeExceedsMaxPresalePerWallet() public {
        vm.warp(presale.startingTime() + 1);

        vm.prank(buyer);
        presale.buyWithStable(address(usdt), 300e6);

        vm.prank(buyer);
        vm.expectRevert("Exceeds max presale per wallet");
        presale.buyWithStable(address(usdt), 301e6);
    }

    function testSoldOutPresaleRejectsFurtherStableAndEthPurchasesWithoutMovingFunds() public {
        vm.warp(presale.startingTime() + 1);
        for (uint256 i = 0; i < 3; i++) {
            _buyTenThousandWkr(address(uint160(0x1000 + i)), 600e6);
        }

        vm.warp(presale.startingTime() + 30 days + 1);
        for (uint256 i = 0; i < 3; i++) {
            _buyTenThousandWkr(address(uint160(0x2000 + i)), 750e6);
        }

        vm.warp(presale.startingTime() + 60 days + 1);
        for (uint256 i = 0; i < 4; i++) {
            _buyTenThousandWkr(address(uint160(0x3000 + i)), 900e6);
        }

        assertEq(presale.totalSold(), PRESALE_SUPPLY);
        assertEq(saleToken.balanceOf(address(presale)), PRESALE_SUPPLY);
        assertEq(presale.currentPhase(), 2);

        address extraBuyer = address(0x4000);
        _fundAndApproveUsdt(extraBuyer);
        vm.deal(extraBuyer, 1 ether);

        uint256 buyerUsdtBefore = usdt.balanceOf(extraBuyer);
        uint256 buyerEthBefore = extraBuyer.balance;
        uint256 treasuryUsdtBefore = usdt.balanceOf(treasury);
        uint256 treasuryEthBefore = treasury.balance;
        uint256 minimumEthPurchase = presale.MIN_ETH_PURCHASE();

        vm.prank(extraBuyer);
        vm.expectRevert("No active phase");
        presale.buyWithStable(address(usdt), 1e6);

        feed.setAnswer(3_000e8);
        vm.prank(extraBuyer);
        vm.expectRevert("No active phase");
        presale.buyWithEth{value: minimumEthPurchase}();

        assertEq(presale.totalSold(), PRESALE_SUPPLY);
        assertEq(presale.userTokenBalance(extraBuyer), 0);
        assertEq(saleToken.balanceOf(address(presale)), PRESALE_SUPPLY);
        assertEq(usdt.balanceOf(extraBuyer), buyerUsdtBefore);
        assertEq(extraBuyer.balance, buyerEthBefore);
        assertEq(usdt.balanceOf(treasury), treasuryUsdtBefore);
        assertEq(treasury.balance, treasuryEthBefore);
    }

    function testBuyWithStable_AllowsExactOneDollarMinimum() public {
        vm.warp(presale.startingTime() + 1);

        vm.prank(buyer);
        presale.buyWithStable(address(usdt), 1e6);

        assertGt(presale.userTokenBalance(buyer), 0);
    }

    function testBuyWithUSDC_AllowsExactOneDollarMinimum() public {
        vm.warp(presale.startingTime() + 1);

        vm.prank(buyer);
        presale.buyWithStable(address(usdc), 1e6);

        assertGt(presale.userTokenBalance(buyer), 0);
    }

    function testRevert_BuyWithStable_WhenUSDTIsBelowOneDollar() public {
        vm.warp(presale.startingTime() + 1);

        vm.prank(buyer);
        vm.expectRevert("Stable amount below minimum");
        presale.buyWithStable(address(usdt), 1e6 - 1);
    }

    function testRevert_BuyWithStable_WhenUSDCIsBelowOneDollar() public {
        vm.warp(presale.startingTime() + 1);

        vm.prank(buyer);
        vm.expectRevert("Stable amount below minimum");
        presale.buyWithStable(address(usdc), 1e6 - 1);
    }

    function testPauseBlocksStableBuy() public {
        vm.warp(presale.startingTime() + 1);
        presale.pause();

        vm.prank(buyer);
        vm.expectRevert();
        presale.buyWithStable(address(usdt), 100e6);
    }

    function testUnpauseEnablesStableBuyAgain() public {
        vm.warp(presale.startingTime() + 1);
        presale.pause();
        presale.unpause();

        vm.prank(buyer);
        presale.buyWithStable(address(usdt), 60e6); // 60 / 0.06 = 1000

        assertEq(presale.userTokenBalance(buyer), 1_000e18);
    }

    function testGetEtherPriceRevertsWhenPriceIsStale() public {
        vm.warp(presale.startingTime() + 3 days);

        // Force stale oracle update timestamp (> MAX_PRICE_AGE = 1 hour).
        feed.setStale(block.timestamp - 2 hours);

        vm.expectRevert("Price too old");
        presale.getEtherPrice();
    }

    function testRevert_BuyWithStable_WhenBlacklisted() public {
        vm.warp(presale.startingTime() + 1);
        presale.blackList(buyer);

        vm.prank(buyer);
        vm.expectRevert("You are blacklisted");
        presale.buyWithStable(address(usdt), 100e6);
    }

    function testRevert_BuyWithStable_WithInvalidToken() public {
        vm.warp(presale.startingTime() + 1);

        MockERC20 dai = new MockERC20("Dai Stablecoin", "DAI", 18);
        dai.mint(buyer, 10_000e18);
        vm.prank(buyer);
        dai.approve(address(presale), type(uint256).max);

        vm.prank(buyer);
        vm.expectRevert("Invalid token address");
        presale.buyWithStable(address(dai), 100e18);
    }

    function testRevert_BuyWithStable_WhenTokenDecimalsAreUnsupported() public {
        MockERC20 unsupportedStable = new MockERC20("Unsupported", "BAD", 19);
        unsupportedStable.mint(buyer, 100e19);
        vm.prank(buyer);
        unsupportedStable.approve(address(presale), type(uint256).max);
        vm.store(address(presale), bytes32(uint256(2)), bytes32(uint256(uint160(address(unsupportedStable)))));

        vm.warp(presale.startingTime() + 1);
        vm.prank(buyer);
        vm.expectRevert("Unsupported token decimals");
        presale.buyWithStable(address(unsupportedStable), 1e19);
    }

    function testRevert_BuyWithStable_BeforeStart() public {
        vm.warp(presale.startingTime() - 1);

        vm.prank(buyer);
        vm.expectRevert("Presale has not started yet");
        presale.buyWithStable(address(usdt), 100e6);
    }

    function testRevert_BuyWithStable_AfterEnd() public {
        vm.warp(presale.endingTime() + 1);

        vm.prank(buyer);
        vm.expectRevert("Presale has ended");
        presale.buyWithStable(address(usdt), 100e6);
    }

    function testClaim_AfterEnd_TransfersTokens() public {
        vm.warp(presale.startingTime() + 1);

        vm.prank(buyer);
        presale.buyWithStable(address(usdt), 600e6); // 10,000 WKR

        vm.warp(presale.endingTime() + 1);

        uint256 before = saleToken.balanceOf(buyer);
        vm.prank(buyer);
        presale.claim();
        uint256 afterBal = saleToken.balanceOf(buyer);

        assertEq(afterBal - before, 10_000e18);
        assertEq(presale.userTokenBalance(buyer), 0);
    }

    function testRevert_Claim_BeforeEnd() public {
        vm.warp(presale.startingTime() + 1);
        vm.prank(buyer);
        presale.buyWithStable(address(usdt), 60e6);

        vm.warp(presale.endingTime());
        vm.prank(buyer);
        vm.expectRevert("Presale has not ended yet");
        presale.claim();
    }

    function testRemoveBlackList_AllowsBuyAgain() public {
        vm.warp(presale.startingTime() + 1);
        presale.blackList(buyer);
        presale.removeBlackList(buyer);

        vm.prank(buyer);
        presale.buyWithStable(address(usdt), 60e6);

        assertEq(presale.userTokenBalance(buyer), 1_000e18);
    }

    function testBuyWithEth_AccruesUserBalanceAndMovesFunds() public {
        vm.warp(presale.startingTime() + 1);
        vm.deal(buyer, 2 ether);
        uint256 treasuryBefore = treasury.balance;

        vm.prank(buyer);
        presale.buyWithEth{value: 0.1 ether}();

        assertGt(presale.userTokenBalance(buyer), 0);
        assertEq(treasury.balance - treasuryBefore, 0.1 ether);
    }

    function testBuyWithEth_AllowsExactMinimum() public {
        vm.warp(presale.startingTime() + 1);
        vm.deal(buyer, 1 ether);
        uint256 minimum = presale.MIN_ETH_PURCHASE();

        vm.prank(buyer);
        presale.buyWithEth{value: minimum}();

        assertGt(presale.userTokenBalance(buyer), 0);
    }

    function testRevert_BuyWithEth_WhenBelowMinimum() public {
        vm.warp(presale.startingTime() + 1);
        vm.deal(buyer, 1 ether);
        uint256 belowMinimum = presale.MIN_ETH_PURCHASE() - 1;

        vm.prank(buyer);
        vm.expectRevert("ETH amount below minimum");
        presale.buyWithEth{value: belowMinimum}();
    }

    function testRevert_BuyWithEth_WhenExceedsMaxPresalePerWallet() public {
        vm.warp(presale.startingTime() + 1);
        vm.deal(buyer, 2 ether);

        vm.prank(buyer);
        vm.expectRevert("Exceeds max presale per wallet");
        presale.buyWithEth{value: 1 ether}();
    }

    function testRevert_BuyWithEth_WhenCumulativePurchasesExceedMaxPresalePerWallet() public {
        vm.warp(presale.startingTime() + 1);
        vm.deal(buyer, 1 ether);

        // At 3,000 USD/ETH and 0.06 USD/WKR, 0.1 ETH reserves 5,000 WKR.
        vm.prank(buyer);
        presale.buyWithEth{value: 0.1 ether}();

        vm.prank(buyer);
        presale.buyWithEth{value: 0.1 ether}();
        assertEq(presale.userTokenBalance(buyer), 10_000e18);

        uint256 minimum = presale.MIN_ETH_PURCHASE();
        vm.prank(buyer);
        vm.expectRevert("Exceeds max presale per wallet");
        presale.buyWithEth{value: minimum}();

        assertEq(presale.userTokenBalance(buyer), 10_000e18);
    }

    function testRevert_BuyWithEth_BeforeStart() public {
        vm.warp(presale.startingTime() - 1);
        vm.deal(buyer, 1 ether);

        vm.prank(buyer);
        vm.expectRevert("Presale has not started yet");
        presale.buyWithEth{value: 0.1 ether}();
    }

    function testRevert_BuyWithEth_AfterEnd() public {
        vm.warp(presale.endingTime() + 1);
        vm.deal(buyer, 1 ether);

        vm.prank(buyer);
        vm.expectRevert("Presale has ended");
        presale.buyWithEth{value: 0.1 ether}();
    }

    function testRevert_BuyWithEth_WhenBlacklisted() public {
        vm.warp(presale.startingTime() + 1);
        vm.deal(buyer, 1 ether);
        presale.blackList(buyer);

        vm.prank(buyer);
        vm.expectRevert("You are blacklisted");
        presale.buyWithEth{value: 0.1 ether}();
    }

    function testRevert_BuyWithEth_WhenReceiverRejectsEth() public {
        RejectEtherReceiver rejector = new RejectEtherReceiver();

        uint256 start = block.timestamp + 1;
        uint256 t1 = start + 30 days;
        uint256 t2 = t1 + 30 days;
        uint256 t3 = t2 + 30 days;

        uint256[][3] memory phases;
        phases[0] = new uint256[](3);
        phases[1] = new uint256[](3);
        phases[2] = new uint256[](3);
        phases[0][1] = P1;
        phases[1][1] = P2;
        phases[2][1] = P3;
        phases[0][2] = t1;
        phases[1][2] = t2;
        phases[2][2] = t3;

        uint256 deployerNonce = vm.getNonce(address(this));
        address predictedPresale = vm.computeCreateAddress(address(this), deployerNonce);
        saleToken.approve(predictedPresale, PRESALE_SUPPLY);
        Presale localPresale = new Presale(
            address(saleToken),
            address(usdt),
            address(usdc),
            address(rejector),
            address(feed),
            PRESALE_SUPPLY,
            start,
            t3,
            phases
        );

        vm.warp(start + 1);
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        vm.expectRevert("Transfer failed.");
        localPresale.buyWithEth{value: 0.1 ether}();
    }

    function testBuyWithEth_BlocksReceiverReentry() public {
        ReentrantEtherReceiver receiver = new ReentrantEtherReceiver();

        uint256 start = block.timestamp + 1;
        uint256 t1 = start + 30 days;
        uint256 t2 = t1 + 30 days;
        uint256 t3 = t2 + 30 days;

        uint256[][3] memory phases;
        phases[0] = new uint256[](3);
        phases[1] = new uint256[](3);
        phases[2] = new uint256[](3);
        phases[0][1] = P1;
        phases[1][1] = P2;
        phases[2][1] = P3;
        phases[0][2] = t1;
        phases[1][2] = t2;
        phases[2][2] = t3;

        uint256 deployerNonce = vm.getNonce(address(this));
        address predictedPresale = vm.computeCreateAddress(address(this), deployerNonce);
        saleToken.approve(predictedPresale, PRESALE_SUPPLY);
        Presale localPresale = new Presale(
            address(saleToken),
            address(usdt),
            address(usdc),
            address(receiver),
            address(feed),
            PRESALE_SUPPLY,
            start,
            t3,
            phases
        );
        receiver.setPresale(localPresale);

        vm.warp(start + 1);
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        localPresale.buyWithEth{value: 0.1 ether}();

        assertTrue(receiver.attemptedReentry());
        assertGt(localPresale.userTokenBalance(buyer), 0);
        assertEq(localPresale.userTokenBalance(address(receiver)), 0);
        assertEq(address(receiver).balance, 0.1 ether);
    }

    function testUpdateDataFeed_AllowsOwnerAndUsesNewPrice() public {
        MockAggregator newFeed = new MockAggregator(2_500e8);

        presale.updateDataFeed(address(newFeed));

        assertEq(presale.datafeedaddress(), address(newFeed));
        assertEq(presale.getEtherPrice(), 2_500e18);
    }

    function testRevert_UpdateDataFeed_WhenCallerIsNotOwner() public {
        MockAggregator newFeed = new MockAggregator(2_500e8);

        vm.prank(attacker);
        vm.expectRevert();
        presale.updateDataFeed(address(newFeed));
    }

    function testRevert_UpdateDataFeed_WhenFeedIsInvalid() public {
        MockAggregator invalidFeed = new MockAggregator(0);

        vm.expectRevert("Invalid ETH price");
        presale.updateDataFeed(address(invalidFeed));
    }

    function testRevert_UpdateDataFeed_WhenDecimalsAreUnsupported() public {
        UnsupportedDecimalsAggregator invalidFeed = new UnsupportedDecimalsAggregator();

        vm.expectRevert("Unsupported feed decimals");
        presale.updateDataFeed(address(invalidFeed));
    }

    function testRevert_GetEtherPrice_WhenInvalidPrice() public {
        vm.warp(presale.startingTime() + 1);
        feed.setAnswer(0);

        vm.expectRevert("Invalid ETH price");
        presale.getEtherPrice();
    }

    function testRevert_GetEtherPrice_WhenStaleRound() public {
        StaleRoundAggregator staleFeed = new StaleRoundAggregator();

        uint256 start = block.timestamp + 1;
        uint256 t1 = start + 30 days;
        uint256 t2 = t1 + 30 days;
        uint256 t3 = t2 + 30 days;

        uint256[][3] memory phases;
        phases[0] = new uint256[](3);
        phases[1] = new uint256[](3);
        phases[2] = new uint256[](3);
        phases[0][1] = P1;
        phases[1][1] = P2;
        phases[2][1] = P3;
        phases[0][2] = t1;
        phases[1][2] = t2;
        phases[2][2] = t3;

        uint256 deployerNonce = vm.getNonce(address(this));
        address predictedPresale = vm.computeCreateAddress(address(this), deployerNonce);
        saleToken.approve(predictedPresale, PRESALE_SUPPLY);
        vm.expectRevert("Stale round");
        new Presale(
            address(saleToken),
            address(usdt),
            address(usdc),
            treasury,
            address(staleFeed),
            PRESALE_SUPPLY,
            start,
            t3,
            phases
        );
    }

    function testRevert_GetEtherPrice_WhenRoundIsIncomplete() public {
        IncompleteRoundAggregator incompleteFeed = new IncompleteRoundAggregator();

        vm.expectRevert("Round not complete");
        presale.updateDataFeed(address(incompleteFeed));
    }

    function testRevert_UpdateDataFeed_WhenAddressIsZero() public {
        vm.expectRevert("Data feed zero");
        presale.updateDataFeed(address(0));
    }

    function testEmergencyERC20Withdraw_WorksForOwner() public {
        uint256 amount = 123e6;
        usdt.mint(address(presale), amount);
        uint256 before = usdt.balanceOf(owner);

        presale.emergencyERC20Withdraw(address(usdt), amount);

        assertEq(usdt.balanceOf(owner) - before, amount);
    }

    function testRevert_EmergencyERC20Withdraw_CannotWithdrawReservedSaleTokens() public {
        vm.warp(presale.startingTime() + 1);

        vm.prank(buyer);
        presale.buyWithStable(address(usdt), 600e6); // 10,000 WKR reserved for buyer

        vm.expectRevert("Reserved sale tokens");
        presale.emergencyERC20Withdraw(address(saleToken), PRESALE_SUPPLY - 10_000e18 + 1);
    }

    function testEmergencyERC20Withdraw_AllowsOnlyUnreservedSaleTokens() public {
        vm.warp(presale.startingTime() + 1);

        vm.prank(buyer);
        presale.buyWithStable(address(usdt), 600e6); // 10,000 WKR reserved for buyer

        uint256 ownerBefore = saleToken.balanceOf(owner);
        uint256 withdrawable = PRESALE_SUPPLY - 10_000e18;

        presale.emergencyERC20Withdraw(address(saleToken), withdrawable);

        assertEq(saleToken.balanceOf(owner) - ownerBefore, withdrawable);
        assertEq(saleToken.balanceOf(address(presale)), 10_000e18);
    }

    function testRevert_WKRPresaleDeploy_WhenLimitsAreEnabled() public {
        WKR wkr = new WKR(owner, address(0xDAD));

        uint256 start = block.timestamp + 1;
        uint256 t1 = start + 30 days;
        uint256 t2 = t1 + 30 days;
        uint256 t3 = t2 + 30 days;

        uint256[][3] memory phases;
        phases[0] = new uint256[](3);
        phases[1] = new uint256[](3);
        phases[2] = new uint256[](3);
        phases[0][1] = P1;
        phases[1][1] = P2;
        phases[2][1] = P3;
        phases[0][2] = t1;
        phases[1][2] = t2;
        phases[2][2] = t3;

        uint256 deployerNonce = vm.getNonce(address(this));
        address predictedPresale = vm.computeCreateAddress(address(this), deployerNonce);
        wkr.approve(predictedPresale, PRESALE_SUPPLY);

        vm.expectRevert("Transfer exceeds max tx");
        new Presale(
            address(wkr), address(usdt), address(usdc), treasury, address(feed), PRESALE_SUPPLY, start, t3, phases
        );
    }

    function testWKRPresaleDeployBuyAndClaim_WhenPresaleIsExempt() public {
        WKR wkr = new WKR(owner, address(0xDAD));

        uint256 start = block.timestamp + 1;
        uint256 t1 = start + 30 days;
        uint256 t2 = t1 + 30 days;
        uint256 t3 = t2 + 30 days;

        uint256[][3] memory phases;
        phases[0] = new uint256[](3);
        phases[1] = new uint256[](3);
        phases[2] = new uint256[](3);
        phases[0][1] = P1;
        phases[1][1] = P2;
        phases[2][1] = P3;
        phases[0][2] = t1;
        phases[1][2] = t2;
        phases[2][2] = t3;

        uint256 deployerNonce = vm.getNonce(address(this));
        address predictedPresale = vm.computeCreateAddress(address(this), deployerNonce);
        wkr.setPresaleExempt(predictedPresale, true);
        wkr.approve(predictedPresale, PRESALE_SUPPLY);

        Presale wkrPresale = new Presale(
            address(wkr), address(usdt), address(usdc), treasury, address(feed), PRESALE_SUPPLY, start, t3, phases
        );

        vm.prank(buyer);
        usdt.approve(address(wkrPresale), type(uint256).max);

        vm.warp(start + 1);
        vm.prank(buyer);
        wkrPresale.buyWithStable(address(usdt), 600e6); // 10,000 WKR

        vm.warp(t3 + 1);
        vm.prank(buyer);
        wkrPresale.claim();

        assertEq(wkr.balanceOf(buyer), 10_000e18);
        assertEq(wkrPresale.totalSold(), 10_000e18);
        assertEq(wkrPresale.totalClaimed(), 10_000e18);
    }

    function testRevert_WKRClaim_WhenPreviousClaimerPushesBuyerAboveWalletLimit() public {
        WKR wkr = new WKR(owner, address(0xDAD));

        uint256 start = block.timestamp + 1;
        uint256 t1 = start + 30 days;
        uint256 t2 = t1 + 30 days;
        uint256 t3 = t2 + 30 days;

        uint256[][3] memory phases;
        phases[0] = new uint256[](3);
        phases[1] = new uint256[](3);
        phases[2] = new uint256[](3);
        phases[0][1] = P1;
        phases[1][1] = P2;
        phases[2][1] = P3;
        phases[0][2] = t1;
        phases[1][2] = t2;
        phases[2][2] = t3;

        uint256 deployerNonce = vm.getNonce(address(this));
        address predictedPresale = vm.computeCreateAddress(address(this), deployerNonce);
        wkr.setPresaleExempt(predictedPresale, true);
        wkr.approve(predictedPresale, PRESALE_SUPPLY);

        Presale wkrPresale = new Presale(
            address(wkr), address(usdt), address(usdc), treasury, address(feed), PRESALE_SUPPLY, start, t3, phases
        );

        vm.prank(buyer);
        usdt.approve(address(wkrPresale), type(uint256).max);
        vm.prank(buyerTwo);
        usdt.approve(address(wkrPresale), type(uint256).max);

        vm.warp(start + 1);
        vm.prank(buyer);
        wkrPresale.buyWithStable(address(usdt), 600e6);
        vm.prank(buyerTwo);
        wkrPresale.buyWithStable(address(usdt), 600e6);

        vm.warp(t3 + 1);
        vm.prank(buyer);
        wkrPresale.claim();

        vm.prank(buyer);
        wkr.transfer(buyerTwo, 6e18);

        vm.prank(buyerTwo);
        vm.expectRevert("Recipient exceeds max wallet");
        wkrPresale.claim();
    }

    function testWKRPresaleExemption_DoesNotDisableUserLimits() public {
        WKR wkr = new WKR(owner, address(0xDAD));
        address presaleAddress = address(0xABCD);
        address regularUser = address(0x1234);

        wkr.setPresaleExempt(presaleAddress, true);

        wkr.transfer(presaleAddress, PRESALE_SUPPLY);
        assertEq(wkr.balanceOf(presaleAddress), PRESALE_SUPPLY);

        vm.expectRevert("Transfer exceeds max tx");
        wkr.transfer(regularUser, PRESALE_SUPPLY);
    }

    function testEmergencyEthWithdraw_WorksForOwner() public {
        vm.deal(address(presale), 1 ether);
        uint256 before = owner.balance;

        presale.emergencyEthWithdraw();

        assertEq(owner.balance - before, 1 ether);
        assertEq(address(presale).balance, 0);
    }

    function testOnlyOwner_GuardsAdminFunctions() public {
        vm.deal(address(presale), 1 ether);

        vm.prank(attacker);
        vm.expectRevert();
        presale.pause();

        vm.prank(attacker);
        vm.expectRevert();
        presale.unpause();

        vm.prank(attacker);
        vm.expectRevert();
        presale.blackList(buyer);

        vm.prank(attacker);
        vm.expectRevert();
        presale.removeBlackList(buyer);

        vm.prank(attacker);
        vm.expectRevert();
        presale.emergencyERC20Withdraw(address(usdt), 1e6);

        vm.prank(attacker);
        vm.expectRevert();
        presale.emergencyEthWithdraw();
    }

    function _buyTenThousandWkr(address account, uint256 payment) private {
        _fundAndApproveUsdt(account);
        vm.prank(account);
        presale.buyWithStable(address(usdt), payment);
        assertEq(presale.userTokenBalance(account), 10_000e18);
    }

    function _fundAndApproveUsdt(address account) private {
        usdt.mint(account, 1_000e6);
        vm.prank(account);
        usdt.approve(address(presale), type(uint256).max);
    }

    function _buildPhases(uint256 start) private pure returns (uint256[][3] memory phases) {
        phases[0] = new uint256[](3);
        phases[1] = new uint256[](3);
        phases[2] = new uint256[](3);
        phases[0][1] = P1;
        phases[1][1] = P2;
        phases[2][1] = P3;
        phases[0][2] = start + 30 days;
        phases[1][2] = start + 60 days;
        phases[2][2] = start + 90 days;
    }
}
