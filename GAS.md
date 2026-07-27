# Gas Comparison

| Test | Input | Gzip.sol | GzipAssembly.sol | GzipYul.sol | Yul win |
|---|---|---|---|---|---|
| empty | 0 B | 157K | 333K | **3.8K** | 97.6% |
| X | 1 B | 200K | 375K | **6.9K** | 96.6% |
| hello | 13 B | 714K | 876K | **43.7K** | 93.9% |
| abcRpt | 12 B | 441K | 613K | **27.0K** | 93.9% |
| quickFox | 89 B | 2,355K | 2,450K | **183K** | 92.2% |
| 500x | 500 B | 1,348K | 1,282K | **455K** | 66.3% |
| dynamic | 132 B | 4,781K | 4,737K | **1,620K** | 66.1% |
| tarGz | 10 KB | 29,870K | 20,801K | **11,723K** | 60.8% |

**Gzip.sol** — original pure-Solidity with shared libraries (BitReader, Huffman, Deflate)

**GzipAssembly.sol** — self-contained with assembly hot-paths: bit-reader, CRC-32, MCOPY

**GzipYul.sol** — pure-Yul, all state on heap, every helper is a Yul function
