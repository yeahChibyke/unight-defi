# Entry Point Map

> Unight | 16 entry points | 1 permissionless | 3 role-gated | 12 admin/configuration

---

## Protocol Flow Paths

### Deployment

`UnightPolicyRegistry.constructor()` -> `setPoolApproval()` / `setMarketApproval()` / `setRatifierApproval()` / `setDormancyOracleApproval()`

`UnightAccountFactory.constructor()` -> `createAccount()` -> `UnightAccount.constructor()` <-- pool and oracle must already be approved

### Owner Setup

`[deployment above]` -> `UnightAccount.setPolicy()` <-- market approved, policy live before maturity

`[owner setup above]` -> `UnightAccount.setExecutor()` -> `takeAutoLend()`

### Auto-Lend

`[owner setup above]` -> `Midnight.setIsAuthorized()` <-- external authorization by owner

`[executor setup above]` -> `takeAutoLend()` -> `Midnight.take()` -> `UnightAccount.onBuy()` -> `V4TerminalPositionAdapter.removeForFunding()` -> `IPositionManager.modifyLiquidities()`

### Maker Bid

`[owner setup above]` -> LP maker offer with `UnightBidRatifier` and account callback

`Borrower takes offer` -> `UnightBidRatifier.isRatified()` -> `UnightAccount.registerBidContext()` or `UnightAccount.onBuy()` idle-path context open -> `V4TerminalPositionAdapter.removeForFunding()`

### Closure

`[settlement flows above]` -> `close()` -> `withdrawPosition()` <-- selected Midnight credit and debt must be zero

`[closure above]` -> `sweepLoanToken()` <-- selected Midnight credit and debt must be zero

## Permissionless

### `UnightAccountFactory.createAccount()`

| Aspect | Detail |
|--------|--------|
| Visibility | external |
| Caller | Anyone deploying for an LP/position pair |
| Parameters | `owner_` (user-controlled), `positionId` (user-controlled), `loanToken` (user-controlled), `expectedPoolId` (user-controlled), `dormancyOracle` (user-controlled), `bidRatifier` (user-controlled) |
| Call chain | `UnightAccountFactory.createAccount()` -> `UnightAccount.constructor()` -> `UnightPolicyRegistry.isPoolApproved()` / `isDormancyOracleApproved()` |
| State modified | `accountOf[owner_][positionId]` |
| Value flow | None |
| Reentrancy guard | no |

## Role-Gated

### `owner or enabled executor`

#### `UnightAccount.takeAutoLend()`

| Aspect | Detail |
|--------|--------|
| Visibility | external, `onlyExecutor idle` |
| Caller | LP owner or enabled keeper |
| Parameters | `offer` (user-signed), `ratifierData` (user-signed), `units` (keeper-provided), `maxBuyerAssets` (keeper-provided), `minUnits` (keeper-provided), `deadline` (keeper-provided) |
| Call chain | `takeAutoLend()` -> `Midnight.take()` -> `onBuy()` -> `V4TerminalPositionAdapter.removeForFunding()` -> `IPositionManager.modifyLiquidities()` -> `IERC20.approve()` |
| State modified | `_execution`, then `committedBuyerAssets`, `autoLendBuyerAssets`, `v4PrincipalRemoved`, `_execution` deleted |
| Value flow | loan token from v4 position to account, then exact allowance to Midnight |
| Reentrancy guard | no; `idle` gates context setup and callback reuse |

### `configured bidRatifier`

#### `UnightAccount.registerBidContext()`

| Aspect | Detail |
|--------|--------|
| Visibility | external, `idle`, internal caller check |
| Caller | configured `bidRatifier` only |
| Parameters | `offerHash` (protocol-derived), `market` (protocol-derived), `taker` (protocol-derived), `maxAssets` (protocol-derived), `deadline` (protocol-derived), `callbackData` (user-signed/protocol-derived) |
| Call chain | `UnightBidRatifier.isRatified()` -> `UnightAccount.registerBidContext()` |
| State modified | `_execution` |
| Value flow | None |
| Reentrancy guard | no; `idle` requires no active context |

### `Midnight`

#### `UnightAccount.onBuy()`

| Aspect | Detail |
|--------|--------|
| Visibility | external, internal caller check |
| Caller | canonical Midnight contract |
| Parameters | `id` (protocol-derived), `market` (protocol-derived), `buyerAssets` (protocol-derived), `units` (protocol-derived), `pendingFeeIncrease` (protocol-derived), `buyer` (protocol-derived), `data` (user-signed/protocol-derived) |
| Call chain | `onBuy()` -> `_openBidContext()` if idle -> `V4TerminalPositionAdapter.removeForFunding()` -> `IPositionManager.modifyLiquidities()` -> `_approveExact()` |
| State modified | `_execution`, `committedBuyerAssets`, `autoLendBuyerAssets` or `bidBoardBuyerAssets`, `v4PrincipalRemoved` |
| Value flow | loan token from v4 position to account; exact allowance to Midnight |
| Reentrancy guard | no; caller and context commitments are checked |

## Admin / Configuration

| Contract | Function | Parameters | State Modified |
|----------|----------|------------|----------------|
| `UnightAccount` | `setExecutor()` | `executor`, `enabled` | `isExecutor[executor]` |
| `UnightAccount` | `setPolicy()` | `newPolicy` | `policy`, `policyNonce` |
| `UnightAccount` | `disablePolicy()` | none | `policy.enabled`, `policyNonce` |
| `UnightAccount` | `close()` | none | `closed`, `policy.enabled`, `policyNonce`, `positionEpoch`; may revoke Midnight authorization |
| `UnightAccount` | `withdrawPosition()` | none | `positionEpoch`; transfers position NFT to owner |
| `UnightAccount` | `sweepLoanToken()` | `amount`, `recipient` | none; transfers residual loan tokens |
| `UnightPolicyRegistry` | `setPoolApproval()` | `poolId`, `approved` | `_pools[poolId]` |
| `UnightPolicyRegistry` | `setMarketApproval()` | `marketId`, `approved` | `_markets[marketId]` |
| `UnightPolicyRegistry` | `setRatifierApproval()` | `ratifier`, `approved` | `_ratifiers[ratifier]` |
| `UnightPolicyRegistry` | `setDormancyOracleApproval()` | `oracle`, `approved` | `_oracles[oracle]` |
| `UnightAccount` | `onERC721Received()` | `tokenId` | none; accepts only configured v4 NFT from PositionManager |
| `UnightBidRatifier` | `isRatified()` | `offer`, `ratifierData`, `taker` | none; static/read-only ratifier boundary |
