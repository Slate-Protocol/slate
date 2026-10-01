// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPriceSource, Observation, PriceKind} from "../interfaces/IPriceSource.sol";
import {IReportVerifier} from "../interfaces/IReportVerifier.sol";
import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignedMath} from "@openzeppelin/contracts/utils/math/SignedMath.sol";

/// @title SignedSource
/// @notice Underlying share prices attested by a K-of-N committee of signers, relayed by anyone.
/// @dev The only off-chain input in Slate is the share price itself. This contract bounds what a
///      committee can do with it:
///      - a report needs `quorum` distinct authorised signers, and a majority quorum is enforced;
///      - signers must agree to within `maxSpreadBps`;
///      - a report must be strictly newer than the last one and not from the future;
///      - a move larger than `unanimousJumpBps` needs every signer, so a split-day drop or a crash still
///        gets through, but a minority or a stale quorum cannot move the price far.
///      The owner can only rotate the signer set (in deployment it is a 48h timelock). The bounds above are
///      immutable.
contract SignedSource is IPriceSource, EIP712, Ownable2Step {
    uint8 public constant DECIMALS = 8;
    uint256 public constant MAX_SIGNERS = 31;
    uint256 private constant BPS = 10_000;

    IReportVerifier public immutable verifier;
    uint16 public immutable maxSpreadBps;
    uint16 public immutable unanimousJumpBps;
    uint32 public immutable maxFutureSkew;

    struct Latest {
        int192 price;
        uint64 observedAt;
    }

    mapping(address signer => bool) public isSigner;
    address[] private _signers;
    uint8 public quorum;
    mapping(bytes32 feedId => Latest) private _latest;

    event SignersUpdated(address[] signers, uint8 quorum);
    event PriceUpdated(bytes32 indexed feedId, int192 price, uint64 observedAt, uint256 signerCount);

    error ZeroAddress();
    error InvalidSignerSet();
    error UnknownSigner(address signer);
    error QuorumNotMet(uint256 signed, uint256 required);
    error NonPositivePrice();
    error SpreadTooWide(uint256 spreadBps);
    error FutureObservation(uint64 observedAt);
    error StaleReport(uint64 observedAt, uint64 latestObservedAt);

    constructor(
        IReportVerifier verifier_,
        address owner_,
        address[] memory signers_,
        uint8 quorum_,
        uint16 maxSpreadBps_,
        uint16 unanimousJumpBps_,
        uint32 maxFutureSkew_
    ) EIP712("Slate SignedSource", "1") Ownable(owner_) {
        if (address(verifier_) == address(0)) revert ZeroAddress();
        verifier = verifier_;
        maxSpreadBps = maxSpreadBps_;
        unanimousJumpBps = unanimousJumpBps_;
        maxFutureSkew = maxFutureSkew_;
        _setSigners(signers_, quorum_);
    }

    // ------------------------------------------------------------------------------------------------
    // Reporting
    // ------------------------------------------------------------------------------------------------

    /// @notice Accepts a signed report for `feedId`. Anyone may relay.
    function submit(bytes32 feedId, bytes calldata report) external {
        IReportVerifier.Summary memory s = verifier.verify(_domainSeparatorV4(), feedId, report);

        uint256 n = s.signers.length;
        for (uint256 i; i < n; ++i) {
            if (!isSigner[s.signers[i]]) revert UnknownSigner(s.signers[i]);
        }
        if (n < quorum) revert QuorumNotMet(n, quorum);
        if (s.minPrice <= 0) revert NonPositivePrice();
        if (s.maxObservedAt > block.timestamp + maxFutureSkew) revert FutureObservation(s.maxObservedAt);

        uint256 spread = (SignedMath.abs(int256(s.maxPrice) - int256(s.minPrice)) * BPS) / SignedMath.abs(s.medianPrice);
        if (spread > maxSpreadBps) revert SpreadTooWide(spread);

        Latest memory prev = _latest[feedId];
        if (s.medianObservedAt <= prev.observedAt) revert StaleReport(s.medianObservedAt, prev.observedAt);
        if (prev.observedAt != 0 && _jumpBps(prev.price, s.medianPrice) > unanimousJumpBps) {
            if (n < _signers.length) revert QuorumNotMet(n, _signers.length);
        }

        _latest[feedId] = Latest({price: s.medianPrice, observedAt: s.medianObservedAt});
        emit PriceUpdated(feedId, s.medianPrice, s.medianObservedAt, n);
    }

    // ------------------------------------------------------------------------------------------------
    // IPriceSource
    // ------------------------------------------------------------------------------------------------

    /// @inheritdoc IPriceSource
    function kind(bytes32) external pure returns (PriceKind) {
        return PriceKind.RAW_UNDERLYING;
    }

    /// @inheritdoc IPriceSource
    function observe(bytes32 feedId) external view returns (Observation memory) {
        Latest memory l = _latest[feedId];
        return Observation({price: l.price, decimals: DECIMALS, observedAt: l.observedAt});
    }

    // ------------------------------------------------------------------------------------------------
    // Signer set
    // ------------------------------------------------------------------------------------------------

    function setSigners(address[] calldata signers_, uint8 quorum_) external onlyOwner {
        _setSigners(signers_, quorum_);
    }

    function signers() external view returns (address[] memory) {
        return _signers;
    }

    /// @notice The EIP-712 domain separator signers sign under.
    function domainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    function _setSigners(address[] memory signers_, uint8 quorum_) private {
        uint256 n = signers_.length;
        if (n == 0 || n > MAX_SIGNERS || quorum_ == 0 || quorum_ > n || uint256(quorum_) * 2 <= n) {
            revert InvalidSignerSet();
        }
        for (uint256 i; i < _signers.length; ++i) {
            isSigner[_signers[i]] = false;
        }
        for (uint256 i; i < n; ++i) {
            address signer = signers_[i];
            if (signer == address(0) || isSigner[signer]) revert InvalidSignerSet();
            isSigner[signer] = true;
        }
        _signers = signers_;
        quorum = quorum_;
        emit SignersUpdated(signers_, quorum_);
    }

    /// @dev `from` is a stored price, so it is positive.
    function _jumpBps(int192 from, int192 to) private pure returns (uint256) {
        return (SignedMath.abs(int256(to) - int256(from)) * BPS) / SignedMath.abs(from);
    }
}
