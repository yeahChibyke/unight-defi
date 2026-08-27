# Unight X-Ray

> Pre-audit readiness report · analyzed branch: `main` at `441e05e` · source nSLOC: **943**

## 1. Overview

Unight is a non-upgradeable LP account and factory system that holds one Uniswap v4 position and conditionally converts terminal, historically dormant liquidity into Midnight credit. The account supports two settlement paths: permissioned Auto-Lend execution of borrower sell offers and maker LP Bid Board settlement through a ratifier and Midnight callback.

The in-scope source consists of four contracts, four internal libraries, and interfaces. `UnightAccount` holds the position NFT, validates policy and market state, removes terminal liquidity through a constrained PositionManager action sequence, and authorizes exact USDC funding. `UnightPolicyRegistry` supplies governance allowlists. `UnightAccountFactory` creates deterministic accounts. `UnightBidRatifier` composes Midnight base authorization with account-specific offer checks.

The documentation describes a single-market, single-position V1 centered on Base, USDC, cbBTC, Uniswap v4, and Midnight (per spec). The selected fork fixture is pinned to Base block `50_000_000` (per spec).

### Scope

| Subsystem | Files | nSLOC |
|---|---:|---:|
| Account and factory | 2 | 521 |
| Policy and ratification | 2 | 87 |
| Arithmetic and v4 adapter | 4 | 196 |
| **Total** | **8** | **804** |

The 943 total reported by enumeration includes 7 interfaces contributing 139 nSLOC. Interfaces are excluded from the behavioral scope above.

### Protocol classification

Protocol classified as: **Lending/Borrowing** with **DEX/AMM / concentrated-liquidity adapter** characteristics. The lending classification is based on credit, debt, collateral, maturity, health, and fee interactions with Midnight. The secondary DEX characteristic is based on v4 ticks, LP position liquidity, PoolManager state, and PositionManager liquidity withdrawal.

### Compatibility observations

No verified backwards-compatibility remnants were identified. The current branch documents the static-call ratifier design as intentional, and the relevant ratifier is actively part of the settlement path.

## 2. Threat & Trust Model

### Actors

| Actor | Capabilities and trust boundary |
|---|---|
| LP owner | Sets policy, executor permissions, closes the account, withdraws the NFT after credit/debt are zero, and sweeps residual loan tokens after closure. Trusted for its own account configuration. |
| Auto-Lend executor | Calls `takeAutoLend` if enabled by the LP. It supplies offers, units, limits, and deadlines; it is not trusted for authorization or capacity. |
| Borrower / offer maker | Supplies offer fields and collateral or maker-bid terms. Midnight and account checks remain authoritative. |
| Registry owner | Instantly changes pool, market, ratifier, and dormancy-oracle allowlists. No timelock, multisig, pause, or delayed operational action is present in scope. |
| Midnight | External settlement authority and callback caller. The account relies on canonical market metadata, credit/debt transitions, fee reads, authorization, and exact callback behavior. |
| Uniswap v4 | External custody and liquidity accounting boundary. The adapter relies on PositionManager ownership/metadata, PoolManager tick/price state, and constrained action semantics. |
| Dormancy oracle | Supplies historical terminality. The account trusts the approved oracle response for the selected position. |

### Trust boundaries

- Account ↔ Midnight: `take`, ratification, buy callback, authorization, credit/debt, maturity, and fee state cross this boundary.
- Account ↔ PositionManager/PoolManager: NFT custody, position identity, terminal tick state, liquidity conversion, and token extraction cross this boundary.
- Account ↔ Registry/oracle: allowlists and historical dormancy are externalized configuration inputs.
- LP ↔ executor: executor permissions are an LP-controlled operational boundary; the executor cannot change policy but can choose execution parameters within policy.

### Key attack surfaces

- **Callback authority and context binding** [ [G-14](invariants.md#g-14), [I-5](invariants.md#i-5), [X-2](invariants.md#x-2) ] — `onBuy` accepts only Midnight and binds market, buyer, callback data, policy epoch, position epoch, fees, debt, and units. Trace all callback variants and verify the static ratifier/callback sequencing remains consistent.

- **Terminal v4 withdrawal and token accounting** [ [G-17](invariants.md#g-17), [I-1](invariants.md#i-1), [X-1](invariants.md#x-1), [E-1](invariants.md#e-1) ] — the adapter requires terminality and dormancy, then executes `DECREASE_LIQUIDITY` plus `TAKE_PAIR`. Verify exact principal, rounding, fee/dust handling, and supported hook behavior across both currency orderings.

- **Capacity and monotonic accounting** [ [G-8](invariants.md#g-8), [I-2](invariants.md#i-2), [I-3](invariants.md#i-3), [E-2](invariants.md#e-2) ] — global and mode caps are checked before and during callback settlement, while committed values increase only after removal. Confirm Bid Board capacity also reflects terminal-principal availability where intended by the specification.

- **Midnight market, fee, health, and maturity assumptions** [ [G-10](invariants.md#g-10), [G-15](invariants.md#g-15), [X-3](invariants.md#x-3) ] — account logic depends on external market metadata, fee values, debt, credit, and maturity. Fork tests cover selected live states, but broader state-transition and boundary validation remains necessary.

- **Offer authorization and stale epochs** [ [G-11](invariants.md#g-11), [G-12](invariants.md#g-12), [I-4](invariants.md#i-4) ] — the ratifier checks maker, callback, ratifier, max assets, and maturity; callback data binds policy and position epochs. Verify cancellation, replay, group consumption, and account lifecycle transitions.

- **Registry-owner operational power** — the registry owner can instantly approve or revoke pools, markets, ratifiers, and oracles. There is no in-scope pause or delay protecting these actions; all accounts consult the registry during relevant setup or execution checks.

- **LP-owner operational power** — owner actions are immediate and include disabling policy, closing, and changing executors. `idle` blocks these actions during an active callback, but no general emergency pause covers every external integration operation.

### Protocol-type concerns

The primary lending concerns are collateral valuation and health delegated to Midnight, maturity/post-maturity semantics, debt/credit accounting, fee treatment, and exact ownership of resulting credit. The secondary v4 concerns are tick-boundary selection, concentrated-liquidity arithmetic, PositionManager action encoding, hook-dependent behavior, and flash-accounting balance deltas. Liquidation and oracle correctness remain primarily external Midnight responsibilities, but Unight depends on their resulting state.

## 3. Invariants

> The complete catalog is in [invariants.md](invariants.md): **17 enforced guards**, **6 single-contract inferred invariants**, **3 cross-contract invariants**, and **2 economic derivations**; **3 inferred items are not fully enforced on-chain**.

## 4. Integrations

| Integration | Scope and assumptions |
|---|---|
| Uniswap v4 | PositionManager NFT custody and `modifyLiquidities`; PoolManager slot0/tick; v4 libraries and hook execution are external. |
| Midnight | Market metadata, `take`, static ratification, buy callback, credit/debt, fees, authorization, maturity, and health are external. |
| ERC20 USDC/cbBTC | Exact approval and balance-delta assumptions; token return values are checked for account-owned transfers/approvals. |
| ERC721 PositionManager | The account accepts only the configured PositionManager and token ID. |
| Dormancy oracle | Approved oracle is trusted to report the historical dwell condition. |
| OpenZeppelin | ERC20/ERC721 interfaces and standard token interaction primitives. |

## 5. Test Analysis

The repository now contains 9 focused Foundry test files and 55 test functions,
including Base fork fuzz tests. It also contains deterministic Medusa and
Echidna targets under `test/fizz/ToolFuzzTester.sol` with committed runner
configuration. The standalone targets intentionally do not exercise live
settlement.

The suite includes Base fork tests for custody, policy, adapter, callback, ratifier, Auto-Lend, and LP Bid Board paths. The latest coverage command compiled with the IR-minimum fallback, but fork execution could not resolve `rpc.ankr.com`; therefore usable line/branch coverage metrics are unavailable from this run. This execution failure is environmental and does not establish test absence.

The highest-value remaining validation is broader stateful fork fuzzing over
partial fills, terminality, callback data, maturity, and failures. Formal or
independent review of the external-call assumptions is also not present.

## 6. Documentation Quality

`UNIGHT.md`, `STRATEGY.md`, `DEMO.md`, `params.md`, and `README.md` describe the intended flow, pinned fork parameters, live integrations, staged implementation, and test commands. The docs explicitly separate on-chain enforcement from planned off-chain monitor/Bid Board services (per spec). `params.md` provides reproducible addresses and block state, but live deployment and external protocol assumptions should be revalidated whenever the pinned block or dependencies change.

## 7. Git History

Analyzed branch: `main` at `441e05e`; 9 commits, 1 contributor, and 4 source-touching commits over 28 days.

- Security-relevant source construction is concentrated in `d8d8977` (`smart contracts written`) and `80c7a3a` (NatSpec), with the initial implementation touching access control, fund flows, signatures, liquidation, oracle/price, and state-machine areas.
- Recent integration commits `c6ae852` and `441e05e` change interfaces, callback/ratifier behavior, and accounting while adding fork tests. These are late changes on the analyzed branch and merit focused regression review.
- Git analysis identifies `src/UnightAccount.sol`, `src/UnightPolicyRegistry.sol`, and the v4 adapter as recurring security-relevant areas. The reported 0.6 fix-without-test rate is a commit-history co-occurrence signal, not a coverage result.
- `lib/v4-hooks-public` is an uninternalized git submodule with 12,887 Solidity files detected by the analysis; it is an external dependency boundary, not part of the in-scope nSLOC.

## X-Ray Verdict

**Tier: 3 — Integration-ready, verification incomplete.**

The core account, policy, ratifier, and v4 adapter paths are implemented and
have live Base fork test coverage, including both settlement modes and major
failure cases. Deterministic external-fuzzer checks now run, while the live
fork fuzz layer is Foundry-based. Readiness remains limited by deployment
validation, broader stateful fork fuzzing, and independent security review.
