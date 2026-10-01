---
title: Market calendar
description: NYSE holidays, early closes and New York daylight saving, on-chain.
---

A stock-token price that stops updating on Saturday is not stale; one that stops on Tuesday afternoon is. SlateFeed tells them apart with `USMarketCalendar`, an on-chain calendar of US trading sessions.

## What it knows

- **Holidays and early closes** from NYSE's published calendar, loaded for **2026 through 2028**. That is 29 holidays, including Good Friday, Juneteenth, observed holidays such as Independence Day on Friday 3 July 2026, and 2028's missing New Year holiday. It also has 5 early closes (13:00): the day after Thanksgiving each year, Christmas Eve 2026, and 3 July 2028.
- **New York daylight saving** for any year, from the rule in force since 2007: 02:00 local on the second Sunday of March to 02:00 local on the first Sunday of November.
- **Two sessions:**
  - `REGULAR`: 09:30 to 16:00 New York time (13:00 on early-close days), for feeds that only update in the core session, such as Chainlink's raw equity feeds on Arbitrum One.
  - `EXTENDED`: Robinhood's 24/5 session, from 20:00 New York time the previous evening to 20:00 on the trading day (17:00 on early-close days). The Robinhood feeds and Slate's signed prices use this one.

`closedSince(timestamp, session)` returns 0 while a session is open; otherwise it returns when the session closed. SlateFeed reports `MARKET_CLOSED` only if the last price was fresh at that moment. A feed that died on Wednesday reads `STALE` all weekend, not `MARKET_CLOSED`.

## Governance

The owner (a timelock in deployment) can add later years and extend coverage. It can never change a day that has already started. Beyond the covered range, every weekday counts as a trading day, so an unlisted holiday reads as stale rather than closed: the calendar fails closed.

## Credit

Our first version only knew weekends. [Strike](https://github.com/Prashant-thakur77/Strike)'s market calendar was better than our first version, and we adopted the approach: an explicit holiday table with early closes, rather than weekday arithmetic. See [Prior art](/prior-art).
