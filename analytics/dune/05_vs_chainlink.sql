-- Slate against Chainlink for the 35 tokens Chainlink prices on Robinhood Chain mainnet, from the accuracy board's
-- snapshot at Friday's close (uploaded as slate_accuracy_snapshot.csv). Slate's prices for these tokens are signed
-- reports verified in the browser, never submitted on-chain, so they are not in robinhood.logs.
-- gap_then compares Chainlink's answer with Slate's report signed within 90 s of Chainlink's last update.
SELECT
  token,
  slate_usd,
  chainlink_usd,
  gap_now_pct,
  gap_then_pct,
  chainlink_threshold_pct,
  chainlink_updated_utc,
  snapshot_utc
FROM dune.{{namespace}}.dataset_slate_accuracy_snapshot
ORDER BY abs(gap_now_pct) DESC
