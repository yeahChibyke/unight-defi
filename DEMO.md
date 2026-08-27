# Unight Hookathon Demonstration

This document defines the reproducible demonstration paths for the current Unight integration. Both paths execute against a pinned Base mainnet fork with live Uniswap v4, Midnight, USDC, and cbBTC contracts.

## Preparation

```bash
cp .env.example .env
# Set BASE_RPC_URL in .env
set -a; source .env; set +a
forge build
forge test
```

The test harness pins Base block `50,000,000`, uses the documented live LP position, and deploys a fresh Unight registry, account factory, account, and controllable dormancy oracle for each test. Live protocol state is preserved; only the account-side integration fixtures and fork state mutations are local to the test.

## Path 1: Auto-Lend

Run:

```bash
forge test --match-contract BaseForkAutoLendTest --match-test testForkAutoLendSettlesLiveBorrowerOffer -vvvv
```

The path is:

```text
LP position → Unight account → live terminal v4 liquidity
                                   ↓
Borrower sell offer → SetterRatifier → Midnight take
                                   ↓
                         USDC proceeds + borrower debt
```

The test proves that:

1. The LP position is held by the Unight account.
2. The borrower supplies live cbBTC collateral to Midnight.
3. The exact borrower offer is authorized by the deployed SetterRatifier.
4. The account removes only the required terminal v4 liquidity.
5. Midnight increases borrower debt and LP credit.
6. The borrower receives USDC.
7. Account accounting increases by the exact gross buyer assets.
8. The callback context is cleared and the Midnight allowance returns to zero.

## Path 2: LP Bid Board

Run:

```bash
forge test --match-contract BaseForkBidBoardTest --match-test testLiveLpBidBoardSettlement -vvvv
```

The path is:

```text
LP maker bid → live SetterRatifier authorization → Midnight take
       borrower collateral and debt ← Unight callback
                                      ↓
                         terminal v4 liquidity → USDC funding
```

The focused suite also demonstrates:

| Behavior | Test coverage |
|---|---|
| Successful settlement | `testLiveLpBidBoardSettlement` |
| Partial fills | `testPartialFillsConsumeOneOfferGroupIncrementally` |
| Group cancellation | `testCancelledOfferGroupRevertsAndRollsBack` |
| Group isolation | `testCancellationIsScopedToItsOfferGroup` |
| Settlement fees | `testNonzeroSettlementFeeIsSettledAndAccounted` |
| Continuous fees | `testNonzeroContinuousFeeAccruesOnLiveCredit` |
| Fee-cap failure | `testSettlementFeeCapFailureRollsBack` |
| Callback/v4 rollback | `testCallbackFailureRollsBackAllSettlementState` |
| Borrower health failure | `testUnhealthyBorrowerRevertsAndRollsBack` |
| Market maturity | `testLiveMidnightRejectsBidAtMarketMaturity` |
| Offer expiry | `testExpiredBidIsRejectedByLiveMidnight` |

For the successful path, inspect the verbose trace for live `Midnight.take`, static offer-ratifier validation, Unight callback execution, v4 position liquidity reduction, USDC transfer, and Midnight LP credit and borrower debt changes.

For rollback paths, assertions verify that failed transactions leave v4 liquidity, Midnight credit/debt, offer-group consumption, Unight accounting, and callback state unchanged.

## Full evidence run

```bash
forge test -vv
```

The expected result is 55 passing Foundry tests. The suite covers custody, policy, adapter, callback, ratifier, Auto-Lend, LP Bid Board, and fork-backed fuzz behavior.

## Scope of this demonstration

The demonstration proves the live settlement mechanics and the account’s policy and rollback boundaries. The fork uses a local account/registry fixture and Foundry state controls to create repeatable LP, borrower, fee, tick, health, and time conditions. It does not represent a production deployment transaction or replace the subsequent deployment, monitoring, and security-review stages. Standalone Medusa and Echidna checks cover deterministic property models; they do not replace these live fork tests.
