// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {BitReader} from "./BitReader.sol";

using BitReader for BitReader.State;

/**
 * @title Huffman
 * @notice Huffman code table construction and symbol decoding for DEFLATE
 * @dev Implements canonical Huffman codes per RFC 1951 section 3.2.2.
 *
 *      The Table struct uses `bytes` (tightly packed in memory) rather than
 *      `uint8[]` (which wastes 31 bytes per element) for the per-symbol
 *      code-length array.
 */
library Huffman {
    /// @notice Maximum code length for literal/length and distance alphabets
    uint8 internal constant MAX_BITS = 15;

    /// @notice Maximum alphabet sizes
    uint16 internal constant MAX_LITLEN_SYMBOLS = 288; // 0-285 used + 286,287 unused
    uint16 internal constant MAX_DIST_SYMBOLS = 32;    // 0-31
    uint16 internal constant MAX_CODELEN_SYMBOLS = 19; // code length alphabet

    /**
     * @notice Decoding table for a Huffman alphabet.
     * @dev firstCode[bits] = the first canonical code of length 'bits'
     *      blCount[bits] = number of codes of length 'bits'
     *      lengths[symbol] = code length for each symbol (0 means symbol not used),
     *                        stored as tightly-packed bytes for memory efficiency
     */
    struct Table {
        uint16[16] firstCode; // index by code length (1..15)
        uint8[16] blCount;    // count of codes per length
        bytes lengths;        // code length per symbol (byte-packed)
    }

    /**
     * @notice Build a canonical Huffman table from per-symbol code lengths.
     * @param lengths The code length for each symbol; 0 means the symbol is not used
     */
    function buildTable(bytes memory lengths) internal pure returns (Table memory table) {
        // Allocate the tightly-packed lengths array
        table.lengths = new bytes(lengths.length);

        // Copy lengths and count codes per length
        for (uint256 i = 0; i < lengths.length; i++) {
            uint8 len = uint8(lengths[i]);
            table.lengths[i] = bytes1(len);
            if (len > 0) {
                require(len <= MAX_BITS, "Huffman: code length too long");
                table.blCount[len]++;
            }
        }

        // Generate first codes for each length (RFC 1951 algorithm)
        uint16 code = 0;
        table.blCount[0] = 0;
        for (uint8 bits = 1; bits <= MAX_BITS; bits++) {
            code = uint16((code + table.blCount[bits - 1]) << 1);
            table.firstCode[bits] = code;
        }
    }

    /**
     * @notice Decode a single symbol using the given table and bit reader.
     * @dev Implements the incremental decode algorithm: read bits one at a time,
     *      checking at each length whether the accumulated code falls within the
     *      valid range for that length (canonical Huffman property).
     * @return symbol The decoded symbol value
     */
    function decodeSymbol(Table memory table, BitReader.State memory br)
        internal
        pure
        returns (uint16)
    {
        uint16 code = 0;
        for (uint8 len = 1; len <= MAX_BITS; len++) {
            code = uint16((uint256(code) << 1) | uint256(br.readBit()));
            if (table.blCount[len] == 0) continue;

            uint16 first = table.firstCode[len];
            uint16 last = first + table.blCount[len];
            // Check if code is within [first, last)
            if (code >= first && code < last) {
                uint16 offset = code - first;
                // Find which symbol has this length and the given offset
                return findSymbolByLengthOffset(table, len, offset);
            }
        }
        revert("Huffman: invalid code");
    }

    /**
     * @notice Find the symbol with the given code length and offset.
     * @dev Scans through all symbols; offsets count sequentially for symbols
     *      of the same length, ordered by symbol index (canonical ordering).
     */
    function findSymbolByLengthOffset(
        Table memory table,
        uint8 targetLen,
        uint16 targetOffset
    ) internal pure returns (uint16) {
        uint16 offset = 0;
        uint256 symCount = table.lengths.length;
        for (uint16 symbol = 0; symbol < symCount; symbol++) {
            if (uint8(table.lengths[symbol]) == targetLen) {
                if (offset == targetOffset) {
                    return symbol;
                }
                offset++;
            }
        }
        revert("Huffman: symbol not found");
    }

    /**
     * @notice Fixed Huffman table for the literal/length alphabet (BTYPE=01).
     * @dev Precomputed per RFC 1951 section 3.2.6.
     *      Symbols 0..143:   8-bit codes starting at 0b00110000
     *      Symbols 144..255: 9-bit codes starting at 0b110010000
     *      Symbols 256..279: 7-bit codes starting at 0b0000000
     *      Symbols 280..287: 8-bit codes starting at 0b11000000
     */
    function buildFixedLitLenTable() internal pure returns (Table memory table) {
        table.lengths = new bytes(MAX_LITLEN_SYMBOLS);

        // 0..143: 8-bit codes
        for (uint16 i = 0; i <= 143; i++) {
            table.lengths[i] = bytes1(uint8(8));
        }
        // 144..255: 9-bit codes
        for (uint16 i = 144; i <= 255; i++) {
            table.lengths[i] = bytes1(uint8(9));
        }
        // 256..279: 7-bit codes
        for (uint16 i = 256; i <= 279; i++) {
            table.lengths[i] = bytes1(uint8(7));
        }
        // 280..287: 8-bit codes
        for (uint16 i = 280; i <= 287; i++) {
            table.lengths[i] = bytes1(uint8(8));
        }

        // Precomputed counts
        table.blCount[7] = 24;  // 256..279
        table.blCount[8] = 152; // 0..143 (144) + 280..287 (8)
        table.blCount[9] = 112; // 144..255

        // Generate first codes
        uint16 code = 0;
        for (uint8 bits = 1; bits <= MAX_BITS; bits++) {
            code = uint16((code + table.blCount[bits - 1]) << 1);
            table.firstCode[bits] = code;
        }
    }

    /**
     * @notice Fixed Huffman table for the distance alphabet (BTYPE=01).
     * @dev All 32 distance codes (0..31) use 5-bit codes, value = symbol.
     */
    function buildFixedDistTable() internal pure returns (Table memory table) {
        table.lengths = new bytes(MAX_DIST_SYMBOLS);
        for (uint16 i = 0; i < 32; i++) {
            table.lengths[i] = bytes1(uint8(5));
        }

        table.blCount[5] = 32;

        uint16 code = 0;
        for (uint8 bits = 1; bits <= MAX_BITS; bits++) {
            code = uint16((code + table.blCount[bits - 1]) << 1);
            table.firstCode[bits] = code;
        }
    }
}
