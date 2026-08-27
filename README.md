# Unight

Conditional fixed-rate lending for out-of-range Uniswap v4 liquidity.

Unight lets an LP place a Uniswap v4 position under policy-controlled custody and use terminal, one-sided liquidity to support fixed-rate credit through Midnight. The system supports two settlement modes:

- **Auto-Lend:** the account takes a borrower sell offer and funds it from eligible LP liquidity.
- **LP Bid Board:** a borrower takes an LP maker bid and the account funds the resulting credit settlement.

## Current integration

The repository contains:

- Uniswap v4 position custody and terminal-liquidity accounting.
- Unight policy, capacity, executor, and dormancy controls.
- Midnight Auto-Lend and LP Bid Board settlement paths.
- SetterRatifier authorization integration.
- Base mainnet-forked tests using live Uniswap v4, USDC, cbBTC, and Midnight deployments.

## Run the fork suite

Copy `.env.example` to `.env` and set `BASE_RPC_URL` to a Base RPC endpoint.

```bash
set -a; source .env; set +a
forge test
```

The complete Foundry suite currently covers 55 tests, including the fork-backed fuzz suite. The focused end-to-end Bid Board suite is:

```bash
forge test --match-contract BaseForkBidBoardTest -vv
```

Pinned deployment and fork parameters are documented in [`params.md`](params.md). The project direction and remaining delivery stages are documented in [`STRATEGY.md`](STRATEGY.md).

## Demonstration

See [`DEMO.md`](DEMO.md) for the Auto-Lend and LP Bid Board walkthroughs, expected state transitions, and failure-proof evidence.

Standalone Medusa and Echidna checks target the deterministic property harness:

```bash
medusa fuzz --config medusa.json
echidna . --contract ToolFuzzTester --config echidna.yaml
```

Those tools validate accounting, policy-cap, callback-commitment, and
liquidity-math properties. Live Midnight/v4 settlement remains covered by the
Foundry Base fork tests.
