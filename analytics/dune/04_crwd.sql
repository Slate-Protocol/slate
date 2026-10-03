-- CRWD, the token Chainlink does not price: every signed share price, and the token price at the 4.000 multiplier
-- in force since 2 Jul 2026 13:30 UTC (CRWD's uiMultiplier() and effectiveAt(), read on-chain).
SELECT
  from_unixtime(CAST(varbinary_to_uint256(varbinary_substring(data, 33, 32)) AS double)) AS observed_at,
  CAST(varbinary_to_int256(varbinary_substring(data, 1, 32)) AS double) / 1e8 AS share_price_usd,
  CAST(varbinary_to_int256(varbinary_substring(data, 1, 32)) AS double) / 1e8 * 4 AS token_price_usd,
  block_time,
  tx_hash
FROM robinhood.logs
WHERE contract_address = 0xf0b57272f1d69083019e8953b82bc128002d7526 -- SignedSource
  AND topic0 = 0xb5fc72f467368c804d4f2afb5affda0daaf438dd46342717543379e55d4a3edc -- PriceUpdated
  AND topic1 = 0x435257442f555344000000000000000000000000000000000000000000000000 -- "CRWD/USD"
ORDER BY observed_at
