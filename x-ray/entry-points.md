# Unight Entry Points

## Protocol Flow Paths

### Account setup (LP owner)

`PolicyRegistry.setPoolApproval()` → `PolicyRegistry.setMarketApproval()` → `PolicyRegistry.setDormancyOracleApproval()` → `AccountFactory.createAccount()` → `Account.setPolicy()`

### Position custody (LP owner)

`PositionManager.safeTransferFrom()` → `Account.onERC721Received()` ◄── configured PositionManager and position ID must match

### Auto-Lend (LP owner or approved executor)

`Account.setExecutor()` → `Account.takeAutoLend()` ◄── policy, market, authorization, debt, capacity, terminality, and dormancy checks → `Midnight.take()` → `Account.onBuy()` → `V4TerminalPositionAdapter.removeForFunding()` → `PositionManager.modifyLiquidities()`

### LP Bid Board (Midnight/taker path)

`Account.setPolicy()` → ratifier validates offer → `Midnight.take()` → `Account.onBuy()` → `_openBidContext()` → `V4TerminalPositionAdapter.removeForFunding()` → `PositionManager.modifyLiquidities()`

### Account exit (LP owner)

`Account.close()` → Midnight authorization revocation → `Account.withdrawPosition()` ◄── selected-market credit and debt must be zero → `PositionManager.safeTransferFrom()`

## Permissionless

### `UnightAccountFactory.createAccount()`

| Aspect | Detail |
|---|---|
| Visibility | external |
| Caller | Anyone; supplied owner becomes immutable account owner |
| Parameters | owner, positionId, loanToken, poolId, oracle, ratifier (user-controlled) |
| Call chain | `→ new UnightAccount()` |
| State modified | `accountOf[owner][positionId]` |
| Value flow | None |
| Reentrancy guard | no |

### `UnightAccount.onBuy()`

| Aspect | Detail |
|---|---|
| Visibility | external |
| Caller | Midnight only; body checks `msg.sender` |
| Parameters | market, assets, units, fee, buyer, callback data (protocol-derived) |
| Call chain | `→ V4TerminalPositionAdapter.removeForFunding()` → `PositionManager.modifyLiquidities()` → exact USDC approval |
| State modified | execution context, committed assets, mode assets, removed principal |
| Value flow | v4 terminal liquidity → account → Midnight pull |
| Reentrancy guard | no explicit modifier; context and caller checks |

## Role-Gated

### LP owner

| Contract | Function | Parameters | State modified |
|---|---|---|---|
| UnightAccount | `setExecutor()` | executor, enabled (user-controlled) | executor mapping |
| UnightAccount | `setPolicy()` | policy (user-controlled) | policy, policyNonce |
| UnightAccount | `disablePolicy()` | none | policy.enabled, policyNonce |
| UnightAccount | `close()` | none | closed, policy, epochs, Midnight authorization |
| UnightAccount | `withdrawPosition()` | none | positionEpoch; NFT ownership |
| UnightAccount | `sweepLoanToken()` | amount, recipient (user-controlled) | token balance outside contract |

### LP owner or approved executor

| Contract | Function | Parameters | State modified |
|---|---|---|---|
| UnightAccount | `takeAutoLend()` | offer, ratifierData, units, max assets, min units, deadline (caller-controlled) | execution context; settlement accounting; v4 position |

### Configured bid ratifier

#### `UnightAccount.registerBidContext()`

| Aspect | Detail |
|---|---|
| Visibility | external, `idle` |
| Caller | configured `bidRatifier` only |
| Parameters | offer hash, market, taker, max assets, deadline, callback data (ratifier/protocol-derived) |
| Call chain | `→ Midnight.credit/debt` reads; opens maker-bid execution context |
| State modified | `_execution` |
| Value flow | None |
| Reentrancy guard | no explicit modifier; `idle` context guard |

### Registry owner

| Contract | Function | Parameters | State modified |
|---|---|---|---|
| UnightPolicyRegistry | `setPoolApproval()` | pool ID, approved | pool allowlist |
| UnightPolicyRegistry | `setMarketApproval()` | market ID, approved | market allowlist |
| UnightPolicyRegistry | `setRatifierApproval()` | ratifier, approved | ratifier allowlist |
| UnightPolicyRegistry | `setDormancyOracleApproval()` | oracle, approved | oracle allowlist |

### Midnight

#### `UnightBidRatifier.isRatified()`

| Aspect | Detail |
|---|---|
| Visibility | external view |
| Caller | Midnight only; `msg.sender` checked |
| Parameters | offer, ratifier data, taker (protocol-provided) |
| Call chain | `→ baseRatifier.isRatified()` |
| State modified | None |
| Value flow | None |
| Reentrancy guard | not applicable; view |

## Initialization

Constructors initialize the registry, factory, account, and ratifier. The account and ratifier contain immutable cross-references; factory account creation accepts a ratifier address supplied by the caller.
