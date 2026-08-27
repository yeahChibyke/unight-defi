# Fizz Property Harness

`ToolFuzzTester.sol` is the standalone Medusa/Echidna target. It deliberately
uses no Foundry cheatcodes, RPC calls, or fork-local state. Its properties
cover deterministic accounting conservation, capacity caps, principal
coverage, callback commitments, epoch progression, and v4 liquidity-math
monotonicity.

Live Midnight and Uniswap v4 settlement is tested separately by the Foundry
Base fork suites under `test/BaseFork*.t.sol`; standalone-fuzzer results do not
replace that integration evidence.

## Run

```bash
forge build
medusa fuzz --config medusa.json
echidna . --contract ToolFuzzTester --config echidna.yaml
```

Fizz discovery metadata and the synthesized property plan are stored in
`fizz_data/` and `PROPERTIES.md`.
