//! SlateVerifier: verifies K-of-N signed price reports for the Slate pricing layer.
//!
//! Skeleton only. The report format, signature checks and median logic land in block B2.

#![cfg_attr(not(any(test, feature = "export-abi")), no_main)]
extern crate alloc;

use stylus_sdk::{alloy_primitives::U256, prelude::*};

/// Report format version this verifier understands.
const REPORT_VERSION: u64 = 1;

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
}

#[cfg(test)]
mod test {
    use super::*;
    use stylus_sdk::testing::*;

    #[test]
    fn reports_version() {
        let vm = TestVM::default();
        let verifier = SlateVerifier::from(&vm);
        assert_eq!(verifier.report_version(), U256::from(REPORT_VERSION));
    }
}
