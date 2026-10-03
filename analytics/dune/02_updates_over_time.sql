-- Signed price updates per hour on Robinhood Chain mainnet, by feed.
SELECT
  date_trunc('hour', block_time) AS hour,
  replace(from_utf8(topic1), chr(0), '') AS feed_id,
  COUNT(*) AS updates
FROM robinhood.logs
WHERE contract_address = 0xf0b57272f1d69083019e8953b82bc128002d7526 -- SignedSource
  AND topic0 = 0xb5fc72f467368c804d4f2afb5affda0daaf438dd46342717543379e55d4a3edc -- PriceUpdated
GROUP BY 1, 2
ORDER BY 1, 2
