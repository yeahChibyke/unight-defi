# Unight

Conditional fixed-rate lending for dormant Uniswap v4 liquidity.

Unight lets a Uniswap LP keep a concentrated-liquidity position in place while making a bounded amount of its single-sided, out-of-range principal available for fixed-maturity lending through Morpho Midnight.

The LP keeps the position NFT and chooses the policy: approved market, maturity window, minimum rate, capacity, and the amount of liquidity that may be removed. When a valid Midnight trade arrives, Unight removes only the required terminal principal and funds the settlement atomically.

> **Status:** Development prototype. The contracts are not audited and are not ready for production use. Do not deposit funds or use fork deployment addresses as production configuration.

## Why Unight?

When a concentrated-liquidity position moves fully out of range, its liquidity principal becomes single-sided and is usually idle. An LP traditionally chooses between waiting or withdrawing and reallocating the capital. Unight adds a third option: keep the position and lend a controlled portion of its dormant terminal inventory without pre-funding a separate lending wallet.

This is not double yield. A successful fill converts part of the LP’s AMM inventory into Midnight credit exposure. The LP remains exposed to Midnight’s rates, liquidity, maturity, liquidation, and bad-debt outcomes.

## How it works

```text
Uniswap v4 position
        │ safely out of range and dormant
        ▼
Unight Account ── exact USDC callback ──► Morpho Midnight
        │                                      │
        └── retains NFT and policy control     └── LP receives credit
```

### Auto-Lend

The LP defines a policy and Unight monitors eligible borrower asks. When an ask meets the policy, an executor takes it for the LP. Midnight calls the Unight Account as the buy callback; the account removes the exact required amount from the v4 position and Midnight pulls it in the same transaction.

### LP Bid Board

The LP publishes a signed Midnight lending bid with Unight as its callback. A borrower discovers the bid through Unight’s distribution layer and takes it directly on Midnight. This lets the LP choose its own price and show available lending capacity, including when a hosted router does not index callback-backed offers.

| | Auto-Lend | LP Bid Board |
|---|---|---|
| Offer creator | Borrower | LP |
| LP’s role | Taker and lender | Maker and lender |
| Discovery | Supported Midnight ask router | Unight distribution/API or direct RFQ |
| Settlement caller | Unight executor | Borrower |
| Callback | Runtime taker callback | Signed maker callback |

## Safety model

Every settlement is checked onchain against the LP’s policy and current position state. The account:

- accepts only its bound Uniswap v4 position;
- requires approved pools, markets, ratifiers, and dormancy oracles;
- verifies terminal, one-sided inventory and historical out-of-range dwell time;
- enforces global, per-mode, offer, and safe-principal caps;
- binds callbacks to the offer, market, policy nonce, position epoch, and deadline;
- reserves capacity before external calls and reverts the entire flow on failure;
- separates lendable principal from fees, dust, recovered assets, and losses;
- has no arbitrary `call`, `delegatecall`, or upgrade path.

Capacity is denominated in gross Midnight `buyerAssets`, the amount funded by the callback. In v1, committed capacity is monotonic and is not automatically recycled after maturity or credit withdrawal; reuse requires explicit reconciliation and policy closure.

## Architecture

| Component | Purpose |
|---|---|
| `UnightAccount` | One non-upgradeable account per LP position; owns the NFT, enforces limits, and implements the Midnight callback. |
| `UnightAccountFactory` | Deterministically deploys and binds an account to an LP, position, and protocol configuration. |
| `V4TerminalPositionAdapter` | Proves terminality, calculates conservative liquidity removal, and withdraws exact principal. |
| `UnightPolicyRegistry` | Governance allowlist for pools, markets, ratifiers, and dormancy oracles. |
| `UnightBidRatifier` | Composes Midnight authorization with dynamic bid and capacity checks. |

Midnight remains responsible for credit, debt, collateral, health, fees, maturity, liquidation, and settlement. Unight is a bounded liquidity adapter and discovery layer—not a replacement for Midnight.

## Current scope

The prototype targets Base, Uniswap v4, USDC terminal principal, approved Midnight markets, and fixed-maturity settlement. It does not support in-callback swaps, leverage, cross-chain inventory, arbitrary AMMs, arbitrary v4 hooks, or automatic capacity recycling.

## Run the tests

Requirements: Foundry and a Base RPC endpoint.

```bash
cp .env.example .env
# Set BASE_RPC_URL in .env
set -a; source .env; set +a
forge build
forge test
```

The fork suite uses a pinned Base block and live Uniswap v4, Midnight, USDC, and cbBTC deployments while deploying fresh local Unight fixtures.

Focused end-to-end paths:

```bash
forge test --match-contract BaseForkAutoLendTest --match-test testForkAutoLendSettlesLiveBorrowerOffer -vvvv
forge test --match-contract BaseForkBidBoardTest --match-test testLiveLpBidBoardSettlement -vvvv
```

Deterministic property fuzzing:

```bash
medusa fuzz --config medusa.json
echidna . --contract ToolFuzzTester --config echidna.yaml
```

See [`DEMO.md`](DEMO.md) for the complete test walkthrough, [`params.md`](params.md) for pinned parameters, and [`UNIGHT.md`](UNIGHT.md) plus [`STRATEGY.md`](STRATEGY.md) for the detailed product and implementation rationale.

