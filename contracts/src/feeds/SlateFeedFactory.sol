// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AggregatorV3Interface} from "../interfaces/AggregatorV3Interface.sol";
import {Quote} from "../interfaces/ISlateFeed.sol";
import {SlateFeed} from "./SlateFeed.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {SignedMath} from "@openzeppelin/contracts/utils/math/SignedMath.sol";

/// @title SlateFeedFactory
/// @notice Deploys `SlateFeed`s at deterministic addresses, optionally checked against a reference feed.
/// @dev Calibration is the guard against the double-count bug: a source declared with the wrong price kind
///      is off by the multiplier, so a feed that disagrees with an independent reference by more than
///      `maxDiffBps` is never deployed. Salts are bound to the caller so addresses cannot be squatted.
contract SlateFeedFactory {
    uint256 private constant BPS = 10_000;
    uint8 private constant DECIMALS = 8;

    event FeedDeployed(address indexed feed, address indexed token, bytes32 indexed feedId, address deployer);

    error CalibrationFailed(int256 answer, int256 referenceAnswer);

    function deploy(SlateFeed.Config calldata config, bytes32 salt) public returns (SlateFeed feed) {
        feed = new SlateFeed{salt: _salt(msg.sender, salt)}(config);
        emit FeedDeployed(address(feed), config.token, config.feedId, msg.sender);
    }

    /// @notice Deploys a feed and reverts unless its current answer is within `maxDiffBps` of `reference`.
    function deployCalibrated(
        SlateFeed.Config calldata config,
        bytes32 salt,
        AggregatorV3Interface referenceFeed,
        uint16 maxDiffBps
    ) external returns (SlateFeed feed) {
        feed = deploy(config, salt);
        Quote memory q = feed.latestQuote();
        (, int256 ref,,,) = referenceFeed.latestRoundData();
        ref = _normalize(ref, referenceFeed.decimals());
        if (q.answer <= 0 || ref <= 0) revert CalibrationFailed(q.answer, ref);
        if (Math.mulDiv(SignedMath.abs(q.answer - ref), BPS, SafeCast.toUint256(ref)) > maxDiffBps) {
            revert CalibrationFailed(q.answer, ref);
        }
    }

    function predict(SlateFeed.Config calldata config, bytes32 salt, address deployer) external view returns (address) {
        bytes32 initHash = keccak256(abi.encodePacked(type(SlateFeed).creationCode, abi.encode(config)));
        return address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), _salt(deployer, salt), initHash))))
        );
    }

    function _salt(address deployer, bytes32 salt) private pure returns (bytes32) {
        return keccak256(abi.encode(deployer, salt));
    }

    function _normalize(int256 value, uint8 decimals) private pure returns (int256) {
        if (decimals == DECIMALS) return value;
        if (decimals > DECIMALS) return value / int256(10 ** (decimals - DECIMALS));
        return value * int256(10 ** (DECIMALS - decimals));
    }
}
