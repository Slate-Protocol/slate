// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AggregatorV3Interface} from "../../src/interfaces/AggregatorV3Interface.sol";

contract MockAggregator is AggregatorV3Interface {
    uint8 public immutable decimals;
    int256 public answer;
    uint256 public updatedAt;
    bool public reverts;

    constructor(uint8 decimals_) {
        decimals = decimals_;
    }

    function set(int256 answer_, uint256 updatedAt_) external {
        answer = answer_;
        updatedAt = updatedAt_;
    }

    function setReverts(bool reverts_) external {
        reverts = reverts_;
    }

    function description() external pure returns (string memory) {
        return "mock";
    }

    function version() external pure returns (uint256) {
        return 1;
    }

    function getRoundData(uint80) external pure returns (uint80, int256, uint256, uint256, uint80) {
        revert("no history");
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        require(!reverts, "mock revert");
        return (1, answer, updatedAt, updatedAt, 1);
    }
}
