# Invariant Map

> Unight | 17 guards | 11 inferred | 4 not enforced on-chain

## 1. Enforced Guards (Reference)

#### G-1
`owner_ == address(0) || address(positionManager_) == address(0) || address(poolManager_) == address(0) || address(midnight_) == address(0) || loanToken_ == address(0) || address(dormancyOracle_) == address(0) || address(registry_) == address(0)` · `UnightAccount.sol:148-153` · prevents an account from being initialized with unusable critical dependencies.

#### G-2
`!registry_.isPoolApproved(expectedPoolId_)` · `UnightAccount.sol:155` · binds the account to an allowlisted v4 pool.

#### G-3
`!registry_.isDormancyOracleApproved(address(dormancyOracle_))` · `UnightAccount.sol:157-159` · prevents use of an unapproved historical-state oracle.

#### G-4
`msg.sender != owner` · `UnightAccount.sol:174` · restricts account administration to the immutable LP owner.

#### G-5
`msg.sender != owner && !isExecutor[msg.sender]` · `UnightAccount.sol:180` · restricts Auto-Lend submission to the LP or its approved executor.

#### G-6
`_execution.state != ExecutionState.Idle` · `UnightAccount.sol:186` · prevents policy and lifecycle mutation during settlement.

#### G-7
`!newPolicy.enabled || newPolicy.marketId == bytes32(0)` · `UnightAccount.sol:214` · prevents installation of an unusable policy.

#### G-8
`newPolicy.globalCap == 0 || newPolicy.autoLendCap > newPolicy.globalCap` · `UnightAccount.sol:215-217` · preserves the global-cap relationship for configured Auto-Lend capacity.

#### G-9
`newPolicy.bidBoardCap > newPolicy.globalCap` · `UnightAccount.sol:218` · preserves the global-cap relationship for configured Bid Board capacity.

#### G-10
`market.chainId != block.chainid || market.midnight != address(midnight) || market.loanToken != loanToken || market.maturity <= block.timestamp || newPolicy.expiry >= market.maturity` · `UnightAccount.sol:229-232` · binds policy execution to the canonical live market before maturity.

#### G-11
`offer.callback != address(0) || offer.callbackData.length != 0` · `UnightAccount.sol:333` · ensures Auto-Lend takes a borrower offer without a maker callback.

#### G-12
`offer.expiry > policy.expiry || offer.expiry > offer.market.maturity` · `UnightAccount.sol:336` · prevents execution beyond the policy or market lending horizon.

#### G-13
`msg.sender != bidRatifier || bidRatifier == address(0)` · `UnightAccount.sol:389` · restricts maker-bid context creation to the configured ratifier.

#### G-14
`msg.sender != address(midnight)` · `UnightAccount.sol:440` · makes Midnight the sole callback authority.

#### G-15
`buyerAssets == 0 || buyerAssets > context.maxBuyerAssets || units < context.minUnits` · `UnightAccount.sol:461-465` · prevents zero, over-cap, or under-minimum callback settlement.

#### G-16
`market.maturity <= block.timestamp || block.timestamp > context.deadline` · `UnightAccount.sol:466` · prevents callback settlement after maturity or deadline.

#### G-17
`afterBalance < beforeBalance || afterBalance - beforeBalance < requiredAmount` · `V4TerminalPositionAdapter.sol:155-159` · requires the constrained v4 withdrawal to produce sufficient loan-token output.

## 2. Inferred Invariants (Single-Contract)

#### I-1
**Category** · On-chain: **Yes**

**Claim**: `committedBuyerAssets` increases by the same successful callback gross amount used to increase one mode-specific counter.

**Derivation** — Δ-pair: `UnightAccount.sol:478-485`.

**If violated** — global and mode accounting diverge.

#### I-2
**Category** · On-chain: **Yes**

**Claim**: `policyNonce` changes whenever policy is installed or disabled, invalidating callback data tied to the previous policy.

**Derivation** — edge: `policyNonce@236 → policyNonce+1`, `policyNonce@245 → policyNonce+1`.

**If violated** — stale policy commitments could remain valid.

#### I-3
**Category** · On-chain: **Yes**

**Claim**: `positionEpoch` changes on account close and position withdrawal, invalidating position-bound callback data.

**Derivation** — edge: `positionEpoch@258 → positionEpoch+1`, `positionEpoch@275 → positionEpoch+1`.

**If violated** — a prior position lifecycle could be reused.

#### I-4
**Category** · On-chain: **Yes**

**Claim**: Closed accounts cannot execute new settlement or report nonzero capacity.

**Derivation** — guard-lift: `!policy.enabled || closed` at `UnightAccount.sol:327`, `390`, `452`; all writes to `closed` are `close()` at `254-255` and no reverse write exists.

**If violated** — closed account state could continue funding credit.

#### I-5
**Category** · On-chain: **Yes**

**Claim**: A successful callback leaves the stored execution context idle.

**Derivation** — Δ-pair/state cleanup: context is created at `UnightAccount.sol:346-360` or `402-417` and deleted at `489`; successful `onBuy` returns only after deletion.

**If violated** — future lifecycle calls could be blocked or context reused.

#### I-6
**Category** · On-chain: **No**

**Claim**: Bid Board capacity is bounded by both policy caps and currently available terminal v4 principal.

**Derivation** — guard-lift: `maxAssets > remainingBidCapacity()` at `UnightAccount.sol:392` and `453`; `remainingBidCapacity()` writes no terminal-principal check at `300-304`, while Auto-Lend performs the terminal-principal check through `remainingCapacity()` at `284-298`.

**If violated** — a bid can pass the pre-check and fail only after the callback reaches the adapter.

## 3. Inferred Invariants (Cross-Contract)

#### X-1
On-chain: **Yes**

**Claim**: The account assumes PositionManager withdrawal increases its loan-token balance by at least the requested amount.

**Caller side** — `V4TerminalPositionAdapter.sol:155-159` — compares before/after ERC20 balance around `modifyLiquidities()`.

**Callee side** — `V4TerminalPositionAdapter.sol:146-153` — fixes actions to decrease liquidity and take the pair to the account.

**If violated** — the transaction reverts before accounting or approval remains effective.

#### X-2
On-chain: **Yes**

**Claim**: Only the configured Midnight callback can transition settlement accounting.

**Caller side** — `UnightAccount.sol:440-465` — rejects non-Midnight callers and validates callback context.

**Callee side** — `UnightAccount.sol:363-364` and `UnightAccount.sol:457-458` — Midnight is the configured external caller for Auto-Lend and callback-side Bid Board flow.

**If violated** — an unauthorized contract could attempt to create credit-backed accounting.

#### X-3
On-chain: **No**

**Claim**: Midnight credit/debt and fee reads remain consistent with the account’s settlement assumptions for all external state transitions.

**Caller side** — `UnightAccount.sol:337-340`, `393`, `467-470` — account gates on credit, debt, continuous fee, settlement fee, and maturity.

**Callee side** — `UnightAccount.sol:260-261` invokes Midnight authorization mutation, while all credit/debt/fee state is maintained externally and has no in-scope writer enumeration.

**If violated** — the account’s local checks may not describe every live Midnight transition.

## 4. Economic Invariants

#### E-1
On-chain: **Yes**

**Claim**: Successful account accounting is monotonic within a transaction: gross committed assets and principal removed are increased only after a successful constrained v4 withdrawal.

**Follows from** — `I-1` + `X-1`.

**If violated** — accounting could claim funding without the corresponding v4 output.

#### E-2
On-chain: **No**

**Claim**: Total successful lending should not exceed global cap, mode cap, or lendable terminal principal.

**Follows from** — `I-1` + `I-6`.

**If violated** — Bid Board capacity may admit more nominal funding than the remaining terminal principal can support.
