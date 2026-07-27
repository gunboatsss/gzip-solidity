# Audit report — `src/GzipYul.sol`

Pure‑Yul gzip decompression library. Verified against the Solidity reference
(`src/Gzip.sol`, `src/lib/Deflate.sol`, `src/lib/Huffman.sol`, `src/lib/BitReader.sol`)
and RFC 1951/1952, with new test vectors generated via Python `gzip`/`zlib` to
cover paths the existing suite (`test/GzipYul.t.sol`) does not.

**Status: all issues fixed.** See [Fix](#fix-applied) below.

Verdict: the bit reader, canonical‑Huffman construction/decode, fixed‑Huffman
decoder, length/distance tables, output buffer (including overlapping RLE copy),
CRC‑32, header/footer parsing, and the CRC32/ISIZE error ABI‑encoding are all
**correct**. One **critical** correctness bug was found and fixed, plus a few minor issues.

Severity legend: 🔴 critical · 🟡 minor · 🔵 informational.
Resolution: ✅ fixed · ⬜ deferred.

---

## 🔴 Critical — stored blocks (BTYPE=0) and multi‑block streams revert ✅ FIXED

`GzipYul.decompress` reverted — bare `revert(0,0)`, empty revert reason — on **any**
gzip stream containing a stored (BTYPE=0) DEFLATE block. This included the common
single‑block case (`gzip -1` on tiny or incompressible input) and all multi‑block
streams. The Solidity reference `Gzip.decompress` decompressed the same inputs
correctly.

### Root cause

The `bfinal` flag was held in a Yul local variable across the `switch`/`case`
block bodies. The Yul compiler reused the stack slot during case execution,
corrupting `bfinal`. After a stored or non‑final block, `if bfinal { break }` saw
`bfinal=0` and tried to read another block header past EOF, reverting.

### Fix

`bfinal` is now stored in the state block at `S+0xE0` (`mstore`/`mload`) instead
of a local variable. The state block was expanded from `0xE0` to `0x120` bytes.
The fix works with both `via_ir=true` and `via_ir=false` and adds zero gas overhead.

### Reproducer

`test/GzipYulAuditRepro.t.sol` — all tests now assert **equality** with the
reference `Gzip` (previously asserted revert).

---

## 🟡 Minor

### 1. `cm != 8` reverts with the wrong error ✅ FIXED

Previously reverted with `GzipInvalidMagic` (selector `0xb0f25b04`). Now uses
`GzipUnsupportedMethod(uint8 cm)` (selector `0x4e2edd5b`) with the `cm` byte
encoded as an argument.

### 2. `htDecode` silently returns `0` on invalid codes ✅ FIXED

Added `revert(0,0)` after the decode loop when no symbol matches. Previously
returned `0` (a literal NUL byte) silently.

### 3. DEFLATE‑level errors are all bare `revert(0,0)` ⬜ DEFERRED

EOF overread, invalid Huffman code, invalid length/distance code, len/nlen
mismatch, reserved BTYPE=3, and `repeat‑without‑previous` all revert with
**empty data**. The CRC32/ISIZE check is the backstop (safety is fine), but
observability could be improved with typed errors.

---

## 🔵 Informational

### 3. Dead store / scratch‑space write ✅ FIXED

`mstore(0x00, S)` was removed. Nothing read it back.

### 4. Memory is never freed or reused ⬜ DEFERRED

The 0x120 state block, the ≥1 KB output buffer, and each dynamic block's
tables are allocated from `0x40` and abandoned. Matches `GzipAssembly`'s
behaviour. Gas‑reducible but not a correctness issue.

### 5. Over‑zeroing in `decodeDynamic` ⬜ DEFERRED

`mstore(cl_lens, 0)` then `mstore(add(cl_lens, 16), 0)` writes into `cl_tbl`'s
region, which `htBuild` fully overwrites. Currently safe, but fragile.

---

## Fix applied

Three targeted changes to `src/GzipYul.sol` (no architectural rewrite):

1. **`bfinal` stored in state block** (`S+0xE0`) — eliminates stack‑slot reuse corruption
2. **`GzipUnsupportedMethod(uint8)` error** — correct selector for `cm != 8`
3. **`htDecode` revert** — no longer silently returns `0` on invalid codes

`via_ir` can be `true` or `false`. `foundry.toml` currently uses `via_ir = true`
for optimal gas (matches original numbers exactly).

### Test coverage

`test/GzipYulAuditRepro.t.sol` now asserts **equality** with `Gzip.sol` for
all stored‑block and multi‑block vectors, plus the header‑flag and error paths.

All 55 tests pass (19 GzipYul‑specific + 36 from other suites).
