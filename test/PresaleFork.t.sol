//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/presale.sol";
import "../src/mocks/MockERC20.sol";

contract PresaleForkTest is Test {
    // Arbitrum One Chainlink ETH/USD proxy
    address public constant ARB_ETH_USD_FEED = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;
    address payable internal treasury = payable(address(0xCAFE));

    function _selectForkOrSkip() internal {
        string memory rpcUrl = vm.envOr("ARB_RPC_URL", string(""));
        if (bytes(rpcUrl).length == 0) {
            vm.skip(true);
        }
        vm.createSelectFork(rpcUrl);
    }

    function testFork_Arbitrum_GetEtherPrice_IsPositive() public {
        _selectForkOrSkip();

        MockERC20 saleToken = new MockERC20("WKR", "WKR", 18);
        MockERC20 usdt = new MockERC20("Tether USD", "USDT", 6);
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);

        uint256 maxSellingAmount = 100_000e18;
        saleToken.mint(address(this), maxSellingAmount);

        uint256 start = block.timestamp + 1;
        uint256 t1 = start + 30 days;
        uint256 t2 = t1 + 30 days;
        uint256 t3 = t2 + 30 days;

        uint256[][3] memory phases;
        phases[0] = new uint256[](3);
        phases[1] = new uint256[](3);
        phases[2] = new uint256[](3);

        phases[0][1] = 60_000;
        phases[1][1] = 75_000;
        phases[2][1] = 90_000;
        phases[0][2] = t1;
        phases[1][2] = t2;
        phases[2][2] = t3;

        uint256 deployerNonce = vm.getNonce(address(this));
        address predictedPresale = vm.computeCreateAddress(address(this), deployerNonce);
        saleToken.approve(predictedPresale, maxSellingAmount);

        Presale presale = new Presale(
            address(saleToken),
            address(usdt),
            address(usdc),
            treasury,
            ARB_ETH_USD_FEED,
            maxSellingAmount,
            start,
            t3,
            phases,
            address(this),
            address(this)
        );

        uint256 price = presale.getEtherPrice();
        assertGt(price, 0);
    }

    function testFork_Arbitrum_BuyWithEth_UsingVmDeal() public {
        _selectForkOrSkip();

        MockERC20 saleToken = new MockERC20("WKR", "WKR", 18);
        MockERC20 usdt = new MockERC20("Tether USD", "USDT", 6);
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);

        uint256 maxSellingAmount = 100_000e18;
        saleToken.mint(address(this), maxSellingAmount);

        uint256 start = block.timestamp + 1;
        uint256 t1 = start + 30 days;
        uint256 t2 = t1 + 30 days;
        uint256 t3 = t2 + 30 days;

        uint256[][3] memory phases;
        phases[0] = new uint256[](3);
        phases[1] = new uint256[](3);
        phases[2] = new uint256[](3);
        phases[0][1] = 60_000;
        phases[1][1] = 75_000;
        phases[2][1] = 90_000;
        phases[0][2] = t1;
        phases[1][2] = t2;
        phases[2][2] = t3;

        uint256 deployerNonce = vm.getNonce(address(this));
        address predictedPresale = vm.computeCreateAddress(address(this), deployerNonce);
        saleToken.approve(predictedPresale, maxSellingAmount);

        Presale presale = new Presale(
            address(saleToken),
            address(usdt),
            address(usdc),
            treasury,
            ARB_ETH_USD_FEED,
            maxSellingAmount,
            start,
            t3,
            phases,
            address(this),
            address(this)
        );

        address buyer = address(0xBEEF);
        vm.deal(buyer, 2 ether);
        vm.warp(start + 1);

        vm.prank(buyer);
        presale.buyWithEth{value: 0.01 ether}();

        assertGt(presale.userTokenBalance(buyer), 0);
    }

    function testFork_Arbitrum_PauseBlocksEthBuy() public {
        _selectForkOrSkip();

        MockERC20 saleToken = new MockERC20("WKR", "WKR", 18);
        MockERC20 usdt = new MockERC20("Tether USD", "USDT", 6);
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);

        uint256 maxSellingAmount = 100_000e18;
        saleToken.mint(address(this), maxSellingAmount);

        uint256 start = block.timestamp + 1;
        uint256 t1 = start + 30 days;
        uint256 t2 = t1 + 30 days;
        uint256 t3 = t2 + 30 days;

        uint256[][3] memory phases;
        phases[0] = new uint256[](3);
        phases[1] = new uint256[](3);
        phases[2] = new uint256[](3);
        phases[0][1] = 60_000;
        phases[1][1] = 75_000;
        phases[2][1] = 90_000;
        phases[0][2] = t1;
        phases[1][2] = t2;
        phases[2][2] = t3;

        uint256 deployerNonce = vm.getNonce(address(this));
        address predictedPresale = vm.computeCreateAddress(address(this), deployerNonce);
        saleToken.approve(predictedPresale, maxSellingAmount);

        Presale presale = new Presale(
            address(saleToken),
            address(usdt),
            address(usdc),
            treasury,
            ARB_ETH_USD_FEED,
            maxSellingAmount,
            start,
            t3,
            phases,
            address(this),
            address(this)
        );

        presale.pause();

        address buyer = address(0xBEEF);
        vm.deal(buyer, 1 ether);
        vm.warp(start + 1);

        vm.prank(buyer);
        vm.expectRevert();
        presale.buyWithEth{value: 0.1 ether}();
    }
}
