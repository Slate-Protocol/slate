-- The publisher's relayer: every transaction it sent to SignedSource, and the gas it spent.
-- Anyone may relay a signed report; this is Slate's own relayer. Robinhood Chain charges no L1 component today.
SELECT
  date_trunc('hour', block_time) AS hour,
  COUNT(*) AS txs,
  SUM(CASE WHEN success THEN 1 ELSE 0 END) AS succeeded,
  SUM(CAST(gas_used AS double) * CAST(gas_price AS double)) / 1e18 AS eth_spent,
  SUM(SUM(CAST(gas_used AS double) * CAST(gas_price AS double)) / 1e18) OVER (ORDER BY date_trunc('hour', block_time)) AS eth_spent_cumulative,
  AVG(CAST(gas_used AS double)) AS avg_gas
FROM robinhood.transactions
WHERE "from" = 0x0acfe7b486d2a2181b4cede90a41ddd15c80168f -- Slate's relayer
  AND "to" = 0xf0b57272f1d69083019e8953b82bc128002d7526 -- SignedSource
GROUP BY 1
ORDER BY 1
