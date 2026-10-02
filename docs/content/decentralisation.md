---
title: The path to independent signers
description: Who controls what in Slate today, exactly what changes when the signer set is handed over, and the runbook for adding an independent signer.
---

Slate's only off-chain input is a share price, signed by a committee. Today every key on that committee is Slate's. This page states what that means, what is already out of Slate's hands, and how the committee passes to independent signers, step by step. The dashboard's [Who signs the prices](https://app.slate.0xo.in/#signers) panel shows the current state, read from the chain.

## Today

| | Who | Can do |
|---|---|---|
| Signer set of `SignedSource` | Three keys, all Slate's, 2 of 3 required | Sign share prices |
| Owner of `SignedSource` | `TimelockController`, 48-hour delay | Replace the signer set and quorum. Nothing else |
| Proposer, executor and canceller of the timelock | Slate's deployer | Schedule, run or cancel timelock operations |
| Admin of the timelock | The timelock itself | Role changes go through the same 48-hour delay |
| Owner of `USMarketCalendar` | Slate's deployer, moving under the timelock: executable Sun 4 Oct, 20:05 IST on testnet and Mon 5 Oct, 00:40 IST on mainnet | Mark future days as holidays or early closes. Days already started in New York cannot be changed |
| `SlateFeed`, `SlateBasket`, `SlateNavFeed`, `SlateRouter` | No owner | Nothing: every parameter is set at deployment |

Fixed for good in `SignedSource`, whoever owns it: signers must agree within 0.5%; a move over 10% needs every signer; a report must be newer than the last and at most 60 seconds in the future; a quorum must be a strict majority of the set.

## What a handover changes

- **Who can move a price.** Once independent signers hold enough keys that Slate's own fall below the quorum, Slate alone can no longer move any price. Each signer fetches and signs its own observation; `SignedSource` takes the median.
- **Who can stop a large move.** Any single signer can withhold a signature from a move over 10%, so an independent signer gets a veto on large moves. The trade-off: a large move also waits for every signer to be online.
- **Who can change the set next.** After the timelock's proposer role passes to a multisig that includes the independent signers, Slate cannot schedule a signer change alone. Every change still waits 48 hours in public.

## What it does not change

- **The feeds.** No feed, basket, router or lending contract is redeployed or reconfigured; they read `SignedSource` and the token's own multiplier as before.
- **The multiplier.** It always comes from the token's own contract. No signer touches it.
- **The bounds above.** They are immutable.
- **The data source.** Signers that read Robinhood's quotes, as Slate's do, share that source. Independence of keys is not independence of data: a signer may also check other sources before signing, and should.
- **Relaying.** Anyone can relay a signed report; the relayer has no power over its content.

## Runbook: adding an independent signer

Rehearsed against the live testnet contracts by `test/fork/Governance.t.sol`, and end to end on a fork with the real co-signer. There, after a rotation to four signers with quorum 3, two of Slate's keys alone were refused (`QuorumNotMet`), and the same report with the operator's own signed observation was accepted.

**1. The operator runs a co-signer** with their own key, choosing which `SignedSource` contracts they sign for:

```bash
cd publisher
COSIGNER_KEY=0x… COSIGNER_ALLOW="46630:0x8B27311a3493a85E063f97e4bB59cf3a22aEA507" PORT=8090 node src/cosigner.ts
```

It never signs a price it is handed. On each request it fetches its own Robinhood quote, applies the publisher's checks (age, spread, halts) and signs its own observation.

**2. Slate's publisher asks it for an entry** with every report: set `COSIGNER_URLS=https://<operator>/` on the publisher. Entries that fail verification, or stray more than 0.4% or 60 seconds from the publisher's own quote, are dropped and logged.

**3. The timelock adds the signer.** Propose the new set (Slate's three keys and the operator's, quorum 3), then execute after 48 hours:

```bash
cd contracts
NEW_SIGNERS=0x33A2…,0x3d6c…,0xfEbA…,0x<operator> NEW_QUORUM=3 \
  forge script script/Deploy.s.sol --sig "proposeSigners()" --rpc-url rh_testnet --private-key $DEPLOYER_PRIVATE_KEY --broadcast
# 48 hours later, with the same environment:
forge script script/Deploy.s.sol --sig "executeSigners()" --rpc-url rh_testnet --private-key $DEPLOYER_PRIVATE_KEY --broadcast
```

The pending operation appears on the dashboard, with its countdown, as soon as it is scheduled.

**4. Repeat** until Slate's keys alone are below the quorum, then hand the timelock's proposer, executor and canceller roles to a multisig that includes the independent signers. That role change is itself a timelock operation.

## Mainnet

Mainnet has the same structure: `SignedSource` has been owned by its 48-hour timelock since the block it was deployed in. Right after deployment, `handOverCalendar()` began moving the mainnet market calendar under the same timelock; the timelock's acceptance is executable on Mon 5 Oct at 00:40 IST. The dashboard's panel shows both networks.
