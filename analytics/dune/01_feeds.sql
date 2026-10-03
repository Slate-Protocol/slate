-- Slate feeds on Robinhood Chain mainnet: every feed SlateFeedFactory deployed, with its last signed price.
-- Prices land as SignedSource PriceUpdated(bytes32 indexed feedId, int192 price, uint64 observedAt, uint256 signerCount).
-- The share price has 8 decimals; a feed's token price is that times the token's uiMultiplier at observedAt.
WITH feeds AS (
  SELECT
    varbinary_substring(topic1, 13, 20) AS feed,
    varbinary_substring(topic2, 13, 20) AS token,
    topic3 AS feed_id,
    block_time AS deployed_at
  FROM robinhood.logs
  WHERE contract_address = 0xd921ad145fa22b0c8a4846d234857fbeffdfddc6 -- SlateFeedFactory
    AND topic0 = 0xfae978986ebc8aed91412076e3f81055021ce753c1d2a58ff6c2a9fe09006461 -- FeedDeployed
), prices AS (
  SELECT
    topic1 AS feed_id,
    block_time,
    tx_hash,
    CAST(varbinary_to_int256(varbinary_substring(data, 1, 32)) AS double) / 1e8 AS share_price,
    from_unixtime(CAST(varbinary_to_uint256(varbinary_substring(data, 33, 32)) AS double)) AS observed_at,
    CAST(varbinary_to_uint256(varbinary_substring(data, 65, 32)) AS integer) AS signers,
    ROW_NUMBER() OVER (PARTITION BY topic1 ORDER BY block_number DESC, index DESC) AS rn,
    COUNT(*) OVER (PARTITION BY topic1) AS updates
  FROM robinhood.logs
  WHERE contract_address = 0xf0b57272f1d69083019e8953b82bc128002d7526 -- SignedSource
    AND topic0 = 0xb5fc72f467368c804d4f2afb5affda0daaf438dd46342717543379e55d4a3edc -- PriceUpdated
)
SELECT
  replace(from_utf8(f.feed_id), chr(0), '') AS feed_id,
  CASE WHEN p.feed_id IS NULL THEN 'Chainlink total return' ELSE 'Signed, 2 of 3' END AS source,
  p.share_price AS last_share_price_usd,
  p.observed_at AS last_observed_at,
  date_diff('minute', p.observed_at, now()) AS minutes_since_observed,
  p.updates,
  p.signers AS signers_on_last,
  f.feed,
  f.token,
  f.deployed_at,
  p.tx_hash AS last_tx
FROM feeds f
LEFT JOIN prices p ON p.feed_id = f.feed_id AND p.rn = 1
ORDER BY p.observed_at DESC NULLS LAST
