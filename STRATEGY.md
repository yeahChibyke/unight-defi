# Unight Strategy and Implementation Guide

> Conditional fixed-rate lending for dormant Uniswap v4 liquidity through Morpho Midnight.

## 1. Executive Summary

Unight allows a Uniswap v4 LP to lend a bounded amount of terminal inventory while keeping the original position NFT and a configured amount of residual liquidity.

The inventory remains in Uniswap until a valid Midnight settlement occurs. During settlement, Midnight calls an Unight callback, Unight removes the exact required amount of terminal principal from the v4 position, and Midnight pulls the loan token from Unight in the same transaction.

Unight supports two discovery paths:

- **Auto-Lend:** Unight finds eligible borrower asks and takes them for the LP.
- **LP Bid Board:** The LP publishes callback-backed Midnight lending offers through Unight’s own distribution layer.

Midnight remains the lending, credit, debt, collateral, liquidation, fee, maturity, and settlement protocol. The Bid Board is only a discovery layer.

Unight preserves the LP’s NFT, range, and configured residual liquidity. It does not preserve the original liquidity size, guarantee immediate re-entry, guarantee repayment at maturity, or protect the LP from Midnight market losses.

## 2. V1 Scope

V1 is deliberately narrow:

- Base only;
- Uniswap v4 positions only;
- USDC as the only loan token;
- approved Midnight markets and maturity bands;
- terminal, single-sided principal only;
- Auto-Lend and LP Bid Board;
- no swaps inside the callback;
- no leverage;
- no cross-chain inventory;
- no arbitrary AMMs;
- no automatic market selection;
- no arbitrary Uniswap v4 hooks;
- no automatic recycling of capacity after maturity or credit withdrawal.

The first deployment should support one approved pool, one Midnight market, and small caps.

## 2.1 Current implementation status

The account, factory, policy registry, terminal-position adapter, ratifier
integration, and both settlement paths are implemented. The pinned Base fork
suite currently passes 55 tests, including successful Auto-Lend and LP Bid
Board settlement plus partial-fill, group, fee, rollback, health, maturity,
custody, and policy cases.

Foundry also runs fork-backed fuzz tests for policy boundaries and callback
rollback. Medusa and Echidna run a separate deterministic harness for
accounting, cap, callback-commitment, epoch, and liquidity-math properties.
Because those standalone fuzzers do not reproduce Foundry fork cheatcodes,
their results are not evidence of live Midnight settlement. The remaining
contract-side milestone is deployment-grade validation: finalize production
deployment addresses and ratifier wiring, replace fork-local test controls
with reviewed production dependencies, and perform independent security and
operational review.

## 3. Product and Risk Model

The product transforms part of an LP’s dormant AMM inventory into fixed-maturity credit exposure.

Before settlement:

```text
LP owns v4 position
LP has terminal USDC principal
LP has no Midnight exposure from this policy
```

After settlement:

```text
v4 position has less liquidity
LP owns Midnight credit
borrower owns Midnight debt
LP bears Midnight market and liquidity risk
```

Midnight credit may be:

- withdrawn when liquidity is available;
- sold early at a discount or premium;
- repaid at or after maturity;
- impaired by bad debt and loss-factor accounting;
- temporarily illiquid after maturity.

Unless Unight adds an explicit insurance or reserve mechanism, the LP absorbs Midnight credit losses.

## 4. Core Design Principles

### 4.1 The LP remains the Midnight lender

The LP, not the Unight Account, should own the Midnight credit.

For Auto-Lend, the account calls Midnight with the LP as `taker` and the account as `takerCallback`. The LP must authorize the account in Midnight.

For LP Bid Board offers, the LP is the signed offer maker and buyer, while the Unight Account is the maker callback.

The account owns or controls the Uniswap position, but it should not become the owner of the LP’s Midnight credit unless custody is explicitly designed and disclosed.

### 4.2 Unight capacity is denominated in gross buyer assets

Midnight distinguishes:

```text
buyerAssets  = gross loan-token amount funded by the buyer callback
sellerAssets = amount received by the counterparty
units        = credit/debt units exchanged
```

Unight capacity is measured in raw USDC `buyerAssets` because that is the amount Midnight pulls from the callback.

For Auto-Lend asks, `maxAssets` may cap the borrower-side `sellerAssets`, so the borrower’s advertised amount is not necessarily the LP’s outflow.

The authoritative capacity check is:

```text
buyerAssets <= remaining global capacity
buyerAssets <= remaining mode capacity
buyerAssets <= safely removable terminal principal
buyerAssets <= configured offer limit
```

### 4.3 Principal, fees, and Midnight exposure are separate

Uniswap v4 principal, accrued fees, Midnight credit units, pending fees, recovered USDC, and realized losses must not share one accounting variable.

The implementation tracks at least:

```text
committedBuyerAssets
committedAutoAssets
committedBidAssets
v4PrincipalRemoved
midnightCreditUnits
midnightPendingFee
actualRecoveredAssets
realizedLoss
```

For v1, `committedBuyerAssets` is monotonic for the active policy. It is not reduced merely because Midnight credit matures, is withdrawn, or changes value. Capacity can only be reused after an explicit policy close and reconciliation process.

### 4.4 Dormancy is stronger than “currently out of range”

A current spot tick does not prove that inventory is safely dormant. A searcher may briefly move a pool out of range, trigger lending, and then return the pool to range.

Eligibility must require:

- current canonical pool state outside the range;
- a meaningful buffer beyond the boundary;
- historical dwell time outside the range;
- no same-transaction activation;
- fresh callback-time validation.

V1 should use either:

1. a dedicated Unight Guard Hook with tightly constrained observation-only permissions; or
2. a hookless pool paired with an independently verified onchain historical-observation mechanism.

Arbitrary “reviewed” hooks are not accepted in v1. Hooks that modify liquidity accounting or return custom deltas require a separate integration and audit.

## 5. Accounting Model

### 5.1 Capacity formula

```text
remainingGlobal = globalCap - committedBuyerAssets
remainingAuto   = autoCap - committedAutoAssets
remainingBid    = bidCap - committedBidAssets

safePrincipal = liveTerminalPrincipal - reactivationReserve

fillable = minimum(
    remainingGlobal,
    selectedModeRemaining,
    safePrincipal,
    maxLendableAmount,
    currentOfferRemaining
)
```

The values are recalculated from live state. Offchain values are estimates only.

### 5.2 Successful settlement accounting

At callback time:

1. Midnight supplies the authoritative `buyerAssets`.
2. Unight checks the amount against all caps.
3. Unight reserves the amount before external calls.
4. Unight removes enough v4 principal to cover it.
5. Midnight pulls exactly that amount.
6. The reservation becomes committed capacity.

If any step reverts, the entire transaction and reservation revert.

### 5.3 Fees and dust

Accrued v4 fees, pre-existing account balances, and incidental dust are not lendable principal.

The adapter must use balance snapshots and exact deltas. It must never approve or transfer the account’s entire USDC balance.

Any rounding surplus withdrawn from the v4 position is either:

- explicitly returned or kept as a separate LP balance; or
- counted as additional `v4PrincipalRemoved`.

It must not silently disappear from accounting.

## 6. Contract Architecture

### 6.1 `UnightAccount`

One non-upgradeable account per LP position.

Responsibilities:

- own the Uniswap v4 position NFT;
- store the LP owner immutably;
- store immutable Base, Midnight, PositionManager, PoolManager, and USDC addresses;
- store policy, caps, reserve, and epochs;
- track committed capacity;
- initiate Auto-Lend;
- implement `IBuyCallback`;
- validate LP Bid Board callback data;
- pause and permanently close lending;
- invalidate policies and offer cohorts;
- transfer the NFT only after safe exit checks.

The account must not expose:

- arbitrary `call`;
- arbitrary `delegatecall`;
- arbitrary PositionManager calldata;
- arbitrary Midnight forwarding;
- upgrade functions controlled by keepers or mutable registries.

### 6.2 `UnightAccountFactory`

Creates deterministic accounts and binds each account to one LP and one immutable protocol configuration.

The factory should prevent accidental duplicate accounts and emit an event containing the LP, account, position, and deployment configuration.

### 6.3 `V4TerminalPositionAdapter`

The adapter is the only component allowed to mutate the v4 position.

It must:

- read the canonical `PoolKey` and position information;
- derive the terminal asset from `currency0`/`currency1` ordering;
- verify the current tick and range;
- calculate terminal principal with exact integer math;
- separate principal from accrued fees;
- calculate liquidity to remove with conservative rounding;
- use meaningful minimum-output parameters;
- execute only the approved PositionManager action sequence;
- resolve positive deltas explicitly;
- send tokens to the Unight Account;
- reject unexpected token balances and hook deltas.

The normal action sequence is:

```text
DECREASE_LIQUIDITY
TAKE_PAIR to UnightAccount
```

The adapter must not accept user-supplied arbitrary action bytes.

### 6.4 `UnightDormancyHook` and observation interface

The Guard Hook records historical pool observations and exposes a conservative dormancy check.

For v1, the hook should not implement:

- custom liquidity accounting;
- removal fees;
- returned liquidity deltas;
- arbitrary external protocol calls.

The registry must verify its exact address, permission bitmap, and deployed code version.

### 6.5 `UnightPolicyRegistry`

The registry stores governed allowlists for:

- approved pools;
- approved hooks;
- approved Midnight markets;
- approved maturities;
- approved loan tokens;
- per-market exposure limits;
- market risk parameters.

It must not dynamically replace the callback-authorized Midnight or PositionManager address for existing accounts.

### 6.6 `UnightRatifier`

Use a dedicated ratifier for LP Bid Board offers when Unight must enforce offer-level conditions that the standard callback cannot see.

It may bind:

- LP maker;
- account callback;
- position ID and epoch;
- policy nonce;
- market;
- direction;
- group;
- expiry;
- callback data;
- optional taker restrictions.

The ratifier handles static offer authorization. The callback handles dynamic capacity, v4 state, and current fee checks.

### 6.7 No onchain Bid Board in v1

The Bid Board is an offchain distribution service for signed Midnight offers.

Midnight remains authoritative for:

- ratification;
- offer validity;
- group consumption;
- settlement;
- credit and debt creation.

The Bid Board must not claim that displayed capacity is reserved or guaranteed.

## 7. Callback and Settlement Design

### 7.1 Execution context

Auto-Lend creates a transient execution context before calling Midnight:

```text
offerHash
expectedLP
expectedMarket
expectedCallbackDataHash
maxBuyerAssets
minimumUnits
policyNonce
positionEpoch
deadline
```

`onBuy` must require an active context and validate every callback parameter available to it. The context is cleared after successful completion and naturally reverts if settlement fails.

For LP Bid Board offers, callback data and the ratifier bind the offer to the active LP policy and position epoch.

Checking only `msg.sender == Midnight` is insufficient.

### 7.2 Reentrancy

The account uses a settlement state machine:

```text
IDLE
AUTO_LEND_PENDING_CALLBACK
BID_CALLBACK
PAUSED
CLOSED
```

The account must:

- reject nested settlements;
- reserve capacity before external calls;
- lock policy and position mutation during settlement;
- reject callback context replacement;
- clear the lock only after success;
- tolerate rollback on failure.

Uniswap hooks, PositionManager subscribers, Midnight ratifiers, gates, or token contracts must be treated as external calls.

### 7.3 Auto-Lend flow

1. The monitor discovers a borrower ask.
2. The executor submits the ask and expected limits to the account.
3. The account validates market, maturity, rate, expiry, policy, and live capacity.
4. The account verifies that the LP has no debt in the target market.
5. The account stores the execution context.
6. The account calls `Midnight.take` with the LP as `taker`.
7. Midnight calls `onBuy` on the account.
8. The account checks live `buyerAssets`, dormancy, capacity, and expected credit creation.
9. The account removes exact v4 principal and receives the tokens.
10. The account approves exactly `buyerAssets` to Midnight.
11. Midnight pulls the funds, credits the LP, and records the borrower’s debt.

### 7.4 LP Bid Board flow

1. The LP signs a grouped Midnight `offer.buy == true` offer.
2. The LP is the maker and credit buyer.
3. The Unight Account is the maker callback.
4. The offer contains policy nonce and position epoch data.
5. The Bid Board distributes the offer offchain.
6. A borrower submits the offer directly to Midnight.
7. Midnight validates the offer and ratifier.
8. The account validates callback data, current capacity, dormancy, and economics.
9. The account removes exact v4 principal.
10. Midnight pulls gross `buyerAssets` and creates credit for the LP.

LP bids are public and raceable unless the ratifier binds a specific taker.

## 8. Offer Groups, Expiry, and Cancellation

Each LP Bid Board policy epoch should use explicit Midnight offer groups.

The implementation must track separately:

```text
Unight global committed USDC
Unight per-mode committed USDC
Midnight consumed amount per maker/group
```

The same signed offer maximum must not be counted as reserved capital. Signed offers remain unfilled until Midnight successfully consumes them.

On policy change, position transfer, NFT replacement, or account closure:

1. disable new lending;
2. increment the policy and position epoch;
3. invalidate or consume relevant Midnight groups;
4. clear callback contexts;
5. revoke Midnight authorization;
6. transfer the position only after all checks succeed.

Every new policy epoch must use new callback data and new offer groups.

New-lending offers should satisfy:

```text
offer expiry < market maturity
```

Post-maturity unwinds and liquidations are separate operations, not new lending.

## 9. Offchain Services

### 9.1 Auto-Lend monitor

The monitor:

- discovers borrower asks;
- validates current router policy;
- computes conservative net APR;
- includes settlement and continuous fees;
- checks maturity and offer expiry;
- simulates the complete transaction;
- submits only fresh execution plans;
- supports partial fills and fallback offers.

The monitor is not trusted for authorization or capacity.

### 9.2 LP Bid Board

The Bid Board:

- stores signed offers and ratifier data;
- tracks Midnight group consumption;
- reports estimated current fillability;
- removes expired or invalidated offers from display;
- warns that public bids are copyable and raceable;
- never treats displayed capacity as reserved.

### 9.3 Risk and capacity service

This service reads:

- v4 position state;
- account policy and epoch;
- Midnight market state;
- group consumption;
- current fees;
- credit and debt state;
- dormancy observations.

It provides conservative estimates for UI and simulation only.

## 10. Security Invariants

The implementation must preserve these invariants:

1. Total successful callback funding never exceeds the global USDC cap.
2. Auto-Lend funding never exceeds the Auto-Lend cap.
3. Bid Board funding never exceeds the Bid Board cap.
4. The reactivation reserve is never removed for lending.
5. Every committed amount equals actual gross `buyerAssets` funded by Midnight.
6. Accrued fees and pre-existing balances never enter lendable principal.
7. The LP, not the account, owns the resulting Midnight credit.
8. The account cannot be invoked as a callback by an untrusted contract.
9. A callback cannot run without a valid policy, position epoch, and execution context.
10. A position cannot be lent from after it re-enters range or fails dormancy checks.
11. A stale signed bid cannot use a newer position or policy.
12. No generic account call can reach arbitrary Midnight or PositionManager functions.
13. A zero-asset Midnight fill cannot remove v4 liquidity.
14. Failed settlement leaves both Uniswap and Midnight state unchanged.
15. Capacity is not automatically released merely because credit matured or changed value.

## 11. Implementation Methodology

### Phase 1 — Specification and money map

Document every asset and claim:

```text
v4 principal
v4 fees
USDC withdrawn
Midnight buyerAssets
Midnight sellerAssets
credit units
pending fees
withdrawable USDC
realized losses
```

For each lifecycle, identify who loses money if accounting fails.

### Phase 2 — Pin dependencies

Pin exact deployed versions and addresses for:

- Midnight;
- Midnight interfaces and ratifiers;
- Base USDC;
- Uniswap v4 core;
- v4-periphery;
- PositionManager;
- Guard Hook.

Do not implement against unpinned moving branches.

### Phase 3 — Build the v4 adapter first

Prove position withdrawal independently before integrating Midnight.

Test:

- both USDC currency orderings;
- tick equality and near-boundary states;
- zero liquidity;
- fees and dust;
- exact liquidity-to-asset rounding;
- minimum outputs;
- PositionManager ownership;
- action encoding;
- balance deltas;
- malicious or unsupported hooks.

### Phase 4 — Build the account and policy layer

Implement immutable dependencies, owner custody, policy epochs, caps, reserve, settlement lock, and safe NFT lifecycle.

Do not add arbitrary execution functionality for convenience.

### Phase 5 — Integrate Midnight

Test actual settlement with:

- Auto-Lend asks;
- LP Bid Board offers;
- partial fills;
- settlement fee changes;
- continuous fee caps;
- groups;
- ratifier failures;
- zero-asset fills;
- existing LP debt;
- borrower health failures;
- callback and transfer failures;
- post-maturity states.

### Phase 6 — Build discovery services

Only after onchain policy enforcement is working should the monitor, simulator, and Bid Board be built.

### Phase 7 — Fuzzing and adversarial testing

Use Foundry fork fuzzing and invariant testing for:

- capacity saturation;
- concurrent fills;
- partial fills;
- rounding;
- range manipulation;
- policy invalidation;
- malicious hooks;
- reentrancy;
- stale offers;
- group consumption;
- account migration;
- maturity and bad debt.

Use Medusa and Echidna for deterministic, tool-compatible properties that do
not require Foundry cheatcodes or live protocol state. Keep their reports
separate from the live-fork settlement evidence.

### Phase 8 — Independent security review

The review must cover:

- accounting and solvency;
- callback authority;
- v4 flash accounting and PositionManager actions;
- hook behavior;
- Midnight ratifiers and authorization;
- offer groups;
- market and oracle risk;
- LP credit ownership;
- emergency exit.

## 12. Deployment Plan

Deploy in stages:

1. Local unit and invariant tests.
2. Fork tests against Base, v4, USDC, and Midnight.
3. Testnet with one market and one pool.
4. Small-cap mainnet deployment.
5. Independent monitoring and emergency pause.
6. Gradual addition of markets only after separate risk review.

The first production deployment should have:

- one approved pool;
- one approved Midnight market;
- one maturity band;
- one dormancy mechanism;
- conservative caps;
- no automatic capacity recycling;
- explicit LP loss disclosure.

## 13. Non-Goals

Unight v1 is not:

- a new lending protocol;
- a replacement for Midnight’s risk engine;
- a pre-funded order book;
- a guarantee of double yield;
- a guarantee of immediate repayment;
- a generic AMM aggregator;
- a cross-chain system;
- a protocol that preserves the original LP size after lending.

## 14. Final Implementation Principle

Unight should be built as a constrained, non-upgradeable v4 position-withdrawal adapter around Midnight’s exact buyer-funding semantics.

The essential flow is:

```text
LP-owned v4 position
    → live dormancy and capacity validation
    → exact PositionManager withdrawal
    → authenticated Midnight buy callback
    → gross buyerAssets funding
    → LP-owned Midnight credit
```

The promise is precise:

> Unight atomically converts a valid, currently executable amount of genuinely dormant Uniswap v4 principal into Midnight credit, while retaining the configured residual position and enforcing the LP’s policy.
