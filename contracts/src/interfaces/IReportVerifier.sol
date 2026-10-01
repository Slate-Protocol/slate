// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Verifies a packed, multi-signer price report and summarises it.
/// @dev Implemented in Solidity (`SolidityReportVerifier`) and in Rust on Stylus (`slate-verifier`);
///      both must return identical results for identical input.
///
///      Report layout: `n` entries of 97 bytes each, no header.
///        [0:24)   int192 price, big-endian two's complement
///        [24:32)  uint64 observedAt
///        [32:64)  bytes32 r
///        [64:96)  bytes32 s   (must be in the lower half order)
///        [96]     uint8   v   (27 or 28)
///      Each entry is an EIP-712 signature over
///        Observation(bytes32 feedId,int192 price,uint64 observedAt)
///      under the caller-supplied domain separator. Recovered signers must be strictly ascending.
interface IReportVerifier {
    struct Summary {
        address[] signers;
        int192 medianPrice;
        int192 minPrice;
        int192 maxPrice;
        uint64 medianObservedAt;
        uint64 maxObservedAt;
    }

    function verify(bytes32 domainSeparator, bytes32 feedId, bytes calldata report)
        external
        view
        returns (Summary memory);
}
