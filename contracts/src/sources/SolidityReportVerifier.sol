// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IReportVerifier} from "../interfaces/IReportVerifier.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/// @title SolidityReportVerifier
/// @notice Reference implementation of `IReportVerifier`. Stateless.
contract SolidityReportVerifier is IReportVerifier {
    bytes32 public constant OBSERVATION_TYPEHASH =
        keccak256("Observation(bytes32 feedId,int192 price,uint64 observedAt)");

    uint256 internal constant ENTRY = 97;

    error EmptyReport();
    error MalformedReport(uint256 length);
    error InvalidSignature(uint256 index);
    error SignersNotAscending(uint256 index);

    /// @inheritdoc IReportVerifier
    function verify(bytes32 domainSeparator, bytes32 feedId, bytes calldata report)
        external
        pure
        returns (
            address[] memory signers,
            int256 medianPrice,
            int256 minPrice,
            int256 maxPrice,
            uint64 medianObservedAt,
            uint64 maxObservedAt
        )
    {
        int192[] memory prices;
        uint64[] memory times;
        (signers, prices, times) = _decode(domainSeparator, feedId, report);
        uint256 n = prices.length;

        _sortPrices(prices);
        _sortTimes(times);
        minPrice = prices[0];
        maxPrice = prices[n - 1];
        medianPrice = n % 2 == 1 ? prices[n / 2] : _avg(prices[n / 2 - 1], prices[n / 2]);
        medianObservedAt = times[n / 2];
        maxObservedAt = times[n - 1];
    }

    function _decode(bytes32 domainSeparator, bytes32 feedId, bytes calldata report)
        private
        pure
        returns (address[] memory signers, int192[] memory prices, uint64[] memory times)
    {
        if (report.length == 0) revert EmptyReport();
        if (report.length % ENTRY != 0) revert MalformedReport(report.length);
        uint256 n = report.length / ENTRY;

        signers = new address[](n);
        prices = new int192[](n);
        times = new uint64[](n);

        address previous;
        for (uint256 i; i < n; ++i) {
            (address signer, int192 price, uint64 observedAt) =
                _recover(domainSeparator, feedId, report[i * ENTRY:(i + 1) * ENTRY], i);
            if (signer <= previous) revert SignersNotAscending(i);
            previous = signer;

            signers[i] = signer;
            prices[i] = price;
            times[i] = observedAt;
        }
    }

    function _recover(bytes32 domainSeparator, bytes32 feedId, bytes calldata entry, uint256 index)
        private
        pure
        returns (address signer, int192 price, uint64 observedAt)
    {
        price = int192(uint192(uint256(bytes32(entry[0:24])) >> 64));
        observedAt = uint64(bytes8(entry[24:32]));
        bytes32 digest = MessageHashUtils.toTypedDataHash(
            domainSeparator, keccak256(abi.encode(OBSERVATION_TYPEHASH, feedId, price, observedAt))
        );
        ECDSA.RecoverError err;
        (signer, err,) = ECDSA.tryRecover(digest, uint8(entry[96]), bytes32(entry[32:64]), bytes32(entry[64:96]));
        if (err != ECDSA.RecoverError.NoError) revert InvalidSignature(index);
    }

    /// @dev Rounds towards negative infinity; cannot overflow for int192 inputs.
    function _avg(int192 a, int192 b) private pure returns (int192) {
        return int192((int256(a) + int256(b)) >> 1);
    }

    function _sortPrices(int192[] memory a) private pure {
        for (uint256 i = 1; i < a.length; ++i) {
            int192 key = a[i];
            uint256 j = i;
            while (j > 0 && a[j - 1] > key) {
                a[j] = a[j - 1];
                --j;
            }
            a[j] = key;
        }
    }

    function _sortTimes(uint64[] memory a) private pure {
        for (uint256 i = 1; i < a.length; ++i) {
            uint64 key = a[i];
            uint256 j = i;
            while (j > 0 && a[j - 1] > key) {
                a[j] = a[j - 1];
                --j;
            }
            a[j] = key;
        }
    }
}
