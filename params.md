# Unight Fork-Test Parameters

This file records the deterministic Base mainnet fixtures for the planned
Unight fork tests. It deliberately does not contain the RPC endpoint. Test
code must load it from the environment with:

```solidity
vm.createSelectFork(vm.envString("BASE_RPC_URL"), FORK_BLOCK);
```

The addresses and state below were read from Base mainnet and should be
rechecked if the test fork block changes.

## 1. Network and fork

| Parameter | Value |
|---|---:|
| Network | Base mainnet |
| Chain ID | `8453` |
| Fork block | `50_000_000` |
| Fork block timestamp | `1_786_789_347` (`2026-08-15 10:22:27 UTC`) |

Block `50_000_000` is a fixed, reproducible block that is after the selected
Uniswap position was created and after Midnight was deployed. It is preferred
to `latest` for stable fork tests.

## 2. Protocol deployments

### Uniswap v4 on Base

| Component | Address |
|---|---|
| PoolManager | `0x498581ff718922c3f8e6a244956af099b2652b2b` |
| PositionManager | `0x7c5f5a4bbd8fd63184577525326123b519429bdc` |
| StateView | `0xa3c0c9b65bad0b08107aa264b0f3db444b867a71` |
| Permit2 | `0x000000000022D473030F116dDEE9F6B43aC78BA3` |

### Midnight on Base

| Component | Address |
|---|---|
| Midnight | `0xAdedD8ab6dE832766Fedf0FaC4992E5C4D3EA18A` |
| SetterRatifier | `0x800B5F12A61B8198a5a6EfD794Cac6699B294d63` |
| EcrecoverRatifier | `0xd6e70365C8E8DDa9a4ca662C07bbE663b017755E` |
| EcrecoverAuthorizer | `0x292bEa9f1443d54E0E509120c919106765c6a493` |
| Mempool | `0xdD6DCE32e21f7b020898a8258dA37355b4017993` |

## 3. Assets

| Asset | Address | Decimals | Role |
|---|---|---:|---|
| USDC | `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` | 6 | Uniswap currency0 and Midnight loan token |
| cbBTC | `0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf` | 8 | Uniswap currency1 and Midnight collateral |

## 4. Uniswap v4 pool fixture

| Pool field | Value |
|---|---|
| Pool ID | `0xca7a9a04f4fbb8e4bbacd89b2597ddabdd8dfb4a6c3e6b7793ac8f75a2e5d89b` |
| currency0 | USDC (`0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913`) |
| currency1 | cbBTC (`0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf`) |
| Fee | `0` |
| Tick spacing | `10` |
| Hooks | `0xfaD27BC5ef16A0a2aA3049953C25a48E8858b0C0` |
| Initialize block | `48_011_591` |
| Initialize tick | `-63_858` |

At fork block `50_000_000`, StateView reports pool tick `-64_451`.

## 5. Real LP position fixture

| Position field | Value |
|---|---:|
| PositionManager token ID | `2_742_919` |
| LP / NFT owner | `0xFEE77A870474B320F8CA3B8711dD76d87c045F24` |
| Lower tick | `-70_790` |
| Upper tick | `-56_920` |
| Liquidity at fork block | `257_740_997` |
| First liquidity-modification block | `48_011_609` |

The position is active at the selected fork block because
`-70_790 < -64_451 < -56_920`. This makes it suitable for custody, pool/
position identity, and active-position rejection tests. It is intentionally
not treated as a terminal position. Terminal unwind tests must use a
fork-local test mechanism to move the pool state or a test dormancy oracle;
they must not infer terminality merely from this position being old.

No LP private key is required. The owner address is a fork fixture and can be
impersonated with Foundry cheatcodes when a setup test needs to approve or
transfer the NFT.

## 6. Midnight market fixture

The selected market is the first currently listed USDC-loan/cbBTC-collateral
market returned by the official Midnight API for Base.

| Market field | Value |
|---|---|
| Market ID | `0x549cd072daf99328554f3a6d2d4d6f4a07f1c59369e891e6391946f9cf75f221` |
| Chain ID | `8453` |
| Loan token | USDC |
| Collateral token | cbBTC |
| Maturity | `1_790_348_400` (`2026-09-25 15:00:00 UTC`) |
| RCF threshold | `3_000_000_000` |
| cbBTC LLTV | `860_000_000_000_000_000` (`86%`) |
| Liquidation cursor | `300_000_000_000_000_000` (`30%`) |
| Oracle | `0x663BECd10daE6C4A3Dcd89F1d76c1174199639B9` |
| Enter gate | `address(0)` |
| Liquidator gate | `address(0)` |

The market resolves successfully through `IMidnight.toMarket` at fork block
`50_000_000` and its canonical loan token and chain ID match this fixture.

## 7. Policy values for the initial tests

These are test inputs, not production risk parameters:

| `UnightPolicy` field | Test value |
|---|---:|
| `marketId` | The market ID above |
| `globalCap` | `1_000_000e6` USDC base units |
| `autoLendCap` | `600_000e6` USDC base units |
| `bidBoardCap` | `400_000e6` USDC base units |
| `reactivationReserve` | `100_000e6` USDC base units |
| `minNetRateWad` | `0` |
| `maxContinuousFee` | `0` |
| `maxSettlementFee` | `0` |
| `expiry` | `1_790_000_000` |
| `minimumDwell` | `1 days` |
| `tickBuffer` | `100` |
| `maxLendableBps` | `8_000` (`80%`) |
| `enabled` | `true` |

The test setup must approve the selected pool and market in a freshly
deployed `UnightPolicyRegistry`. It should use a fork-local mock dormancy
oracle approved by that registry; no production Unight dormancy-oracle
deployment exists in this repository.

## 8. Source references

- [Uniswap v4 Base deployments](https://developers.uniswap.org/docs/protocols/v4/deployments)
- [Morpho Midnight contract addresses](https://docs.morpho.org/developers/contracts/addresses/)
- [Morpho Midnight SDK and Base chain support](https://docs.morpho.org/developers/sdks/morpho-sdk/midnight/)
- [Morpho Midnight API](https://docs.morpho.org/developers/api/morpho-midnight/)
- [Circle USDC contract addresses](https://developers.circle.com/stablecoins/usdc-contract-addresses)
- [Coinbase cbBTC](https://www.coinbase.com/cbbtc)

