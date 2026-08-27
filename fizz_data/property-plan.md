# Property Plan

> Generated from five specialized discovery passes, the x-ray reports, and the
> generated `test/fizz` suite. 30 feasible properties: 27 HIGH, 3 MEDIUM, 0
> LOW. Guarantee distribution: 21 SHOULD-HOLD and 9 EXPLORATORY. All
> properties are retained in automatic mode.

## Global Properties (public, checked by fuzzer after every call)

| Spec ID | Function Name | Property | Category | Guarantee | Evidence | Priority |
|---|---|---|---|---|---|---|
| GL-01 | property_modeAccounting | `committedBuyerAssets == autoLendBuyerAssets + bidBoardBuyerAssets` | HIGH_LEVEL | SHOULD-HOLD | Exact `onBuy` update identity | HIGH |
| GL-02 | property_globalCap | committed assets do not exceed `policy.globalCap` | HIGH_LEVEL | EXPLORATORY | — | HIGH |
| GL-03 | property_autoLendCap | Auto-Lend assets do not exceed `policy.autoLendCap` | HIGH_LEVEL | EXPLORATORY | — | HIGH |
| GL-04 | property_bidBoardCap | Bid Board assets do not exceed `policy.bidBoardCap` | HIGH_LEVEL | EXPLORATORY | — | HIGH |
| GL-05 | property_countersMonotonic | Four settlement counters never decrease | VARIABLE_TRANSITION | SHOULD-HOLD | Counters have increment-only writes | HIGH |
| GL-06 | property_principalCoversCommitment | Principal removed covers successful committed assets | HIGH_LEVEL | EXPLORATORY | — | HIGH |
| GL-07 | property_closedCapacityZero | Closed accounts expose zero capacity | VALID_STATE | SHOULD-HOLD | Explicit `closed` early return in both views | HIGH |
| GL-08 | property_disabledCapacityZero | Disabled accounts expose zero capacity | VALID_STATE | SHOULD-HOLD | Explicit `!policy.enabled` early return in both views | HIGH |
| GL-09 | property_epochsMonotonic | Policy and position epochs never decrease | VARIABLE_TRANSITION | SHOULD-HOLD | Epochs increment on policy/lifecycle transitions | MEDIUM |
| GL-10 | property_idleContextClean | Idle execution context has no committed context | VALID_STATE | SHOULD-HOLD | Successful settlement deletes `_execution` | HIGH |
| GL-11 | property_factoryMappingMatchesPrediction | Factory mapping agrees with CREATE2 prediction | HIGH_LEVEL | SHOULD-HOLD | Same salt and init code are used | HIGH |
| GL-12 | property_policyCapsValid | Both mode caps are no greater than the global cap | VALID_STATE | SHOULD-HOLD | Explicit `setPolicy` guards | HIGH |
| GL-13 | property_successAccountingPair | A mode increment has the same global increment | STATE_TRANSITION | SHOULD-HOLD | Both writes use `buyerAssets` | HIGH |
| GL-14 | property_exactMidnightAllowance | Midnight allowance is exact after settlement | HIGH_LEVEL | SHOULD-HOLD | `_approveExact` clears and sets exact amount | HIGH |

## Specific Properties (internal, called after relevant handlers)

| Spec ID | Function Name | Property | Category | Guarantee | Evidence | Called After | Priority |
|---|---|---|---|---|---|---|---|
| SP-01 | property_policyInstalled | Policy equals input and nonce increments once | STATE_TRANSITION | SHOULD-HOLD | Explicit `setPolicy` postcondition | `unightAccount_setPolicy` | HIGH |
| SP-02 | property_policyDisabled | Policy is disabled and nonce increments once | STATE_TRANSITION | SHOULD-HOLD | Explicit `disablePolicy` postcondition | `unightAccount_disablePolicy` | HIGH |
| SP-03 | property_executorIsolation | Executor update does not alter unrelated state | STATE_TRANSITION | EXPLORATORY | — | `unightAccount_setExecutor` | MEDIUM |
| SP-04 | property_accountClosed | Close disables policy, advances epochs, and revokes authorization | STATE_TRANSITION | SHOULD-HOLD | Explicit `close` postcondition | `unightAccount_close` | HIGH |
| SP-05 | property_positionWithdrawn | Eligible close-only withdrawal returns the NFT and advances position epoch | STATE_TRANSITION | SHOULD-HOLD | Explicit withdrawal guards and writes | `unightAccount_withdrawPosition` | HIGH |
| SP-06 | property_factoryCreation | Creation binds owner/position and duplicate pair reverts | STATE_TRANSITION | SHOULD-HOLD | Constructor args and `AccountExists` guard | `unightAccountFactory_createAccount` | HIGH |
| SP-07 | property_bidContextBound | Bid context records exact offer, taker, limits, deadline, and epochs | STATE_TRANSITION | SHOULD-HOLD | `_execution` initialization | `unightAccount_registerBidContext` | HIGH |
| SP-08 | property_callbackSettlement | Successful callback updates accounting, allowance, principal, and cleanup exactly | STATE_TRANSITION | SHOULD-HOLD | Explicit `onBuy` postconditions | `unightAccount_onBuy` | HIGH |
| SP-09 | property_callbackRollback | Rejected callback is state-preserving | STATE_TRANSITION | EXPLORATORY | — | negative `unightAccount_onBuy` cases | HIGH |
| SP-10 | property_autoLendSettlement | Successful Auto-Lend changes only Auto-Lend/global settlement accounting | STATE_TRANSITION | SHOULD-HOLD | Auto-Lend branch and debt guard | `unightAccount_takeAutoLend` | HIGH |
| SP-11 | property_autoLendRejections | Invalid Auto-Lend inputs revert without state changes | VALID_STATE | SHOULD-HOLD | Explicit input and authorization guards | negative `unightAccount_takeAutoLend` cases | HIGH |
| SP-12 | property_bidRejections | Invalid bid callback state or commitments revert without state changes | VALID_STATE | SHOULD-HOLD | Explicit callback guards | negative bid callback cases | HIGH |
| SP-13 | property_registryAccess | Only registry owner can update one approval at a time | STATE_TRANSITION | SHOULD-HOLD | `onlyOwner` and single-map writes | registry setter handlers | HIGH |
| SP-14 | property_partialFillCaps | Repeated partial fills stay within caps and pre-fill capacity | HIGH_LEVEL | EXPLORATORY | — | successful settlement sequences | HIGH |
| SP-15 | property_groupReplayResistance | Consumed/cancelled offer groups cannot settle again | STATE_TRANSITION | EXPLORATORY | — | ratifier/take sequences | HIGH |
| SP-16 | property_roundingAndBounds | Math is monotonic for zero/sub-unit inputs and narrow fields do not wrap | VARIABLE_TRANSITION | EXPLORATORY | — | parameterized math/settlement sequences | MEDIUM |

## Ghost Variable Plan

| Ghost Variable | Type | Updated In | Used By |
|---|---|---|---|
| `lastCommittedBuyerAssets` | `uint256` | successful callback observation | GL-05, GL-06, GL-13, SP-08 |
| `lastAutoLendBuyerAssets` | `uint256` | successful Auto-Lend observation | GL-03, GL-13, SP-10 |
| `lastBidBoardBuyerAssets` | `uint256` | successful Bid Board observation | GL-04, GL-13, SP-08 |
| `lastV4PrincipalRemoved` | `uint256` | successful callback observation | GL-05, GL-06, SP-08 |
| `successfulSettlementCount` | `uint256` | successful settlement handlers | SP-14 |
| `lastPolicyNonce` | `uint256` | policy/lifecycle handlers | GL-09, SP-01, SP-02, SP-04 |
| `lastPositionEpoch` | `uint256` | lifecycle handlers | GL-09, SP-04, SP-05 |

## Snapshot State Plan

| State Variable | Type | Source | Used By |
|---|---|---|---|
| `policy` | `UnightPolicy` | `account.policy()` | GL-02–GL-04, GL-08, GL-12, SP-01, SP-02 |
| `committedBuyerAssets` | `uint256` | `account.committedBuyerAssets()` | GL-01, GL-02, GL-05, GL-06, GL-13, SP-08–SP-14 |
| `autoLendBuyerAssets` | `uint256` | `account.autoLendBuyerAssets()` | GL-01, GL-03, GL-05, GL-13, SP-10, SP-14 |
| `bidBoardBuyerAssets` | `uint256` | `account.bidBoardBuyerAssets()` | GL-01, GL-04, GL-05, GL-13, SP-08, SP-14 |
| `v4PrincipalRemoved` | `uint256` | `account.v4PrincipalRemoved()` | GL-05, GL-06, SP-08 |
| `policyNonce` | `uint256` | `account.policyNonce()` | GL-09, SP-01, SP-02, SP-04, SP-07 |
| `positionEpoch` | `uint256` | `account.positionEpoch()` | GL-09, SP-04, SP-05, SP-07 |
| `closed` | `bool` | `account.closed()` | GL-07, SP-04, SP-05 |
| `execution` | `ExecutionContext` | `account.executionContext()` | GL-10, SP-07–SP-12 |
| `midnightAllowance` | `uint256` | loan-token `allowance(account, midnight)` | GL-14, SP-08, SP-09 |
| `factoryAccount` | `address` | `factory.accountOf(owner, positionId)` | GL-11, SP-06 |

## Handler Wiring Plan

| Handler | Snapshot before/after | Ghost updates | Specific properties |
|---|---|---|---|
| `UnightAccountHandler` policy/lifecycle methods | YES | epochs and policy snapshots | SP-01–SP-05 |
| `UnightAccountHandler` Auto-Lend methods | YES; fork fixture required | settlement counters and allowance | SP-10, SP-11, SP-14 |
| `UnightAccountHandler` bid-context/callback methods | YES; fork fixture required | settlement counters and context state | SP-07–SP-09, SP-12, SP-14 |
| `UnightAccountFactoryHandler` | YES | factory mapping observation | SP-06 |
| `UnightPolicyRegistryHandler` | YES | approval observation | SP-13 |
| dedicated `offerGroup` sequence handler | YES | consumed-group baseline | SP-15 |
| dedicated `roundTrip`/boundary handler | YES | conversion and fill baselines | SP-16 |

## Feasibility Notes

- `UnightBidRatifier` has no state-changing ABI and is therefore exercised
  through account callback/take paths, not as a standalone handler.
- Settlement properties require the existing live Midnight and Uniswap v4
  addresses, the pinned Base fork block, a valid dormant terminal position,
  and the production ratifier fixture. Arbitrary generated structs alone are
  not valid live settlement inputs.
- Rollback properties must compare all listed snapshots after an expected
  revert. Do not update ghosts until the outer call succeeds.
- The x-ray report identifies `remainingBidCapacity()` as not explicitly
  bounded by live terminal principal; GL-06/SP-14 therefore remain important
  exploratory checks rather than assumed guarantees.
