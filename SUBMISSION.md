# DeepSurge 2026 — Project Submission

## Project name
Adaptive Funding Engine

## One-line description
A Sui-native milestone funding protocol that pays out scholarships and grants adaptively — rewarding on-time delivery, penalizing delays, and automatically recycling unclaimed funds to the next recipient in a waitlist.

---

## The problem

Scholarship and grant disbursement is broken in three ways:

1. **All-or-nothing**: recipients get full payment regardless of whether they deliver, or nothing if they miss a single deadline
2. **No accountability**: funders have no on-chain visibility into milestone completion
3. **Dead capital**: when a recipient fails, funds sit idle instead of flowing to the next person who needs them

---

## The solution

The Adaptive Funding Engine turns every grant into a series of on-chain milestones with built-in accountability loops:

- Milestones unlock sequentially — the next one only opens after the previous is approved
- Recipients submit cryptographic proof of work (URL + hash) per milestone
- A quorum of credentialed reviewers votes to approve, warn, or reject
- Payout is computed adaptively: early submissions earn a bonus, late submissions lose a percentage per day via an on-chain decay formula
- Withheld funds recycle automatically back to the shared pool for the next person in the waitlist
- Completing all milestones mints a soulbound on-chain credential the recipient owns forever

---

## How it works (technical)

### Smart contracts — 5 Move modules, 1,291 lines, 27 unit tests

**`program.move`** — Access control. The `ManagerCap` is a capability object that authorizes all administrative actions. Managers issue `ReviewerCap` objects to trusted reviewers — no centralized role registry, just object ownership.

**`pool.move`** — A shared `FundingPool<T>` object holds all escrowed SUI. Managers deposit, yield accrues against a configurable APY (stored in basis points), and funds are drawn into individual agreement escrows at creation time.

**`agreement.move`** — The core protocol. Each `FundingAgreement<T>` holds:
- An ordered vector of `Milestone` objects, each with amount, deadline, state machine, and submission metadata
- A `StreamConfig` per milestone describing the vesting curve (linear, stepped, or quadratic-accelerating), cliff, and duration
- A quorum threshold and reviewer address list
- An adaptive payout engine: `payout = base × bonus_bps - decay_bps × days_late`, capped at the base amount
- A `Waitlist<T>` shared object — a FIFO queue of funding requests that are promoted to live agreements when pool balance allows

**`credential.move`** — A soulbound NFT (non-transferable) minted when `complete_agreement` is called. Stored permanently in the recipient's wallet as proof of successful completion.

**`staking.move`** — Yield reserve deposits that back the pool's APY payouts.

### Milestone state machine

```
Locked → Open → Submitted → Streaming → Paid
                          ↘ Partially Released → (withheld recycled)
                          ↘ Rejected           → (withheld recycled)
              → Expired                        → (withheld recycled)
```

### Frontend — React + Vite + Tailwind + @mysten/dapp-kit

Five role-specific pages, all reading live on-chain state:
- **Treasury**: pool balance, APY, deposit controls
- **Manager Dashboard**: issue reviewer caps, create agreements, manage waitlist
- **My Grants**: recipient view — submit proof, track milestone states, claim vested funds
- **Review Inbox**: reviewer view — see submitted milestones with proof URLs, cast votes
- **Public View**: open to anyone — live pool stats, all active agreements, milestone states

---

## What makes it adaptive

Most on-chain funding systems are binary. This one uses a formula:

```
effective_payout = base_amount
                 + (base × on_time_bonus_bps / 10000)   [if submitted before deadline]
                 - (base × late_decay_bps / 10000 × days_late)  [if submitted after deadline]
```

The result is then streamed through a vesting curve chosen at agreement creation:
- **Linear**: constant drip over the stream duration
- **Stepped**: 25% every quarter of the duration
- **Accelerating (quadratic)**: slow start, fast finish — rewards sustained engagement

The difference between `base_amount` and `effective_payout` is the `withheld` amount. Once the milestone reaches a terminal state, any withheld balance is recycled back to the shared pool via `recycle_withheld`, which automatically triggers `try_fund_next` to promote the next waitlist entry.

---

## Live demo

**Network**: Sui Testnet  
**Package**: `0xe5324915726a9a96d4034fdb51e8251772fd463dd2b40e2e332a6aa7880980da`  
**Frontend**: runs locally via `cd frontend && npm install && npm run dev`

Demo scenario seeded on-chain:
- 1.5 SUI deposited in pool
- 2 ReviewerCaps issued
- Ada Lovelace agreement: 1 SUI across 2 milestones, linear vesting
- Grace Hopper waitlist entry: queued, ready to fund when pool allows
- M1 submitted and reviewer-approved → currently in Streaming state

---

## What's next

- **Multi-token support**: the contracts are generic over `<T>` — any Sui coin type works
- **DAO governance**: replace `ManagerCap` with a multisig or on-chain vote for reviewer appointments
- **IPFS proof storage**: replace URL strings with content-addressed proof hashes
- **Waitlist auctions**: let candidates bid for queue priority by staking SUI

---

## Team

Built solo for DeepSurge 2026.
