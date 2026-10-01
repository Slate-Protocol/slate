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
///      Prices are returned as int256 (each fits int192) and the results as plain return values, not a struct,
///      so the Solidity and Stylus encodings are identical.
interface IReportVerifier {
    /// @return signers Recovered signers, strictly ascending.
    /// @return medianPrice Median price; for an even count, the floor of the mean of the middle two.
    /// @return minPrice Lowest price.
    /// @return maxPrice Highest price.
    /// @return medianObservedAt Median observation time (upper middle for an even count).
    /// @return maxObservedAt Latest observation time.
    function verify(bytes32 domainSeparator, bytes32 feedId, bytes calldata report)
        external
        view
        returns (
            address[] memory signers,
            int256 medianPrice,
            int256 minPrice,
            int256 maxPrice,
            uint64 medianObservedAt,
            uint64 maxObservedAt
        );
}
