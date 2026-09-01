# X-Ray Report

> Unight | 943 nSLOC | ad62511 (`main`) | Foundry | 01/09/26

---

## 1. Protocol Overview

**What it does:** Unight lets a Uniswap v4 LP account use terminal, dormant, one-sided liquidity to fund fixed-rate Midnight lending settlements.

- **Users**: LP owners configure accounts; executors submit auto-lend offers; borrowers take LP maker bids through Midnight.
- **Core flow**: terminal v4 liquidity is removed only during a Midnight callback, then the account grants Midnight an exact loan-token allowance.
- **Key mechanism**: immutable account custody, per-account policy caps, registry allowlists, callback context commitments, and terminal-position adapter checks.
- **Token model**: one configured loan token per account funds Midnight buyer assets; the account also custodies one v4 position NFT.
- **Admin model**: registry owner controls global allowlists; each account owner controls policy, executors, closure, NFT withdrawal, and residual token sweep.

For a visual overview of the protocol's architecture, see the [architecture diagram](architecture.svg).

### Contracts in Scope

| Subsystem | Key Contracts | nSLOC | Role |
|-----------|--------------|------:|------|
| Account custody & settlement | `UnightAccount` | 434 | Per-LP account that owns the v4 NFT, validates policy, and funds Midnight callbacks. |
| Deployment | `UnightAccountFactory` | 87 | CREATE2 account factory keyed by owner, position, pool, and token. |
| Governance allowlists | `UnightPolicyRegistry` | 50 | Owner-controlled pool, market, ratifier, and oracle approvals. |
| Maker-bid authorization | `UnightBidRatifier` | 37 | Read-only adapter composing Midnight base ratification with account checks. |
| Math & v4 adapter | `MarketId`, `UnightTypes`, `V4LiquidityMath`, `V4TerminalPositionAdapter` | 196 | Structs, market hashing, liquidity math, and constrained v4 unwind logic. |

### How It Fits Together

The core trick: the account turns an LP's terminal v4 position into tightly capped Midnight buyer funding without letting arbitrary callbacks or arbitrary v4 actions through.

### Account Creation

```text
LP / anyone
└─ UnightAccountFactory.createAccount()
   ├─ UnightAccount.constructor()
   │  ├─ UnightPolicyRegistry.isPoolApproved()
   │  └─ UnightPolicyRegistry.isDormancyOracleApproved()
   └─ accountOf[owner][positionId] = account
```

*The factory is permissionless, but the account constructor enforces approved pool and oracle inputs.*

### Auto-Lend Settlement

```text
Owner or executor
└─ UnightAccount.takeAutoLend()
   ├─ registry / policy / capacity / Midnight authorization checks
   ├─ _execution = AutoLend context
   └─ Midnight.take()
      └─ UnightAccount.onBuy()
         ├─ V4TerminalPositionAdapter.removeForFunding()
         ├─ committedBuyerAssets += buyerAssets
         └─ IERC20.approve(midnight, buyerAssets)
```

*The callback is the only place the account removes liquidity and approves Midnight funding.*

### Maker-Bid Settlement

```text
Borrower through Midnight
└─ UnightBidRatifier.isRatified()
   ├─ baseRatifier.isRatified()
   └─ UnightAccount.registerBidContext()
      └─ UnightAccount.onBuy()
         ├─ bidBoardBuyerAssets += buyerAssets
         └─ delete _execution
```

*The ratifier is read-only, while the account validates callback commitments at settlement time.*

### Position Exit

```text
LP owner
└─ UnightAccount.close()
   ├─ policy.enabled = false
   └─ Midnight.setIsAuthorized(account, false, owner)
      └─ withdrawPosition() / sweepLoanToken()
```

*NFT withdrawal and token sweep require closure plus zero selected-market credit and debt.*

## 2. Threat & Trust Model

### Protocol Threat Profile

> Protocol classified as: **Lending/Borrowing** with **DEX/AMM** characteristics

The strongest code signals are Midnight credit/debt settlement, market maturity, continuous/settlement fees, and fixed-rate offer taking; Uniswap v4 concentrated-liquidity terminal math adds AMM/LP-position risk.

### Actors & Adversary Model

| Actor | Trust Level | Capabilities |
|-------|-------------|-------------|
| Account owner / LP | Trusted per account | Instant policy changes, executor grants, close, NFT withdrawal, and residual loan-token sweep; no timelock or pause module. |
| Registry owner | Trusted governance | Instant allowlist changes for pools, markets, ratifiers, and dormancy oracles; registry itself holds no funds. |
| Executor | Bounded (owner-enabled) | Can call `takeAutoLend` within policy, cap, expiry, registry, authorization, and callback checks. |
| Bid ratifier | Bounded (immutable per account) | Can register maker-bid context only when configured and only while account is idle. |
| Midnight | Trusted external protocol | Sole caller of `onBuy`; controls settlement outputs, credit/debt reads, fees, market metadata, and authorization state. |
| Dormancy oracle | Trusted external data source | Determines whether a terminal v4 position has satisfied historical dwell. |
| Uniswap v4 PositionManager/PoolManager | Trusted external protocol | Custodies position NFT, reports pool/position/tick state, and executes liquidity removal. |

**Adversary Ranking** (ordered by threat level for this protocol type, adjusted by git evidence):

1. **Oracle or terminality manipulator** — dormancy, tick, and market data decide whether LP liquidity can fund settlement.
2. **Keeper/executor with stale or adversarial offer inputs** — executors can submit auto-lend offers under owner-granted permission and account policy constraints.
3. **Malicious borrower / maker-bid taker** — bid-board flow depends on ratifier checks, callback data, and Midnight-provided settlement values aligning.
4. **Compromised account or registry owner** — owner powers are immediate and affect policy, executor permissions, allowlists, and lifecycle.
5. **External protocol failure** — Midnight and Uniswap v4 are not in scope but sit directly on value movement and accounting paths.

See [entry-points.md](entry-points.md) for the full permissionless entry point map.

### Trust Boundaries

- **Registry allowlist boundary** — registry owner can instantly approve pools, markets, ratifiers, and oracles consumed by account checks at `UnightAccount.sol:155`, `226`, `334`; no operational delay exists.

- **Midnight callback boundary** — `onBuy` accepts only `msg.sender == midnight` at `UnightAccount.sol:440`, then trusts Midnight-returned settlement values subject to context, fee, rate, and debt checks.

- **Uniswap v4 unwind boundary** — adapter validates ownership, pool id, terminal side, dormancy, and received balance at `V4TerminalPositionAdapter.sol:65-159` before account approval.

- **Account-owner boundary** — the LP owner can instantly change policy/executors or close at `UnightAccount.sol:203-263`; the account has no timelock, multisig detection, or pause abstraction.

### Key Attack Surfaces

- **Callback context and settlement binding** &nbsp;[[G-35](invariants.md#g-35), [G-36](invariants.md#g-36), [I-5](invariants.md#i-5)] — `UnightAccount.onBuy:440-489` mixes explicit and idle-open maker-bid contexts; worth tracing every field that enters `callbackDataHash`, nonce, epoch, buyer, and market hash.

- **Terminal v4 liquidity removal math** &nbsp;[[G-37](invariants.md#g-37), [I-8](invariants.md#i-8)] — `V4TerminalPositionAdapter.removeForFunding:122-159` rounds liquidity upward and relies on balance deltas after `modifyLiquidities`; worth checking boundary cases around dust, fees, and hooks.

- **Capacity accounting across settlement modes** &nbsp;[[I-1](invariants.md#i-1), [I-7](invariants.md#i-7), [E-1](invariants.md#e-1)] — `remainingCapacity:284-297`, `remainingBidCapacity:300-305`, and `onBuy:478-484` split global vs mode counters; worth confirming all settlement paths keep those counters aligned.

- **Registry-controlled component substitution** &nbsp;[[X-1](invariants.md#x-1)] — `UnightPolicyRegistry:39-58` feeds constructor, policy, and offer gates; worth reviewing registry owner operations against accepted external dependencies.

- **Owner operational powers without delay** — `UnightAccount:203-263` lets the LP owner change executors/policy, disable, close, and revoke authorization instantly; worth checking intended operational key custody.

- **Maker-bid ratifier/account handshake** &nbsp;[[X-2](invariants.md#x-2)] — `UnightBidRatifier.isRatified:49-56` and `registerBidContext:389-417` split read-only offer verification from stateful context installation; worth checking race and replay assumptions.

### Upgrade Architecture Concerns

- No upgradeable contracts or initializer entry points were detected; accounts and registry use constructors and immutable dependencies.

### Protocol-Type Concerns

**As Lending/Borrowing:**

- `UnightAccount.takeAutoLend:337-340` checks maker credit, owner debt, remaining capacity, and authorization before settlement; external Midnight accounting freshness is central.
- `UnightAccount.onBuy:467-472` checks debt, continuous fee, settlement fee, and minimum net rate after Midnight callback data arrives.

**As DEX/AMM:**

- `V4TerminalPositionAdapter.snapshot:87-108` derives terminal principal from current tick, tick bounds, tick buffer, dormancy, and Uniswap liquidity math.
- `V4LiquidityMath:13-63` converts concentrated liquidity to amounts and back; rounding direction matters because removal targets a required token amount.

### Temporal Risk Profile

**Deployment & Initialization:**

- `UnightAccountFactory.createAccount:63-88` is permissionless and deterministic, while constructor approval checks rely on current registry state.

**Market Stress:**

- `UnightAccount.onBuy:466-469` rejects maturity, expired callback deadline, and excessive fees at callback time, not just at offer submission.

### Composability & Dependency Risks

**Dependency Risk Map:**

> **Midnight** — via `takeAutoLend`, `onBuy`, `close`, `withdrawPosition`, `sweepLoanToken`
> - Assumes: market metadata, credit/debt, authorization, fee, and settlement callback behavior are canonical.
> - Validates: caller, market hash, policy nonce, position epoch, debt unchanged, fee ceilings, and minimum net rate.
> - Mutability: external dependency, not determined in repo.
> - On failure: most reads/calls revert; bad accepted values are bounded by account checks.

> **Uniswap v4 PositionManager/PoolManager** — via `V4TerminalPositionAdapter`
> - Assumes: NFT ownership, pool/position metadata, liquidity, slot0 tick, and modifyLiquidities behavior are canonical.
> - Validates: owner, pool id, loan-token terminal side, received loan-token balance delta, and output minimum.
> - Mutability: external dependency, not determined in repo.
> - On failure: adapter reverts or leaves settlement unfunded.

> **Dormancy oracle** — via `V4TerminalPositionAdapter.snapshot`
> - Assumes: `isDormant` correctly proves terminal dwell for pool id, ticks, tick buffer, and minimum dwell.
> - Validates: oracle address approved at account construction.
> - Mutability: external dependency, registry-controlled selection.
> - On failure: adapter reverts when false; true responses are trusted.

> **ERC20 loan token** — via `approve`, `transfer`, and `balanceOf`
> - Assumes: standard boolean-return ERC20 behavior and balance delta semantics.
> - Validates: transfer/approve return values and post-v4 balance delta.
> - Mutability: token contract external.
> - On failure: account reverts on false return or insufficient balance delta.

**Token Assumptions** *(unvalidated only)*:

- Fee-on-transfer or rebasing loan tokens are not explicitly modeled; balance-delta funding is checked, but allowance semantics are assumed standard.

## 3. Invariants

> ### Full invariant map: **[invariants.md](invariants.md)**
>
> A dedicated reference file contains the complete invariant analysis — do not look here for the catalog.
>
> - **37 Enforced Guards** (`G-1` … `G-37`) — per-call preconditions with `Check` / `Location` / `Purpose`
> - **8 Single-Contract Invariants** (`I-1` … `I-8`) — Conservation, Bound, Ratio, StateMachine, Temporal
> - **2 Cross-Contract Invariants** (`X-1` … `X-2`) — caller/callee pairs that cross scope boundaries
> - **1 Economic Invariant** (`E-1`) — higher-order property deriving from `I-N` + `X-N`
>
> Every inferred block cites a concrete delta-pair, guard-lift + write-sites, state edge, temporal predicate, or NatSpec quote. The **On-chain=No** blocks are the high-signal ones — each is simultaneously an invariant and a potential bug. Attack-surface bullets above cross-link directly into the relevant blocks.

## 4. Documentation Quality

| Aspect | Status | Notes |
|--------|--------|-------|
| README | Present | `README.md` describes purpose, flows, tests, and external docs. |
| NatSpec | 15 annotations detected | Core contracts and libraries have meaningful NatSpec on roles, callbacks, policy, and v4 adapter behavior. |
| Spec/Whitepaper | Missing | No dedicated whitepaper/spec/design doc was detected outside README. |
| Inline Comments | Adequate | Security-relevant intent is documented around callback context, terminality, and local Midnight interface pinning. |

## 5. Test Analysis

| Metric | Value | Source |
|--------|-------|--------|
| Test files | 12 | File scan (always reliable) |
| Test functions | 55 | File scan (always reliable) |
| Line coverage | Unavailable — fork RPC DNS failure after `--ir-minimum` retry | Coverage tool (requires compilation and fork RPC) |
| Branch coverage | Unavailable — fork RPC DNS failure after `--ir-minimum` retry | Coverage tool (requires compilation and fork RPC) |

### Test Depth

| Category | Count | Contracts Covered |
|----------|-------|-------------------|
| Unit | 55 | broad account, adapter, policy, callback, ratifier, params, and bid-board tests |
| Fork | 2 | Base mainnet fork fixtures detected |
| Stateless Fuzz | 4 | fork-backed fuzz plus deterministic harness signals |
| Stateful Fuzz (Foundry) | 0 | none detected |
| Stateful Fuzz (Echidna) | 0 | config present but no Echidna functions detected |
| Stateful Fuzz (Medusa) | 5 | Medusa config and functions detected |
| Formal Verification (Certora) | 0 | none detected |
| Formal Verification (Halmos) | 0 | none detected |
| Formal Verification (HEVM) | 0 | none detected |

### Gaps

- Foundry invariant tests are absent despite lifecycle/callback state machines.
- Formal verification is absent for liquidity math, capacity accounting, and callback commitment invariants.
- Coverage metrics require a working Base RPC; current run failed at fork setup rather than test discovery.

## 6. Developer & Git History

> Repo shape: normal_dev — current branch `main` at `ad62511` has 10 commits, 4 source-touching commits, and 28 days of visible history.

### Contributors

| Author | Commits | Source Lines (+/-) | % of Source Changes |
|--------|--------:|--------------------|--------------------:|
| yeahChibyke | 10 | +1419 / -21 | 100% |

### Review & Process Signals

| Signal | Value | Assessment |
|--------|-------|------------|
| Unique contributors | 1 | Single-dev |
| Merge commits | 0 of 10 (0%) | No merge commits visible on analyzed branch |
| Repo age | 2026-07-30 -> 2026-08-27 | 28 days |
| Recent source activity (30d) | 4 commits | Active, all source commits inside recent window |
| Test co-change rate | 50% | Half of source-changing commits also modified tests; measures co-modification, not coverage |

### File Hotspots

| File | Modifications | Note |
|------|-------------:|------|
| `src/interfaces/IMidnight.sol` | 4 | External boundary interface churn. |
| `src/UnightAccount.sol` | 3 | Core custody and settlement hotspot. |
| `src/UnightBidRatifier.sol` | 3 | Maker-bid authorization hotspot. |
| `src/interfaces/IMidnightRatifier.sol` | 3 | Ratifier boundary churn. |
| `src/UnightAccountFactory.sol` | 2 | Deployment surface touched twice. |

### Security-Relevant Commits

**Score** = weighted sum of fix-like signals in a commit: message keywords, diff patterns, touched domains, and change shape. **10+ warrants a manual diff.**

| SHA | Date | Subject | Score | Key Signal |
|-----|------|---------|------:|------------|
| d8d8977 | 2026-08-20 | smart contracts written | 12 | large initial security-domain implementation |
| c6ae852 | 2026-08-25 | test: add live Auto-Lend fork settlement fixture | 6 | accounting/signature boundary touched with tests |
| 80c7a3a | 2026-08-20 | added proper NatSpec | 6 | security-domain files touched without tests |
| 441e05e | 2026-08-27 | test: add comprehensive live LP Bid Board fork coverag | 5 | runtime guards and accounting paths touched with tests |

### Dangerous Area Evolution

| Security Area | Commits | Key Files |
|--------------|--------:|-----------|
| fund_flows | 4 | `UnightAccount.sol`, `UnightPolicyRegistry.sol`, `IMidnight.sol` |
| oracle_price | 4 | `UnightAccount.sol`, `UnightAccountFactory.sol`, `V4TerminalPositionAdapter.sol` |
| liquidation | 4 | `IMidnight.sol` |
| access_control | 3 | `UnightAccount.sol`, `UnightPolicyRegistry.sol` |
| signatures | 3 | `UnightAccount.sol` |
| state_machines | 3 | `UnightAccount.sol` |

### Forked Dependencies

| Library | Path | Upstream | Status | Notes |
|---------|------|----------|--------|-------|
| v4-hooks-public | `lib/v4-hooks-public` | not resolved by script | Submodule | Large external dependency tree; not internalized by this repo. |

### Security Observations

- **Single-developer branch** — yeahChibyke authored 100% of commits and source additions.
- **No merge history** — 0 merge commits on `main`, so peer-review signals are not visible from git.
- **Core hotspot** — `UnightAccount.sol` appears in access-control, fund-flow, oracle, signature, and state-machine areas.
- **External interface churn** — `IMidnight.sol` is the most modified source file and is the main external lending boundary.
- **Late source burst** — all four source-touching commits are inside the final 30-day window ending 2026-08-27.
- **Fork dependency footprint** — `lib/v4-hooks-public` is a submodule with a very large Solidity file count and broad pragma spread.

### Cross-Reference Synthesis

- **`UnightAccount.sol` is both core hotspot and attack-surface center** — callback, capacity, policy, and v4 unwind flows all route through it.
- **`IMidnight.sol` churn aligns with trust-boundary priority** — Midnight metadata, credit/debt, fee, and callback assumptions dominate Section 2.
- **Test breadth exists but coverage is blocked by RPC** — 55 scanned tests and fork/fuzz signals are present, while runtime coverage depends on external Base RPC availability.

## X-Ray Verdict

**FRAGILE** — tests and NatSpec exist, but no timelock/pause architecture, no formal verification, and single-developer/no-merge history keep readiness below adequate for a money-moving integration.

**Structural facts:**
1. 943 in-scope nSLOC across account, factory, registry, ratifier, and v4/math helper subsystems.
2. 12 test files and 55 test functions were detected, with stateless fuzz, fork tests, and Medusa config/functions present.
3. No upgradeable contracts, proxy initializers, or pause module were detected.
4. Current branch `main` has 10 commits, one contributor, and 4 source-touching commits over 28 days.
