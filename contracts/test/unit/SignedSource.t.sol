// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {USMarketCalendar} from "../../src/calendar/USMarketCalendar.sol";
import {SlateFeed} from "../../src/feeds/SlateFeed.sol";
import {Session} from "../../src/interfaces/IMarketCalendar.sol";
import {Observation, PriceKind} from "../../src/interfaces/IPriceSource.sol";
import {FeedStatus, Quote} from "../../src/interfaces/ISlateFeed.sol";
import {MultiplierModel} from "../../src/libraries/MultiplierLens.sol";
import {SignedSource} from "../../src/sources/SignedSource.sol";
import {SolidityReportVerifier} from "../../src/sources/SolidityReportVerifier.sol";
import {MockStockToken} from "../mocks/MockStockToken.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {Test} from "forge-std/Test.sol";

/// @dev Builds and signs packed reports in the layout `IReportVerifier` documents.
abstract contract ReportBuilder is Test {
    bytes32 internal constant OBSERVATION_TYPEHASH =
        keccak256("Observation(bytes32 feedId,int192 price,uint64 observedAt)");
    uint256 internal constant SECP256K1_N = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;

    struct Signer {
        address addr;
        uint256 key;
    }

    /// @dev Signers sorted by address ascending, as reports require.
    function _signers(uint256 n) internal returns (Signer[] memory s) {
        s = new Signer[](n);
        for (uint256 i; i < n; ++i) {
            (address a, uint256 k) = makeAddrAndKey(string.concat("signer", vm.toString(i)));
            s[i] = Signer(a, k);
        }
        for (uint256 i = 1; i < n; ++i) {
            Signer memory key = s[i];
            uint256 j = i;
            while (j > 0 && s[j - 1].addr > key.addr) {
                s[j] = s[j - 1];
                --j;
            }
            s[j] = key;
        }
    }

    function _entry(bytes32 domain, bytes32 feedId, Signer memory signer, int192 price, uint64 observedAt)
        internal
        pure
        returns (bytes memory)
    {
        bytes32 digest = MessageHashUtils.toTypedDataHash(
            domain, keccak256(abi.encode(OBSERVATION_TYPEHASH, feedId, price, observedAt))
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer.key, digest);
        return abi.encodePacked(price, observedAt, r, s, v);
    }

    function _report(bytes32 domain, bytes32 feedId, Signer[] memory signers, int192[] memory prices, uint64 t)
        internal
        pure
        returns (bytes memory report)
    {
        for (uint256 i; i < signers.length; ++i) {
            report = bytes.concat(report, _entry(domain, feedId, signers[i], prices[i], t));
        }
    }

    function _same(uint256 n, int192 price) internal pure returns (int192[] memory p) {
        p = new int192[](n);
        for (uint256 i; i < n; ++i) {
            p[i] = price;
        }
    }

    function _take(Signer[] memory s, uint256 n) internal pure returns (Signer[] memory out) {
        out = new Signer[](n);
        for (uint256 i; i < n; ++i) {
            out[i] = s[i];
        }
    }
}

contract SignedSourceTest is ReportBuilder {
    bytes32 internal constant CRWD = bytes32("CRWD/USD");
    uint16 internal constant SPREAD_BPS = 50;
    uint16 internal constant JUMP_BPS = 1000;

    SolidityReportVerifier internal verifier;
    SignedSource internal src;
    Signer[] internal signers;
    address internal owner = makeAddr("timelock");
    bytes32 internal domain;

    function setUp() public {
        vm.warp(1_790_780_400);
        verifier = new SolidityReportVerifier();
        Signer[] memory s = _signers(3);
        address[] memory addrs = new address[](3);
        for (uint256 i; i < 3; ++i) {
            signers.push(s[i]);
            addrs[i] = s[i].addr;
        }
        src = new SignedSource(verifier, owner, addrs, 2, SPREAD_BPS, JUMP_BPS, 60);
        domain = src.domainSeparator();
    }

    function _all() internal view returns (Signer[] memory s) {
        s = new Signer[](signers.length);
        for (uint256 i; i < s.length; ++i) {
            s[i] = signers[i];
        }
    }

    function _submit(Signer[] memory s, int192[] memory prices, uint64 t) internal {
        src.submit(CRWD, _report(domain, CRWD, s, prices, t));
    }

    // ---------------------------------------------------------------- happy paths

    function test_quorumReport_storesMedian() public {
        int192[] memory p = new int192[](3);
        (p[0], p[1], p[2]) = (26_490_000_000, 26_498_000_000, 26_506_000_000);
        vm.expectEmit(address(src));
        emit SignedSource.PriceUpdated(CRWD, 26_498_000_000, uint64(block.timestamp), 3);
        _submit(_all(), p, uint64(block.timestamp));
        Observation memory o = src.observe(CRWD);
        assertEq(o.price, 26_498_000_000);
        assertEq(o.decimals, 8);
        assertEq(o.observedAt, block.timestamp);
        assertEq(uint8(src.kind(CRWD)), uint8(PriceKind.RAW_UNDERLYING));
    }

    function test_evenSignerCount_medianIsTheMean() public {
        int192[] memory p = new int192[](2);
        (p[0], p[1]) = (10_000_000_000, 10_002_000_000);
        _submit(_take(_all(), 2), p, uint64(block.timestamp));
        assertEq(src.observe(CRWD).price, 10_001_000_000);
    }

    function test_anyoneCanRelay() public {
        bytes memory report = _report(domain, CRWD, _all(), _same(3, 100e8), uint64(block.timestamp));
        vm.prank(makeAddr("stranger"));
        src.submit(CRWD, report);
        assertEq(src.observe(CRWD).price, 100e8);
    }

    // ---------------------------------------------------------------- rejections

    function test_rejects_belowQuorum() public {
        vm.expectRevert(abi.encodeWithSelector(SignedSource.QuorumNotMet.selector, 1, 2));
        _submit(_take(_all(), 1), _same(1, 100e8), uint64(block.timestamp));
    }

    function test_rejects_unknownSigner() public {
        Signer[] memory s = _signers(4); // signer3 is not in the set
        Signer[] memory pick = new Signer[](3);
        uint256 k;
        for (uint256 i; i < 4 && k < 3; ++i) {
            if (!src.isSigner(s[i].addr) || k < 2) pick[k++] = s[i];
        }
        bytes memory report = _report(domain, CRWD, pick, _same(3, 100e8), uint64(block.timestamp));
        vm.expectPartialRevert(SignedSource.UnknownSigner.selector);
        src.submit(CRWD, report);
    }

    function test_rejects_duplicateSigner() public {
        Signer[] memory s = new Signer[](2);
        (s[0], s[1]) = (signers[0], signers[0]);
        bytes memory report = _report(domain, CRWD, s, _same(2, 100e8), uint64(block.timestamp));
        vm.expectRevert(abi.encodeWithSelector(SolidityReportVerifier.SignersNotAscending.selector, 1));
        src.submit(CRWD, report);
    }

    /// Single-entry reports, so the membership check is what rejects them.
    function test_rejects_signaturesForAnotherFeed() public {
        bytes memory report = _entry(domain, bytes32("AAPL/USD"), signers[0], 100e8, uint64(block.timestamp));
        vm.expectPartialRevert(SignedSource.UnknownSigner.selector);
        src.submit(CRWD, report);
    }

    function test_rejects_signaturesForAnotherDeployment() public {
        bytes memory report =
            _entry(keccak256("other chain or contract"), CRWD, signers[0], 100e8, uint64(block.timestamp));
        vm.expectPartialRevert(SignedSource.UnknownSigner.selector);
        src.submit(CRWD, report);
    }

    function test_rejects_malleableHighS() public {
        bytes memory e = _entry(domain, CRWD, signers[0], 100e8, uint64(block.timestamp));
        bytes32 s;
        assembly {
            s := mload(add(e, 96)) // entry offset 64
        }
        bytes32 highS = bytes32(SECP256K1_N - uint256(s));
        uint8 flippedV = uint8(e[96]) == 27 ? 28 : 27;
        for (uint256 i; i < 32; ++i) {
            e[64 + i] = highS[i];
        }
        e[96] = bytes1(flippedV);
        vm.expectRevert(abi.encodeWithSelector(SolidityReportVerifier.InvalidSignature.selector, 0));
        src.submit(CRWD, e);
    }

    function test_rejects_malformedAndEmptyReports() public {
        vm.expectRevert(SolidityReportVerifier.EmptyReport.selector);
        src.submit(CRWD, "");
        vm.expectRevert(abi.encodeWithSelector(SolidityReportVerifier.MalformedReport.selector, 96));
        src.submit(CRWD, new bytes(96));
    }

    function test_rejects_wideSpread() public {
        int192[] memory p = new int192[](3);
        (p[0], p[1], p[2]) = (99e8, 100e8, 101e8);
        vm.expectRevert(abi.encodeWithSelector(SignedSource.SpreadTooWide.selector, 200));
        _submit(_all(), p, uint64(block.timestamp));
    }

    function test_rejects_nonPositive() public {
        vm.expectRevert(SignedSource.NonPositivePrice.selector);
        _submit(_all(), _same(3, 0), uint64(block.timestamp));
    }

    function test_rejects_futureObservation() public {
        uint64 t = uint64(block.timestamp + 61);
        vm.expectRevert(abi.encodeWithSelector(SignedSource.FutureObservation.selector, t));
        _submit(_all(), _same(3, 100e8), t);
    }

    function test_rejects_notNewer() public {
        uint64 t = uint64(block.timestamp);
        _submit(_all(), _same(3, 100e8), t);
        vm.expectRevert(abi.encodeWithSelector(SignedSource.StaleReport.selector, t, t));
        _submit(_all(), _same(3, 100e8), t);
    }

    /// A large move needs every signer: a quorum alone cannot move the price far.
    function test_largeJump_needsUnanimity() public {
        _submit(_all(), _same(3, 1000e8), uint64(block.timestamp));
        vm.warp(block.timestamp + 1);
        vm.expectRevert(abi.encodeWithSelector(SignedSource.QuorumNotMet.selector, 2, 3));
        _submit(_take(_all(), 2), _same(2, 250e8), uint64(block.timestamp));
        _submit(_all(), _same(3, 250e8), uint64(block.timestamp));
        assertEq(src.observe(CRWD).price, 250e8);
    }

    // ---------------------------------------------------------------- signer set

    function test_setSigners_onlyOwner() public {
        address[] memory s = new address[](1);
        s[0] = address(1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        src.setSigners(s, 1);
        vm.prank(owner);
        src.setSigners(s, 1);
        assertTrue(src.isSigner(address(1)));
        assertFalse(src.isSigner(signers[0].addr));
        assertEq(src.quorum(), 1);
    }

    function test_setSigners_rejectsMinorityQuorumDuplicatesAndZero() public {
        address[] memory s = new address[](4);
        (s[0], s[1], s[2], s[3]) = (address(1), address(2), address(3), address(4));
        vm.startPrank(owner);
        vm.expectRevert(SignedSource.InvalidSignerSet.selector);
        src.setSigners(s, 2); // 2 of 4 is not a majority
        s[3] = address(3);
        vm.expectRevert(SignedSource.InvalidSignerSet.selector);
        src.setSigners(s, 3);
        s[3] = address(0);
        vm.expectRevert(SignedSource.InvalidSignerSet.selector);
        src.setSigners(s, 3);
        vm.stopPrank();
    }

    // ---------------------------------------------------------------- verifier

    function testFuzz_verifierMedianMatchesReference(uint256 seed, uint8 count) public {
        uint256 n = bound(count, 1, 7);
        Signer[] memory s = _signers(n);
        int192[] memory p = new int192[](n);
        for (uint256 i; i < n; ++i) {
            p[i] = int192(int256(bound(uint256(keccak256(abi.encode(seed, i))), 1, 1e15)));
        }
        bytes32 otherDomain = keccak256("domain");
        (address[] memory signers_, int256 median, int256 min, int256 max,,) =
            verifier.verify(otherDomain, CRWD, _report(otherDomain, CRWD, s, p, 42));

        int192[] memory sorted = _sorted(p);
        int256 expected = n % 2 == 1 ? int256(sorted[n / 2]) : (int256(sorted[n / 2 - 1]) + int256(sorted[n / 2])) >> 1;
        assertEq(median, expected);
        assertEq(min, sorted[0]);
        assertEq(max, sorted[n - 1]);
        assertEq(signers_.length, n);
        for (uint256 i; i < n; ++i) {
            assertEq(signers_[i], s[i].addr);
        }
    }

    function _sorted(int192[] memory a) private pure returns (int192[] memory b) {
        b = new int192[](a.length);
        for (uint256 i; i < a.length; ++i) {
            b[i] = a[i];
        }
        for (uint256 i; i < b.length; ++i) {
            for (uint256 j = i + 1; j < b.length; ++j) {
                if (b[j] < b[i]) (b[i], b[j]) = (b[j], b[i]);
            }
        }
    }

    // ---------------------------------------------------------------- end to end

    function test_endToEnd_signedCrwdPriceThroughSlateFeed() public {
        MockStockToken crwd = new MockStockToken("CrowdStrike", "CRWD");
        USMarketCalendar calendar = new USMarketCalendar(address(this));
        crwd.updateMultiplier(4e18);
        SlateFeed feed = new SlateFeed(
            SlateFeed.Config({
                token: address(crwd),
                model: MultiplierModel.ERC8056,
                source: src,
                feedId: CRWD,
                maxAge: 15 minutes,
                corporateActionGrace: 30 minutes,
                largeChangeBps: 500,
                allowMarketClosed: false,
                calendar: calendar,
                session: Session.EXTENDED,
                description: "CRWD / USD"
            })
        );
        vm.warp(block.timestamp + 31 minutes);
        _submit(_all(), _same(3, 26_498_000_000), uint64(block.timestamp));
        Quote memory q = feed.latestQuote();
        assertEq(uint8(q.status), uint8(FeedStatus.OK));
        assertEq(q.answer, 105_992_000_000);
    }
}
