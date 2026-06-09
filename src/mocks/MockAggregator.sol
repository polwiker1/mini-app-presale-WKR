//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract MockAggregator {
    uint8 public constant decimals = 8;
    int256 public answer;
    uint256 public updatedAt;
    uint80 public roundId;
    uint80 public answeredInRound;

    constructor(int256 answer_) {
        roundId = 1;
        answeredInRound = 1;
        answer = answer_;
        updatedAt = block.timestamp;
    }

    function setAnswer(int256 answer_) external {
        answer = answer_;
        roundId++;
        answeredInRound = roundId;
        updatedAt = block.timestamp;
    }

    function setStale(uint256 updatedAt_) external {
        updatedAt = updatedAt_;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (roundId, answer, updatedAt, updatedAt, answeredInRound);
    }
}
