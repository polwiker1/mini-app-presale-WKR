// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {Presale} from "../src/presale.sol";
import {WKR} from "../src/WKR.sol";

/**
 * @title DeployWKRPresale
 * @notice Deploy y fondeo de preventa (presale) WKR.
 * @dev
 * Variables de entorno esperadas:
 * - PRIVATE_KEY                  -> deployer tecnico
 * - WKR_ADDRESS                  -> token WKR ya desplegado
 * - USDT_ADDRESS                 -> stablecoin USDT para testnet/mainnet
 * - USDC_ADDRESS                 -> stablecoin USDC para testnet/mainnet
 * - ETH_USD_FEED                 -> Chainlink ETH/USD feed
 * - FUNDS_RECEIVER               -> wallet que recibe USDT/USDC/ETH de compras
 *
 * Variables opcionales:
 * - PRESALE_SUPPLY_TOKENS        -> default 100000
 * - PRESALE_START_TIMESTAMP      -> unix timestamp absoluto de inicio; si se omite usa delay
 * - PRESALE_START_DELAY_SECONDS  -> default 3600
 * - PRESALE_PHASE_DURATION       -> default 2592000 (30 dias)
 * - PRESALE_OWNER                -> owner administrativo de Presale, default deployer
 * - SALE_TOKEN_OWNER             -> wallet que aporta los WKR, default deployer
 */
contract DeployWKRPresale is Script {
    uint256 internal constant DEFAULT_PRESALE_SUPPLY_TOKENS = 100_000;
    uint256 internal constant DEFAULT_START_DELAY_SECONDS = 1 hours;
    uint256 internal constant DEFAULT_PHASE_DURATION = 30 days;

    uint256 internal constant PHASE_1_PRICE_USD6 = 60_000; // 0.06
    uint256 internal constant PHASE_2_PRICE_USD6 = 75_000; // 0.075
    uint256 internal constant PHASE_3_PRICE_USD6 = 90_000; // 0.09

    function run() external {
        uint256 deployerPk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPk);

        WKR wkr = WKR(vm.envAddress("WKR_ADDRESS"));
        address usdt = vm.envAddress("USDT_ADDRESS");
        address usdc = vm.envAddress("USDC_ADDRESS");
        address ethUsdFeed = vm.envAddress("ETH_USD_FEED");
        address fundsReceiver = vm.envAddress("FUNDS_RECEIVER");
        address presaleOwner = vm.envOr("PRESALE_OWNER", deployer);
        address saleTokenOwner = vm.envOr("SALE_TOKEN_OWNER", deployer);

        uint256 presaleSupplyTokens = vm.envOr("PRESALE_SUPPLY_TOKENS", DEFAULT_PRESALE_SUPPLY_TOKENS);
        uint256 startTimestamp = vm.envOr("PRESALE_START_TIMESTAMP", uint256(0));
        uint256 startDelay = vm.envOr("PRESALE_START_DELAY_SECONDS", DEFAULT_START_DELAY_SECONDS);
        uint256 phaseDuration = vm.envOr("PRESALE_PHASE_DURATION", DEFAULT_PHASE_DURATION);

        require(fundsReceiver != address(0), "FUNDS_RECEIVER zero");
        require(usdt != address(0), "USDT_ADDRESS zero");
        require(usdc != address(0), "USDC_ADDRESS zero");
        require(ethUsdFeed != address(0), "ETH_USD_FEED zero");
        require(presaleOwner != address(0), "PRESALE_OWNER zero");
        require(saleTokenOwner != address(0), "SALE_TOKEN_OWNER zero");
        require(presaleSupplyTokens == DEFAULT_PRESALE_SUPPLY_TOKENS, "Presale supply must be 100000 WKR");

        uint256 start = startTimestamp == 0 ? block.timestamp + startDelay : startTimestamp;
        require(start > block.timestamp, "Presale start must be future");
        uint256 phase1End = start + phaseDuration;
        uint256 phase2End = phase1End + phaseDuration;
        uint256 phase3End = phase2End + phaseDuration;
        uint256 maxSellingAmount = presaleSupplyTokens * 1e18;

        uint256[][3] memory phases = _buildPhases(phase1End, phase2End, phase3End);

        bool deployerCanPrepareWkr = wkr.owner() == deployer && saleTokenOwner == deployer;
        uint256 presaleNonce = vm.getNonce(deployer) + (deployerCanPrepareWkr ? 2 : 0);
        address predictedPresale = vm.computeCreateAddress(deployer, presaleNonce);

        require(wkr.balanceOf(saleTokenOwner) >= maxSellingAmount, "Insufficient WKR balance");

        if (!deployerCanPrepareWkr) {
            require(wkr.isPresaleExempt(predictedPresale), "Presale must be WKR exempt");
            require(wkr.allowance(saleTokenOwner, predictedPresale) >= maxSellingAmount, "Presale allowance missing");
        }

        vm.startBroadcast(deployerPk);

        if (deployerCanPrepareWkr) {
            wkr.setPresaleExempt(predictedPresale, true);
            wkr.approve(predictedPresale, maxSellingAmount);
        }

        new Presale(
            address(wkr),
            usdt,
            usdc,
            fundsReceiver,
            ethUsdFeed,
            maxSellingAmount,
            start,
            phase3End,
            phases,
            presaleOwner,
            saleTokenOwner
        );

        vm.stopBroadcast();
    }

    function _buildPhases(uint256 phase1End, uint256 phase2End, uint256 phase3End)
        internal
        pure
        returns (uint256[][3] memory phases)
    {
        phases[0] = new uint256[](3);
        phases[1] = new uint256[](3);
        phases[2] = new uint256[](3);

        phases[0][1] = PHASE_1_PRICE_USD6;
        phases[1][1] = PHASE_2_PRICE_USD6;
        phases[2][1] = PHASE_3_PRICE_USD6;

        phases[0][2] = phase1End;
        phases[1][2] = phase2End;
        phases[2][2] = phase3End;
    }
}
