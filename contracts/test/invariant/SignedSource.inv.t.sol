// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Observation} from "../../src/interfaces/IPriceSource.sol";
import {SignedSource} from "../../src/sources/SignedSource.sol";
import {SolidityReportVerifier} from "../../src/sources/SolidityReportVerifier.sol";
import {ReportBuilder} from "../unit/SignedSource.t.sol";
import {SignedMath} from "@openzeppelin/contracts/utils/math/SignedMath.sol";

/// @dev Drives SignedSource with random reports, signer subsets (including keys outside the set), timestamps
///      (stale, current, future), price spreads and jumps, signer rotations by the owner and attempts by others.
///      For every report it computes, independently, whether the rules allow it, and records any disagreement
///      with what the contract did. Parameters are mainnet's: 2 of 3, 0.5% spread, unanimity above 10%, 60 s skew.
contract SignedSourceHandler is ReportBuilder {
    uint256 internal constant BPS = 10_000;
    bytes32 public constant FEED = bytes32("CRWD/USD");

    SignedSource public immutable src;
    address public immutable owner;
    bytes32 internal immutable domain;
    Signer[] internal pool; // 5 keys, sorted by address; the current set is a subset

    // Ghost state: what the rules say the source should hold.
    address[] public ghostSet;
    uint8 public ghostQuorum;
    int192 public ghostPrice;
    uint64 public ghostObservedAt;

    // Disagreements between the rules and the contract. Each must stay zero.
    uint256 public acceptedButInvalid;
    uint256 public rejectedButValid;
    uint256 public wrongPriceStored;
    uint256 public timeWentBackwards;
    uint256 public strangerRotated;
    uint256 public validRotationRejected;

    // Coverage counters, to show the run exercised every path.
    uint256 public accepted;
    uint256 public rejected;
    uint256 public bigJumpsAccepted;
    uint256 public rotations;

    constructor(SignedSource src_, address owner_, Signer[] memory pool_, address[] memory set_, uint8 quorum_) {
        src = src_;
        owner = owner_;
        domain = src_.domainSeparator();
        for (uint256 i; i < pool_.length; ++i) {
            pool.push(pool_[i]);
        }
        ghostSet = set_;
        ghostQuorum = quorum_;
    }

    function _inSet(address a) internal view returns (bool) {
        for (uint256 i; i < ghostSet.length; ++i) {
            if (ghostSet[i] == a) return true;
        }
        return false;
    }

    struct Draft {
        Signer[] chosen;
        int192[] prices;
        uint64 t;
    }

    struct Verdict {
        bool valid;
        bool bigJump;
        int256 median;
    }

    /// @dev One report: `mask` picks signers from the pool (sorted order kept), `base` and `spread` the prices,
    ///      `timeMode` the timestamp (0 stale, 1 equal to the last, 2 fresh, 3 slightly future, 4 far future).
    function submit(uint8 mask, uint64 base, uint16 spreadBps, uint8 jumpMode, uint8 timeMode) external {
        Draft memory d = _draft(mask, base, spreadBps, jumpMode, timeMode);
        Verdict memory v = _judge(d);
        bool ok;
        try src.submit(FEED, _report(domain, FEED, d.chosen, d.prices, d.t)) {
            ok = true;
        } catch {}
        _record(ok, v, d.t);
    }

    function _draft(uint8 mask, uint64 base, uint16 spreadBps, uint8 jumpMode, uint8 timeMode)
        internal
        view
        returns (Draft memory d)
    {
        mask = uint8(bound(mask, 1, 31));
        // Price: near the last one, or a jump past the unanimity bound, or from scratch.
        int256 last = ghostPrice == 0 ? int256(26_000_000_000) : int256(ghostPrice);
        int256 center;
        jumpMode = uint8(bound(jumpMode, 0, 3));
        if (jumpMode == 0) center = last + (last * int256(uint256(bound(base, 0, 900)))) / 10_000; // < 9%
        else if (jumpMode == 1) center = last - (last * int256(uint256(bound(base, 0, 900)))) / 10_000;
        else if (jumpMode == 2) center = last * 4; // a split-sized move
        else center = last / 4 + 1;
        // Keep prices in a realistic band so repeated jumps cannot overflow the arithmetic.
        if (center > 1e15) center = last / 4;
        if (center < 1e6) center = last * 4;
        int256 spread = int256(uint256(bound(spreadBps, 0, 120))); // straddles the 50 bps bound

        d.chosen = new Signer[](5);
        d.prices = new int192[](5);
        uint256 n;
        for (uint256 i; i < 5; ++i) {
            if (mask & (1 << i) == 0) continue;
            d.chosen[n] = pool[i];
            // Prices spread around the centre, from -spread/2 to +spread/2.
            d.prices[n] =
                int192(center + (center * spread * int256(n)) / int256(BPS * 4) - (center * spread) / int256(BPS * 2));
            ++n;
        }
        Signer[] memory chosen = d.chosen;
        int192[] memory prices = d.prices;
        assembly {
            mstore(chosen, n)
            mstore(prices, n)
        }

        timeMode = uint8(bound(timeMode, 0, 4));
        if (timeMode == 0 && ghostObservedAt > 0) d.t = ghostObservedAt - 1;
        else if (timeMode == 1 && ghostObservedAt > 0) d.t = ghostObservedAt;
        else if (timeMode == 3) d.t = uint64(block.timestamp + 30);
        else if (timeMode == 4) d.t = uint64(block.timestamp + 61);
        else d.t = uint64(block.timestamp);
    }

    /// @dev The rules, computed independently of the contract.
    function _judge(Draft memory d) internal view returns (Verdict memory v) {
        uint256 n = d.chosen.length;
        v.valid = n >= ghostQuorum;
        int256 lo = type(int256).max;
        int256 hi = type(int256).min;
        int256[] memory sorted = new int256[](n);
        for (uint256 i; i < n; ++i) {
            if (!_inSet(d.chosen[i].addr)) v.valid = false;
            int256 p = d.prices[i];
            if (p < lo) lo = p;
            if (p > hi) hi = p;
            uint256 j = i;
            while (j > 0 && sorted[j - 1] > p) {
                sorted[j] = sorted[j - 1];
                --j;
            }
            sorted[j] = p;
        }
        v.median = n % 2 == 1 ? sorted[n / 2] : (sorted[n / 2 - 1] + sorted[n / 2]) / 2;
        if (lo <= 0) v.valid = false;
        if (d.t > block.timestamp + 60) v.valid = false;
        if (v.valid && (SignedMath.abs(hi - lo) * BPS) / SignedMath.abs(v.median) > 50) v.valid = false;
        if (d.t <= ghostObservedAt) v.valid = false;
        v.bigJump = ghostObservedAt != 0
            && (SignedMath.abs(v.median - int256(ghostPrice)) * BPS) / SignedMath.abs(int256(ghostPrice)) > 1000;
        if (v.bigJump && n < ghostSet.length) v.valid = false;
    }

    function _record(bool ok, Verdict memory v, uint64 t) internal {
        if (ok && !v.valid) ++acceptedButInvalid;
        if (!ok && v.valid) ++rejectedButValid;
        if (ok) {
            ++accepted;
            if (v.bigJump) ++bigJumpsAccepted;
            if (t <= ghostObservedAt) ++timeWentBackwards;
            ghostPrice = int192(v.median);
            ghostObservedAt = t;
        } else {
            ++rejected;
        }
        Observation memory o = src.observe(FEED);
        if (o.price != ghostPrice || o.observedAt != ghostObservedAt) ++wrongPriceStored;
    }

    /// @dev The owner (the timelock) rotates to a subset of the pool with a random quorum, valid or not.
    function rotate(uint8 mask, uint8 quorum_) external {
        mask = uint8(bound(mask, 1, 31));
        address[] memory set_ = new address[](5);
        uint256 n;
        for (uint256 i; i < 5; ++i) {
            if (mask & (1 << i) != 0) set_[n++] = pool[i].addr;
        }
        assembly {
            mstore(set_, n)
        }
        quorum_ = uint8(bound(quorum_, 0, 6));
        bool valid = quorum_ > 0 && quorum_ <= n && uint256(quorum_) * 2 > n;
        vm.prank(owner);
        try src.setSigners(set_, quorum_) {
            if (!valid) ++acceptedButInvalid;
            ghostSet = set_;
            ghostQuorum = quorum_;
            ++rotations;
        } catch {
            if (valid) ++validRotationRejected;
        }
    }

    /// @dev Anyone else trying to rotate must fail.
    function strangerRotates(address stranger, uint8 mask) external {
        if (stranger == owner) return;
        address[] memory set_ = new address[](1);
        set_[0] = pool[uint256(bound(mask, 0, 4))].addr;
        vm.prank(stranger);
        try src.setSigners(set_, 1) {
            ++strangerRotated;
            ghostSet = set_;
            ghostQuorum = 1;
        } catch {}
    }

    function warp(uint32 dt) external {
        vm.warp(block.timestamp + bound(dt, 0, 3 days));
    }

    function ghostSetLength() external view returns (uint256) {
        return ghostSet.length;
    }
}

contract SignedSourceInvariantTest is ReportBuilder {
    SignedSource internal src;
    SignedSourceHandler internal handler;
    address internal owner = makeAddr("timelock");

    function setUp() public {
        vm.warp(1_790_780_400);
        Signer[] memory pool = _signers(5);
        // Start like mainnet: three signers, quorum 2.
        address[] memory set_ = new address[](3);
        for (uint256 i; i < 3; ++i) {
            set_[i] = pool[i].addr;
        }
        src = new SignedSource(new SolidityReportVerifier(), owner, set_, 2, 50, 1000, 60);
        handler = new SignedSourceHandler(src, owner, pool, set_, 2);
        targetContract(address(handler));
    }

    /// The source accepts exactly the reports its rules allow, no more and no fewer.
    function invariant_acceptsExactlyTheValidReports() public view {
        assertEq(handler.acceptedButInvalid(), 0, "accepted a report or rotation the rules forbid");
        assertEq(handler.rejectedButValid(), 0, "rejected a report the rules allow");
        assertEq(handler.validRotationRejected(), 0, "owner's valid rotation rejected");
    }

    /// What it stores is the median of an accepted report, and observation times only move forward.
    function invariant_storesTheMedianAndTimeMovesForward() public view {
        assertEq(handler.wrongPriceStored(), 0, "stored price differs from the accepted report's median");
        assertEq(handler.timeWentBackwards(), 0, "a stored observation time went backwards");
        Observation memory o = src.observe(handler.FEED());
        assertEq(o.price, handler.ghostPrice());
        assertEq(o.observedAt, handler.ghostObservedAt());
    }

    /// Only the owner changes the signer set, and the quorum is always a majority of it.
    function invariant_onlyTheOwnerRotates_andQuorumIsAMajority() public view {
        assertEq(handler.strangerRotated(), 0, "someone other than the owner rotated the signers");
        address[] memory s = src.signers();
        assertEq(s.length, handler.ghostSetLength());
        assertGt(uint256(src.quorum()) * 2, s.length, "quorum is not a majority");
        assertLe(src.quorum(), s.length);
    }

    /// Coverage. With INVARIANT_COVERAGE=1, each run's counts go to cache/invariant-coverage-signed.csv for totals.
    function afterInvariant() external {
        if (!vm.envOr("INVARIANT_COVERAGE", false)) return;
        vm.writeLine(
            "cache/invariant-coverage-signed.csv",
            string.concat(
                vm.toString(handler.accepted()),
                ",",
                vm.toString(handler.rejected()),
                ",",
                vm.toString(handler.bigJumpsAccepted()),
                ",",
                vm.toString(handler.rotations())
            )
        );
    }
}
