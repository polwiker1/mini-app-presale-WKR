//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./IAggregator.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Presale is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public saleTokenAddress;
    address public usdtAddress;
    address public usdcAddress;
    address public fundsReceiverAddress;
    address public datafeedaddress;

    uint256 public maxSellingAmount;
    uint256 public startingTime;
    uint256 public endingTime;
    uint256[][3] public phases;

    uint256 public currentPhase;
    uint256 public totalSold;
    uint256 public totalClaimed;
    uint256 public constant MAX_PRICE_AGE = 1 hours;
    uint256 public constant MAX_TOKENS_PER_WALLET = 10_000 * 1e18;
    uint256 public constant MIN_ETH_PURCHASE = 0.0001 ether;
    uint256 public constant MIN_STABLE_PURCHASE_USD18 = 1e18;

    mapping(address => uint256) public userTokenBalance;
    mapping(address => bool) public isBlackListed;

    event TokenBuy(address user, uint256 amountPaid);
    event DataFeedUpdated(address indexed previousFeed, address indexed newFeed);

    constructor(
        address saleTokenAddress_,
        address usdtAddress_,
        address usdcAddress_,
        address fundsReceiverAddress_,
        address datafeedaddress_,
        uint256 maxSellingAmount_,
        uint256 startingTime_,
        uint256 endingTime_,
        uint256[][3] memory phases_
    ) Ownable(msg.sender) {
        saleTokenAddress = saleTokenAddress_;
        usdtAddress = usdtAddress_;
        usdcAddress = usdcAddress_;
        fundsReceiverAddress = fundsReceiverAddress_;
        datafeedaddress = datafeedaddress_;
        maxSellingAmount = maxSellingAmount_;
        startingTime = startingTime_;
        endingTime = endingTime_;
        phases = phases_;

        require(endingTime > startingTime, "Ending time must be greater than starting time");
        require(phases[0].length >= 3 && phases[1].length >= 3 && phases[2].length >= 3, "Invalid phases");
        require(phases[0][1] > 0 && phases[1][1] > 0 && phases[2][1] > 0, "Invalid phase price");
        require(phases[0][2] > startingTime, "Invalid phase 1 end");
        require(phases[1][2] > phases[0][2], "Invalid phase 2 end");
        require(phases[2][2] > phases[1][2], "Invalid phase 3 end");
        require(phases[2][2] == endingTime, "Phase 3 end mismatch");
        require(datafeedaddress != address(0), "Data feed zero");
        _getEtherPrice(datafeedaddress);
        require(IERC20Metadata(saleTokenAddress_).decimals() == 18, "Sale token must have 18 decimals");

        // phases[i] = [capAcumulado, priceUsd6, endTime]
        uint256 phaseAmount = maxSellingAmount / 3;
        uint256 cap0 = phaseAmount;
        uint256 cap1 = phaseAmount * 2;
        uint256 cap2 = maxSellingAmount;

        phases[0][0] = cap0;
        phases[1][0] = cap1;
        phases[2][0] = cap2;

        IERC20(saleTokenAddress).safeTransferFrom(msg.sender, address(this), maxSellingAmount);
    }

    function blackList(address user_) external onlyOwner {
        isBlackListed[user_] = true;
    }

    function removeBlackList(address user_) external onlyOwner {
        isBlackListed[user_] = false;
    }

    function checksCurrentPhase(uint256 amount_) private {
        while (currentPhase < 3) {
            bool withinCap = totalSold + amount_ <= phases[currentPhase][0];
            bool withinTime = block.timestamp <= phases[currentPhase][2];

            if (withinCap && withinTime) {
                return;
            }

            currentPhase++;
        }

        revert("No active phase");
    }

    function quoteTokenAmount(uint256 usdAmount18_) private view returns (uint256 tokenAmount, uint256 finalPhase) {
        uint256 phase = currentPhase;
        uint256 simulatedSold = totalSold;
        uint256 remainingUsd18 = usdAmount18_;

        while (remainingUsd18 > 0) {
            while (phase < 3 && (simulatedSold >= phases[phase][0] || block.timestamp > phases[phase][2])) {
                phase++;
            }

            require(phase < 3, "No active phase");

            uint256 phaseCap = phases[phase][0];
            uint256 availableInPhase = phaseCap - simulatedSold;
            uint256 phasePriceUsd6 = phases[phase][1];
            uint256 tokensAtPhasePrice = remainingUsd18 * 1e6 / phasePriceUsd6;

            require(tokensAtPhasePrice > 0, "Payment too small for active phase");

            if (tokensAtPhasePrice <= availableInPhase) {
                tokenAmount += tokensAtPhasePrice;
                simulatedSold += tokensAtPhasePrice;
                remainingUsd18 = 0;
            } else {
                tokenAmount += availableInPhase;
                simulatedSold += availableInPhase;
                remainingUsd18 -= availableInPhase * phasePriceUsd6 / 1e6;
            }
        }

        finalPhase = phase;
    }

    function buyWithStable(address tokenUsedToBuy_, uint256 amount_) external whenNotPaused {
        require(!isBlackListed[msg.sender], "You are blacklisted");
        require(block.timestamp > startingTime, "Presale has not started yet");
        require(block.timestamp <= endingTime, "Presale has ended");
        require(tokenUsedToBuy_ == usdtAddress || tokenUsedToBuy_ == usdcAddress, "Invalid token address");

        checksCurrentPhase(0);

        uint8 stableDecimals = IERC20Metadata(tokenUsedToBuy_).decimals();
        require(stableDecimals <= 18, "Unsupported token decimals");

        uint256 stableAmount18 = amount_ * (10 ** (18 - stableDecimals));
        require(stableAmount18 >= MIN_STABLE_PURCHASE_USD18, "Stable amount below minimum");
        (uint256 tokenAmountToReceive, uint256 finalPhase) = quoteTokenAmount(stableAmount18);

        require(
            userTokenBalance[msg.sender] + tokenAmountToReceive <= MAX_TOKENS_PER_WALLET,
            "Exceeds max presale per wallet"
        );
        totalSold += tokenAmountToReceive;
        require(totalSold <= maxSellingAmount, "Exceeds maximum selling amount");

        userTokenBalance[msg.sender] += tokenAmountToReceive;
        currentPhase = finalPhase;
        IERC20(tokenUsedToBuy_).safeTransferFrom(msg.sender, fundsReceiverAddress, amount_);

        emit TokenBuy(msg.sender, amount_);
    }

    function buyWithEth() external payable whenNotPaused nonReentrant {
        require(!isBlackListed[msg.sender], "You are blacklisted");
        require(block.timestamp > startingTime, "Presale has not started yet");
        require(block.timestamp <= endingTime, "Presale has ended");
        require(msg.value >= MIN_ETH_PURCHASE, "ETH amount below minimum");

        uint256 usdValue = (msg.value * getEtherPrice()) / 1e18;
        checksCurrentPhase(0);

        (uint256 tokenAmountToReceive, uint256 finalPhase) = quoteTokenAmount(usdValue);

        require(
            userTokenBalance[msg.sender] + tokenAmountToReceive <= MAX_TOKENS_PER_WALLET,
            "Exceeds max presale per wallet"
        );
        totalSold += tokenAmountToReceive;
        userTokenBalance[msg.sender] += tokenAmountToReceive;
        currentPhase = finalPhase;

        (bool success,) = fundsReceiverAddress.call{value: msg.value}("");
        require(success, "Transfer failed.");

        emit TokenBuy(msg.sender, msg.value);
    }

    function claim() external {
        require(block.timestamp > endingTime, "Presale has not ended yet");

        uint256 amount = userTokenBalance[msg.sender];
        delete userTokenBalance[msg.sender];
        totalClaimed += amount;

        IERC20(saleTokenAddress).safeTransfer(msg.sender, amount);
    }

    function getEtherPrice() public view returns (uint256) {
        return _getEtherPrice(datafeedaddress);
    }

    function updateDataFeed(address newDataFeed_) external onlyOwner {
        require(newDataFeed_ != address(0), "Data feed zero");
        _getEtherPrice(newDataFeed_);

        address previousFeed = datafeedaddress;
        datafeedaddress = newDataFeed_;
        emit DataFeedUpdated(previousFeed, newDataFeed_);
    }

    function _getEtherPrice(address dataFeed_) private view returns (uint256) {
        (uint80 roundId, int256 price,, uint256 updatedAt, uint80 answeredInRound) =
            IAggregator(dataFeed_).latestRoundData();

        require(price > 0, "Invalid ETH price");
        require(answeredInRound >= roundId, "Stale round");
        require(updatedAt > 0, "Round not complete");
        require(block.timestamp - updatedAt <= MAX_PRICE_AGE, "Price too old");

        uint8 feedDecimals = IAggregator(dataFeed_).decimals();
        require(feedDecimals <= 18, "Unsupported feed decimals");
        return uint256(price) * (10 ** (18 - feedDecimals));
    }

    /**
     * @dev El owner puede recuperar remanentes no vendidos, incluido polvo final que no pueda comprarse por minimos
     *      de compra o por redondeos, y enviarlos a tesoreria. Los tokens reservados para compradores quedan protegidos.
     */
    function emergencyERC20Withdraw(address tokenAddress_, uint256 amount_) external onlyOwner {
        if (tokenAddress_ == saleTokenAddress) {
            uint256 reservedForBuyers = totalSold - totalClaimed;
            uint256 saleTokenBalance = IERC20(saleTokenAddress).balanceOf(address(this));
            require(saleTokenBalance >= reservedForBuyers, "Sale token reserve broken");
            require(amount_ <= saleTokenBalance - reservedForBuyers, "Reserved sale tokens");
        }
        IERC20(tokenAddress_).safeTransfer(msg.sender, amount_);
    }

    function emergencyEthWithdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        (bool success,) = msg.sender.call{value: balance}("");
        require(success, "Transfer failed.");
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
