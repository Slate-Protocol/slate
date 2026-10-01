//! SlateVerifier: verifies K-of-N signed price reports for the Slate pricing layer.
//!
//! Implements the same ABI and semantics as `SolidityReportVerifier` (`contracts/src/interfaces/IReportVerifier.sol`):
//!
//! - a report is `n` entries of 97 bytes: `int192 price | uint64 observedAt | r | s | v`;
//! - each entry is an EIP-712 signature over `Observation(bytes32 feedId,int192 price,uint64 observedAt)`
//!   under the caller's domain separator;
//! - signatures must be low-s with `v` of 27 or 28, and recovered signers strictly ascending;
//! - the result is the signers, the median, minimum and maximum price (median of an even count is the floor of
//!   the mean of the middle two), the median observation time (upper middle) and the latest one.

#![cfg_attr(not(any(test, feature = "export-abi")), no_main)]
extern crate alloc;

use alloc::vec::Vec;
use alloy_primitives::{Address, B256, Bytes, I256, U256, address, b256};
use alloy_sol_types::sol;
use stylus_sdk::{call::static_call, crypto::keccak, prelude::*, stylus_core::calls::Call};

/// Report format version this verifier understands.
const REPORT_VERSION: u64 = 1;
/// Bytes per report entry.
const ENTRY: usize = 97;
/// The ecrecover precompile.
const ECRECOVER: Address = address!("0000000000000000000000000000000000000001");
/// keccak256("Observation(bytes32 feedId,int192 price,uint64 observedAt)")
const OBSERVATION_TYPEHASH: B256 =
    b256!("7a1f1abe511c865142ec6d34e96ae59e6b0173c542061c40ac6b1fbc0c0e3297");
/// secp256k1 group order / 2: the largest `s` accepted, as OpenZeppelin's ECDSA does.
const MAX_S: B256 = b256!("7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a0");

sol! {
    error EmptyReport();
    error MalformedReport(uint256 length);
    error InvalidSignature(uint256 index);
    error SignersNotAscending(uint256 index);
}

#[derive(SolidityError)]
pub enum VerifierError {
    EmptyReport(EmptyReport),
    MalformedReport(MalformedReport),
    InvalidSignature(InvalidSignature),
    SignersNotAscending(SignersNotAscending),
}

/// `(signers, medianPrice, minPrice, maxPrice, medianObservedAt, maxObservedAt)`
pub type Summary = (Vec<Address>, I256, I256, I256, u64, u64);

sol_storage! {
    #[entrypoint]
    pub struct SlateVerifier {}
}

#[public]
impl SlateVerifier {
    /// Returns the report format version this verifier understands.
    pub fn report_version(&self) -> U256 {
        U256::from(REPORT_VERSION)
    }

    /// Verifies `report` for `feed_id` under `domain_separator` and summarises it.
    pub fn verify(
        &self,
        domain_separator: B256,
        feed_id: B256,
        report: Bytes,
    ) -> Result<Summary, VerifierError> {
        verify_with(domain_separator, feed_id, &report, |input| {
            let output = static_call(self.vm(), Call::new(), ECRECOVER, input).ok()?;
            (output.len() == 32).then(|| Address::from_slice(&output[12..32]))
        })
    }
}

/// The verification logic, with signature recovery supplied by the caller (the ecrecover precompile on-chain).
fn verify_with<F>(
    domain_separator: B256,
    feed_id: B256,
    report: &[u8],
    mut recover: F,
) -> Result<Summary, VerifierError>
where
    F: FnMut(&[u8; 128]) -> Option<Address>,
{
    if report.is_empty() {
        return Err(VerifierError::EmptyReport(EmptyReport {}));
    }
    if !report.len().is_multiple_of(ENTRY) {
        return Err(VerifierError::MalformedReport(MalformedReport {
            length: U256::from(report.len()),
        }));
    }
    let n = report.len() / ENTRY;

    let mut signers = Vec::with_capacity(n);
    let mut prices = Vec::with_capacity(n);
    let mut times = Vec::with_capacity(n);
    let mut previous = Address::ZERO;

    for (i, entry) in report.chunks_exact(ENTRY).enumerate() {
        let (price_word, observed_at) = decode_values(entry);
        let digest = typed_data_hash(
            domain_separator,
            struct_hash(feed_id, &price_word, observed_at),
        );
        let input = ecrecover_input(&digest, entry).ok_or_else(|| invalid(i))?;
        let signer = recover(&input)
            .filter(|signer| *signer != Address::ZERO)
            .ok_or_else(|| invalid(i))?;
        if signer <= previous {
            return Err(VerifierError::SignersNotAscending(SignersNotAscending {
                index: U256::from(i),
            }));
        }
        previous = signer;

        signers.push(signer);
        prices.push(I256::from_be_bytes(price_word));
        times.push(observed_at);
    }

    let (median, min, max, median_time, max_time) = summarise(&mut prices, &mut times);
    Ok((signers, median, min, max, median_time, max_time))
}

fn invalid(index: usize) -> VerifierError {
    VerifierError::InvalidSignature(InvalidSignature {
        index: U256::from(index),
    })
}

/// The entry's price, sign-extended to a 32-byte word, and its observation time.
fn decode_values(entry: &[u8]) -> ([u8; 32], u64) {
    let mut word = [0u8; 32];
    if entry[0] & 0x80 != 0 {
        word[..8].fill(0xff);
    }
    word[8..].copy_from_slice(&entry[0..24]);
    let mut time = [0u8; 8];
    time.copy_from_slice(&entry[24..32]);
    (word, u64::from_be_bytes(time))
}

/// `keccak256(abi.encode(OBSERVATION_TYPEHASH, feedId, price, observedAt))`
fn struct_hash(feed_id: B256, price_word: &[u8; 32], observed_at: u64) -> B256 {
    let mut buf = [0u8; 128];
    buf[0..32].copy_from_slice(OBSERVATION_TYPEHASH.as_slice());
    buf[32..64].copy_from_slice(feed_id.as_slice());
    buf[64..96].copy_from_slice(price_word);
    buf[120..128].copy_from_slice(&observed_at.to_be_bytes());
    keccak(buf)
}

/// `keccak256("\x19\x01" ‖ domainSeparator ‖ structHash)`
fn typed_data_hash(domain_separator: B256, struct_hash: B256) -> B256 {
    let mut buf = [0u8; 66];
    buf[0] = 0x19;
    buf[1] = 0x01;
    buf[2..34].copy_from_slice(domain_separator.as_slice());
    buf[34..66].copy_from_slice(struct_hash.as_slice());
    keccak(buf)
}

/// The ecrecover precompile input `digest ‖ v ‖ r ‖ s`, or `None` for a high-s or out-of-range-v signature.
fn ecrecover_input(digest: &B256, entry: &[u8]) -> Option<[u8; 128]> {
    let v = entry[96];
    if v != 27 && v != 28 {
        return None;
    }
    if entry[64..96] > *MAX_S.as_slice() {
        return None;
    }
    let mut input = [0u8; 128];
    input[0..32].copy_from_slice(digest.as_slice());
    input[63] = v;
    input[64..128].copy_from_slice(&entry[32..96]);
    Some(input)
}

/// Sorts both lists and returns `(median, min, max, medianTime, maxTime)`.
fn summarise(prices: &mut [I256], times: &mut [u64]) -> (I256, I256, I256, u64, u64) {
    prices.sort_unstable();
    times.sort_unstable();
    let n = prices.len();
    let median = if n % 2 == 1 {
        prices[n / 2]
    } else {
        // Arithmetic shift: the floor of the mean, as Solidity's `>> 1` on int256. Cannot overflow for int192 inputs.
        (prices[n / 2 - 1] + prices[n / 2]).asr(1)
    };
    (median, prices[0], prices[n - 1], times[n / 2], times[n - 1])
}

#[cfg(test)]
mod test {
    use super::*;
    use stylus_sdk::testing::*;

    fn entry(price: i128, observed_at: u64, v: u8, s: [u8; 32]) -> Vec<u8> {
        let mut e = Vec::with_capacity(ENTRY);
        let word = I256::try_from(price).unwrap().to_be_bytes::<32>();
        e.extend_from_slice(&word[8..32]);
        e.extend_from_slice(&observed_at.to_be_bytes());
        e.extend_from_slice(&[0x11; 32]);
        e.extend_from_slice(&s);
        e.push(v);
        e
    }

    /// Maps each entry's precompile input to the signer it should recover to.
    fn recoverer(
        domain: B256,
        feed: B256,
        entries: &[(Vec<u8>, Address)],
    ) -> impl FnMut(&[u8; 128]) -> Option<Address> {
        let map: std::collections::HashMap<[u8; 128], Address> = entries
            .iter()
            .map(|(e, signer)| {
                let (word, t) = decode_values(e);
                let digest = typed_data_hash(domain, struct_hash(feed, &word, t));
                (ecrecover_input(&digest, e).unwrap(), *signer)
            })
            .collect();
        move |input| map.get(input).copied()
    }

    fn addr(b: u8) -> Address {
        Address::repeat_byte(b)
    }

    #[test]
    fn reports_version() {
        let vm = TestVM::default();
        let verifier = SlateVerifier::from(&vm);
        assert_eq!(verifier.report_version(), U256::from(REPORT_VERSION));
    }

    #[test]
    fn decodes_negative_prices_with_sign_extension() {
        let e = entry(-5, 7, 27, [0x01; 32]);
        let (word, t) = decode_values(&e);
        assert_eq!(I256::from_be_bytes(word), I256::try_from(-5i64).unwrap());
        assert_eq!(t, 7);
    }

    #[test]
    fn struct_hash_matches_abi_encode() {
        // abi.encode(TYPEHASH, feedId, int192(-1), uint64(1)) hashed, computed independently with cast.
        let word = I256::MINUS_ONE.to_be_bytes::<32>();
        let h = struct_hash(B256::repeat_byte(0xaa), &word, 1);
        let mut expected = Vec::new();
        expected.extend_from_slice(OBSERVATION_TYPEHASH.as_slice());
        expected.extend_from_slice(&[0xaa; 32]);
        expected.extend_from_slice(&[0xff; 32]);
        let mut one = [0u8; 32];
        one[31] = 1;
        expected.extend_from_slice(&one);
        assert_eq!(h, keccak(expected));
    }

    #[test]
    fn rejects_empty_and_malformed() {
        let vm = TestVM::default();
        let v = SlateVerifier::from(&vm);
        assert!(matches!(
            v.verify(B256::ZERO, B256::ZERO, Bytes::new()),
            Err(VerifierError::EmptyReport(_))
        ));
        assert!(matches!(
            v.verify(B256::ZERO, B256::ZERO, Bytes::from(vec![0u8; 96])),
            Err(VerifierError::MalformedReport(_))
        ));
    }

    #[test]
    fn rejects_high_s_and_bad_v() {
        let vm = TestVM::default();
        let v = SlateVerifier::from(&vm);
        let high_s = entry(1, 1, 27, [0xff; 32]);
        assert!(matches!(
            v.verify(B256::ZERO, B256::ZERO, high_s.into()),
            Err(VerifierError::InvalidSignature(_))
        ));
        let bad_v = entry(1, 1, 29, [0x01; 32]);
        assert!(matches!(
            v.verify(B256::ZERO, B256::ZERO, bad_v.into()),
            Err(VerifierError::InvalidSignature(_))
        ));
    }

    #[test]
    fn summarises_three_signers() {
        let (domain, feed) = (B256::repeat_byte(1), B256::repeat_byte(2));
        let es = vec![
            (entry(26_506, 30, 27, [0x01; 32]), addr(0x10)),
            (entry(26_490, 10, 28, [0x02; 32]), addr(0x11)),
            (entry(26_498, 20, 27, [0x03; 32]), addr(0x12)),
        ];
        let report: Vec<u8> = es.iter().flat_map(|(e, _)| e.clone()).collect();
        let (signers, median, min, max, t_med, t_max) =
            verify_with(domain, feed, &report, recoverer(domain, feed, &es))
                .ok()
                .unwrap();
        assert_eq!(signers, vec![addr(0x10), addr(0x11), addr(0x12)]);
        assert_eq!(median, I256::try_from(26_498_i64).unwrap());
        assert_eq!(min, I256::try_from(26_490_i64).unwrap());
        assert_eq!(max, I256::try_from(26_506_i64).unwrap());
        assert_eq!((t_med, t_max), (20, 30));
    }

    #[test]
    fn rejects_an_unrecoverable_signature() {
        let (domain, feed) = (B256::repeat_byte(1), B256::repeat_byte(2));
        let es = vec![(entry(1, 1, 27, [0x01; 32]), addr(0x10))];
        let report = es[0].0.clone();
        let other_feed = B256::repeat_byte(3); // signed for another feed: recovers to nothing known
        assert!(matches!(
            verify_with(domain, other_feed, &report, recoverer(domain, feed, &es)),
            Err(VerifierError::InvalidSignature(_))
        ));
    }

    #[test]
    fn even_count_median_is_floor_of_mean() {
        let mut p = [
            I256::try_from(-3i64).unwrap(),
            I256::try_from(0i64).unwrap(),
        ];
        let mut t = [1u64, 2];
        assert_eq!(summarise(&mut p, &mut t).0, I256::try_from(-2i64).unwrap());
    }

    #[test]
    fn rejects_unordered_and_duplicate_signers() {
        let (domain, feed) = (B256::repeat_byte(1), B256::repeat_byte(2));
        let unordered = vec![
            (entry(1, 1, 27, [0x01; 32]), addr(0x20)),
            (entry(1, 1, 27, [0x02; 32]), addr(0x10)),
        ];
        let report: Vec<u8> = unordered.iter().flat_map(|(e, _)| e.clone()).collect();
        assert!(matches!(
            verify_with(domain, feed, &report, recoverer(domain, feed, &unordered)),
            Err(VerifierError::SignersNotAscending(_))
        ));
        let duplicate = vec![
            (entry(1, 1, 27, [0x01; 32]), addr(0x10)),
            (entry(1, 1, 27, [0x02; 32]), addr(0x10)),
        ];
        let report: Vec<u8> = duplicate.iter().flat_map(|(e, _)| e.clone()).collect();
        assert!(matches!(
            verify_with(domain, feed, &report, recoverer(domain, feed, &duplicate)),
            Err(VerifierError::SignersNotAscending(_))
        ));
    }
}
