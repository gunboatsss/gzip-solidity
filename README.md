# gzip-solidity

Gas-optimized gzip decompression in pure Yul. 55–97% cheaper than a pure‑Solidity reference.

## Overview

| Library | Approach | Gas vs `Gzip.sol` |
|---|---|---|
| `Gzip.sol` | Pure Solidity with shared libs (BitReader, Huffman, Deflate) | baseline |
| `GzipAssembly.sol` | Solidity structs + assembly hot‑paths | 0–30% cheaper |
| `GzipYul.sol` | Pure‑Yul, state on heap, every helper inlined | **55–97% cheaper** |

All three pass the same test suite. `GzipYul` is the recommended choice.

## Quick start

```bash
# Install dependencies
forge install

# Run tests
forge test

# Gas comparison (single profile)
FOUNDRY_PROFILE=default forge test --match-contract GasCompare -vv

# Gas matrix (all profiles + optimizer settings)
bash scripts/gas_matrix.sh
```

## Gas

| Test | Input | `Gzip.sol` | `GzipYul.sol` | Savings |
|---|---|---|---|---|
| empty | 0 B | 156K | **4.3K** | 97% |
| 1 byte | 1 B | 194K | **7.8K** | 96% |
| hello | 13 B | 643K | **49K** | 92% |
| quick fox | 89 B | 2,081K | **203K** | 90% |
| 500×"A" | 500 B | 1,229K | **479K** | 61% |
| stored 1 KB | 1 KB | 2,080K | **950K** | 54% |
| stored 16 KB | 16 KB | 33M | **15M** | 54% |
| fixed 64 KB | 64 KB | 154M | **73M** | 52% |

## Profiles

| Profile | via_ir | optimizer | best for |
|---|---|---|---|
| `default` | false | true, runs=200 | **small payloads** (<2 KB) |
| `ir-opt-runs10k` | true | true, runs=10k | **large payloads** (>2 KB) |
| `ir-opt-no-opt` | true | false | comparison baseline |

Select with `FOUNDRY_PROFILE=<name>`:

```bash
FOUNDRY_PROFILE=ir-opt-runs10k forge test --match-contract GasCompare -vv
```

## Block type support

All DEFLATE block types are supported:

| BTYPE | Name | Status |
|---|---|---|
| 0 | Stored (no compression) | ✅ |
| 1 | Fixed Huffman | ✅ |
| 2 | Dynamic Huffman | ✅ |
| 3 | Reserved | reverts |

Multi-block streams and gzip members work correctly.

## Scripts

| Script | Purpose |
|---|---|
| `scripts/gen_testdata` | Generate `.gz` fixtures for all block types |
| `scripts/gas_matrix.sh` | Gas comparison across compiler profiles |

```bash
# Generate test fixtures (required before roundtrip tests)
./scripts/gen_testdata

# Full gas matrix
bash scripts/gas_matrix.sh

# Specific profiles
bash scripts/gas_matrix.sh default ir-opt-runs10k
```

## Error types

| Error | Selector |
|---|---|
| `GzipInvalidMagic()` | `0xb0f25b04` |
| `GzipUnsupportedMethod(uint8)` | `0x4e2edd5b` |
| `GzipInputTooShort()` | `0x6d1e0b23` |
| `GzipCrc32Mismatch(uint32,uint32)` | `0x6d9f3e27` |
| `GzipIsizeMismatch(uint32,uint32)` | `0x61025233` |

## License

MIT
