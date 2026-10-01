// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPriceSource, Observation, PriceKind} from "../../src/interfaces/IPriceSource.sol";

contract MockPriceSource is IPriceSource {
    PriceKind public immutable priceKind;
    Observation private _obs;

    constructor(PriceKind kind_) {
        priceKind = kind_;
    }

    function set(int256 price, uint8 decimals, uint256 observedAt) external {
        // forge-lint: disable-next-line(unsafe-typecast)
        _obs = Observation({price: price, decimals: decimals, observedAt: uint64(observedAt)});
    }

    function kind(bytes32) external view returns (PriceKind) {
        return priceKind;
    }

    function observe(bytes32) external view returns (Observation memory) {
        return _obs;
    }
}
