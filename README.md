# Adaptive Funding Engine

A milestone-based scholarship and grant disbursement system built on the Sui blockchain. Funds vest adaptively — on-time delivery earns bonuses, late submissions decay the payout, and withheld funds recycle automatically to the next recipient in a waitlist.

**Live on Sui Testnet · DeepSurge 2026**

---

## What it does

Traditional grants are all-or-nothing. The Adaptive Funding Engine turns a grant into a series of on-chain milestones with built-in accountability:

- **Recipients** submit proof of work for each milestone
- **Reviewers** vote to approve, warn, or reject
- When quorum is reached, funds stream to the recipient via a configurable vesting curve (linear, stepped, or accelerating)
- Late submissions lose a fraction of payout via an on-chain decay formula
- Withheld or rejected funds recycle back to the pool for the next person in the waitlist
- Completing all milestones mints a soulbound on-chain credential

---

## Architecture

### Smart Contracts (Move 2024, Sui Testnet)

| Module | Responsibility |
|---|---|
| `program.move` | ManagerCap + ReviewerCap issuance, access control |
| `pool.move` | SUI treasury, deposit, yield accrual |
| `agreement.move` | Milestone lifecycle, voting, adaptive payout, waitlist |
| `credential.move` | Soulbound NFT minted on agreement completion |
| `staking.move` | Yield reserve deposits |

1,291 lines of Move across 5 modules · 27 unit tests

### Frontend (React + Vite + Tailwind + @mysten/dapp-kit)

| Page | Role |
|---|---|
| Treasury | Deposit SUI, accrue yield, view pool stats |
| Manager | Issue reviewer caps, create agreements, manage waitlist |
| My Grants | Submit proof, claim vested funds, complete agreement |
| Review Inbox | Cast votes with optional review notes |
| Public View | Live on-chain stats and all active agreements |

---

## Deployed objects (Sui Testnet)

| Object | ID |
|---|---|
| Package | `0xe5324915726a9a96d4034fdb51e8251772fd463dd2b40e2e332a6aa7880980da` |
| FundingPool | `0x7dc551e06630ea6ab420d30fae5775cba384f7aa7e657227b14ded85fa153705` |
| ManagerCap | `0xdf5ec7452700dc94e25f7f5bf914f001d57d960ea2220189a917c1f22b4e885b` |
| Pool Object | `0xebeefb46f48731cb4c3e73306d4bd8899cfdd03b85ffb720995c58d3da4dc201` |
| Waitlist | `0x0f6cd9d93a33faf4288fcacf1adf4c59b00709f3e37b8d9aa59a17a5be922c3d` |
| StakeVault | `0x43a07bf315ccd611748781275a580f912c738cef8ea3bd3f9611cec2696b30bd` |

---

## Run locally

### Prerequisites

- Node.js 18+
- Sui CLI (for contract interaction)
- Sui Wallet Chrome extension

### Frontend

```bash
cd frontend
npm install
npm run dev
# → http://localhost:5173
```

Connect the Sui Wallet extension to **Testnet**. All contract objects are pre-configured in `frontend/src/constants.ts`.

### Contracts (already deployed — for reference)

```bash
cd contracts
sui move build
sui move test          # 27 tests
sui client publish --gas-budget 200000000
```

---

## Demo flow

1. **Treasury** — deposit SUI into the pool
2. **Manager** — issue ReviewerCaps, create a milestone agreement for a recipient
3. **Manager** — add a candidate to the waitlist; fund from waitlist
4. **My Grants** (recipient wallet) — submit proof for Milestone 1
5. **Review Inbox** (reviewer wallet) — cast vote (Approve / Warn / Reject)
6. Quorum triggers payout → M1 transitions to **Streaming**
7. **My Grants** — claim vested funds once cliff passes
8. After all milestones complete → **Complete Agreement & Mint Credential**

---

## Adaptive payout formula

```
payout = base_amount
       × on_time_bonus_bps      (if submitted before deadline)
       - late_decay_bps/day     (if submitted after deadline)
       × vesting_curve(elapsed) (linear | stepped | accelerating)
```

Withheld amount = `base_amount - payout` → recycled to pool → funds next waitlist entry.

---

## License

MIT
