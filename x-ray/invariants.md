# Invariant Map

> Unight | 37 guards | 8 inferred | 1 not enforced on-chain

---

## 1. Enforced Guards (Reference)

Per-call preconditions. Heading IDs below (`G-N`) are anchor targets from x-ray.md attack surfaces.

#### G-1
`owner_ == address(0) || address(positionManager_) == address(0) || address(poolManager_) == address(0) || address(midnight_) == address(0) || loanToken_ == address(0) || address(dormancyOracle_) == address(0) || address(registry_) == address(0)` · `src/UnightAccount.sol:150` · prevents deployment with unusable core dependencies.

#### G-2
`!registry_.isPoolApproved(expectedPoolId_)` · `src/UnightAccount.sol:155` · binds a new account to a governance-approved v4 pool.

#### G-3
`!registry_.isDormancyOracleApproved(address(dormancyOracle_))` · `src/UnightAccount.sol:156` · binds terminality proofs to an approved oracle.

#### G-4
`msg.sender != owner` · `src/UnightAccount.sol:174` · restricts owner-controlled account configuration and withdrawals.

#### G-5
`msg.sender != owner && !isExecutor[msg.sender]` · `src/UnightAccount.sol:180` · restricts auto-lend submission to the LP or enabled keepers.

#### G-6
`_execution.state != ExecutionState.Idle` · `src/UnightAccount.sol:186` · blocks policy/lifecycle mutation during active callback context.

#### G-7
`executor == address(0)` · `src/UnightAccount.sol:204` · avoids granting executor status to the zero address.

#### G-8
`!newPolicy.enabled || newPolicy.marketId == bytes32(0)` · `src/UnightAccount.sol:214` · requires an executable policy to name a nonzero Midnight market.

#### G-9
`newPolicy.globalCap == 0 || newPolicy.autoLendCap > newPolicy.globalCap` · `src/UnightAccount.sol:215` · keeps auto-lend capacity inside the account lifetime cap.

#### G-10
`newPolicy.bidBoardCap > newPolicy.globalCap` · `src/UnightAccount.sol:218` · keeps maker-bid capacity inside the account lifetime cap.

#### G-11
`newPolicy.maxLendableBps == 0 || newPolicy.maxLendableBps > BPS` · `src/UnightAccount.sol:219` · bounds the fraction of terminal principal usable for lending.

#### G-12
`newPolicy.tickBuffer > 887_272 || newPolicy.expiry <= block.timestamp` · `src/UnightAccount.sol:222` · rejects impossible tick buffers and already-expired policies.

#### G-13
`newPolicy.bidBoardCap > 0 && bidRatifier == address(0)` · `src/UnightAccount.sol:225` · disables bid-board capacity unless a ratifier exists.

#### G-14
`!registry.isMarketApproved(newPolicy.marketId)` · `src/UnightAccount.sol:226` · requires the selected Midnight market to be approved.

#### G-15
`market.chainId != block.chainid || market.midnight != address(midnight) || market.loanToken != loanToken || market.maturity <= block.timestamp || newPolicy.expiry >= market.maturity` · `src/UnightAccount.sol:229` · binds policy market metadata to the current chain, Midnight instance, token, and maturity.

#### G-16
`!closed` · `src/UnightAccount.sol:270` · requires account closure before returning the v4 NFT.

#### G-17
`midnight.credit(policy.marketId, owner) != 0 || midnight.debt(policy.marketId, owner) != 0` · `src/UnightAccount.sol:271` · prevents NFT withdrawal while the selected Midnight position is live.

#### G-18
`!policy.enabled || closed || block.timestamp > policy.expiry` · `src/UnightAccount.sol:327` · stops auto-lend after policy expiry, closure, or disablement.

#### G-19
`units == 0 || maxBuyerAssets == 0 || minUnits > units || deadline < block.timestamp || deadline > offer.expiry` · `src/UnightAccount.sol:328` · bounds auto-lend offer size and callback deadline.

#### G-20
`offer.buy || offer.maker == address(0)` · `src/UnightAccount.sol:332` · accepts only borrower sell offers with a maker.

#### G-21
`offer.callback != address(0) || offer.callbackData.length != 0` · `src/UnightAccount.sol:333` · prevents auto-lend offers from supplying their own callback.

#### G-22
`!registry.isRatifierApproved(offer.ratifier)` · `src/UnightAccount.sol:334` · requires auto-lend offer ratifier approval.

#### G-23
`!_marketMatchesPolicy(offer.market)` · `src/UnightAccount.sol:335` · rejects offers outside the active policy market.

#### G-24
`offer.expiry > policy.expiry || offer.expiry > offer.market.maturity` · `src/UnightAccount.sol:336` · keeps offer validity inside policy expiry and market maturity.

#### G-25
`midnight.credit(policy.marketId, offer.maker) != 0` · `src/UnightAccount.sol:337` · rejects auto-lend makers already carrying credit in the policy market.

#### G-26
`midnight.debt(policy.marketId, owner) != 0` · `src/UnightAccount.sol:338` · prevents new credit settlement while owner debt exists.

#### G-27
`maxBuyerAssets > remainingCapacity()` · `src/UnightAccount.sol:339` · caps auto-lend by live terminal principal and per-mode limits.

#### G-28
`!midnight.isAuthorized(owner, address(this))` · `src/UnightAccount.sol:340` · requires Midnight authorization before account-funded settlement.

#### G-29
`msg.sender != bidRatifier || bidRatifier == address(0)` · `src/UnightAccount.sol:389` · restricts explicit maker-bid context registration to the configured ratifier.

#### G-30
`!policy.enabled || closed || block.timestamp > policy.expiry` · `src/UnightAccount.sol:390` · stops maker-bid context setup after policy expiry, closure, or disablement.

#### G-31
`!_marketMatchesPolicy(market) || maxAssets == 0` · `src/UnightAccount.sol:391` · binds maker-bid context to the active policy market and nonzero size.

#### G-32
`maxAssets > remainingBidCapacity()` · `src/UnightAccount.sol:392` · caps maker-bid context by global and bid-board limits.

#### G-33
`midnight.debt(policy.marketId, owner) != 0` · `src/UnightAccount.sol:393` · prevents maker-bid settlement while owner debt exists.

#### G-34
`callbackPolicyNonce != policyNonce || callbackPositionEpoch != positionEpoch || minUnits == 0 || deadline < block.timestamp` · `src/UnightAccount.sol:397` · prevents stale callback data from surviving policy or position changes.

#### G-35
`msg.sender != address(midnight)` · `src/UnightAccount.sol:440` · restricts buy callbacks to the canonical Midnight contract.

#### G-36
`id != context.marketId || buyer != context.expectedBuyer || MarketId.hash(market) != context.marketHash || keccak256(data) != context.callbackDataHash || context.policyNonce != policyNonce || context.positionEpoch != positionEpoch || buyerAssets == 0 || buyerAssets > context.maxBuyerAssets || units < context.minUnits` · `src/UnightAccount.sol:460` · binds callback settlement to the committed offer, market, buyer, nonce, epoch, cap, and units.

#### G-37
`afterBalance < beforeBalance || afterBalance - beforeBalance < requiredAmount` · `src/libraries/V4TerminalPositionAdapter.sol:158` · proves the v4 unwind delivered enough loan tokens to the account.

## 2. Inferred Invariants (Single-Contract)

#### I-1

`Conservation` · On-chain: **Yes**

> `committedBuyerAssets` increases with exactly one mode counter for every successful `onBuy`.

**Derivation** — delta-pair: `committedBuyerAssets += buyerAssets` at `src/UnightAccount.sol:478` paired with either `autoLendBuyerAssets += buyerAssets` at `src/UnightAccount.sol:481` or `bidBoardBuyerAssets += buyerAssets` at `src/UnightAccount.sol:484`.

**If violated** — mode caps and global cap would no longer describe the same committed settlement history.

#### I-2

`Bound` · On-chain: **Yes**

> `policy.autoLendCap <= policy.globalCap` and `policy.bidBoardCap <= policy.globalCap` for every stored policy.

**Derivation** — guard-lift: `src/UnightAccount.sol:215` and `src/UnightAccount.sol:218`; the only `policy = newPolicy` write is `src/UnightAccount.sol:234`, while `disablePolicy`/`close` only set `policy.enabled = false`.

**If violated** — per-mode remaining-capacity calculations could exceed the lifetime cap.

#### I-3

`Bound` · On-chain: **Yes**

> `policy.maxLendableBps` is nonzero and at most `10_000` for every enabled stored policy.

**Derivation** — guard-lift: `newPolicy.maxLendableBps == 0 || newPolicy.maxLendableBps > BPS` at `src/UnightAccount.sol:219`; only full-policy write is `src/UnightAccount.sol:234`.

**If violated** — `remainingCapacity` could lend more than terminal principal policy permits.

#### I-4

`Temporal` · On-chain: **Yes**

> New executions require both the account policy and callback deadline to be live.

**Derivation** — temporal: `block.timestamp > policy.expiry` at `src/UnightAccount.sol:327`, `src/UnightAccount.sol:390`, `src/UnightAccount.sol:452`, plus `deadline < block.timestamp` at `src/UnightAccount.sol:328`, `src/UnightAccount.sol:397`, `src/UnightAccount.sol:455`.

**If violated** — stale policy or callback data could settle after the LP's intended execution window.

#### I-5

`StateMachine` · On-chain: **Yes**

> A callback context is opened from `Idle`, must be consumed by `onBuy`, and is deleted after token approval.

**Derivation** — edge: `Idle@src/UnightAccount.sol:186` -> `AutoLend@src/UnightAccount.sol:346` or `MakerBid@src/UnightAccount.sol:402`, then `delete _execution` at `src/UnightAccount.sol:489`.

**If violated** — a callback context could be reused across offers, policies, or position epochs.

#### I-6

`StateMachine` · On-chain: **No**

> `closed` is one-way: the account can close, but no function reopens it.

**Derivation** — edge: `closed=false` -> `closed=true` at `src/UnightAccount.sol:254`; write-site enumeration finds no `closed = false`, but constructor default is implicit rather than guarded by a runtime edge.

**If violated** — lifecycle assumptions around `withdrawPosition` and `sweepLoanToken` would need re-checking after reopen.

#### I-7

`Ratio` · On-chain: **Yes**

> `remainingCapacity` is bounded by the minimum of terminal-principal reserve, lendable BPS, global cap, and auto-lend cap.

**Derivation** — ratio/min formula at `src/UnightAccount.sol:288` through `src/UnightAccount.sol:296`.

**If violated** — auto-lend could allocate beyond the LP's terminal-liquidity policy envelope.

#### I-8

`Conservation` · On-chain: **Yes**

> A v4 unwind must increase account loan-token balance by at least the required Midnight buyer assets.

**Derivation** — balance-delta check: `beforeBalance` at `src/libraries/V4TerminalPositionAdapter.sol:155`, `modifyLiquidities` at `src/libraries/V4TerminalPositionAdapter.sol:156`, `afterBalance - beforeBalance < requiredAmount` at `src/libraries/V4TerminalPositionAdapter.sol:158`.

**If violated** — the account could approve Midnight without receiving the required loan-token funding.

## 3. Inferred Invariants (Cross-Contract)

#### X-1

On-chain: **Yes**

> Account policy assumes the registry's approved pool, market, ratifier, and oracle mappings are the canonical allowlists.

**Caller side** — `src/UnightAccount.sol:155`, `src/UnightAccount.sol:226`, `src/UnightAccount.sol:334`, `src/UnightAccount.sol:156` — constructor, policy setup, and offer checks consume registry approvals.

**Callee side** — `src/UnightPolicyRegistry.sol:40`, `src/UnightPolicyRegistry.sol:46`, `src/UnightPolicyRegistry.sol:52`, `src/UnightPolicyRegistry.sol:58` — owner can update each allowlist.

**If violated** — accounts can accept a pool, market, ratifier, or oracle outside the intended governance set.

#### X-2

On-chain: **Yes**

> `registerBidContext` is expected to be called only after the bid ratifier has verified maker, callback, ratifier, and base authorization.

**Caller side** — `src/UnightBidRatifier.sol:49` through `src/UnightBidRatifier.sol:56` — ratifier checks Midnight caller, base ratifier success, offer shape, maker, callback, ratifier, max assets, and maturity.

**Callee side** — `src/UnightAccount.sol:389` through `src/UnightAccount.sol:417` — account accepts only the configured ratifier and stores the bid context.

**If violated** — maker-bid callback data could be installed without the expected static ratification path.

## 4. Economic Invariants

#### E-1

On-chain: **Yes**

> Gross buyer assets committed by an account remain inside the LP's selected global and mode caps.

**Follows from** — `I-1` + `I-2` + `I-7`

**If violated** — the LP's configured capacity envelope would not match actual settlement accounting.
