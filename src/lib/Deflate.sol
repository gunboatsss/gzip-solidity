// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {BitReader} from "./BitReader.sol";
import {Huffman} from "./Huffman.sol";

using BitReader for BitReader.State;
using Huffman for Huffman.Table;

/**
 * @title Deflate
 * @notice DEFLATE decompression (RFC 1951)
 * @dev Decompresses a DEFLATE byte stream into the original uncompressed data.
 *      Supports all three block types: stored (00), fixed Huffman (01),
 *      and dynamic Huffman (10).
 */
library Deflate {
    // ─── output buffer management ───────────────────────────────────────

    struct Output {
        bytes data;
        uint256 len; // actual number of bytes written (may be < data.length)
    }

    uint256 private constant INITIAL_OUTPUT_SIZE = 1024;

    function newOutput() internal pure returns (Output memory out) {
        out.data = new bytes(INITIAL_OUTPUT_SIZE);
        out.len = 0;
    }

    /// @notice Ensure the output buffer has room for at least `needed` additional bytes
    function ensureCapacity(Output memory out, uint256 needed) internal pure {
        uint256 required = out.len + needed;
        if (required > out.data.length) {
            uint256 newSize = out.data.length;
            // Double until we have enough capacity
            while (newSize < required) {
                newSize *= 2;
            }
            bytes memory newData = new bytes(newSize);
            // Copy existing data
            for (uint256 i = 0; i < out.len; i++) {
                newData[i] = out.data[i];
            }
            out.data = newData;
        }
    }

    /// @notice Append a single byte to the output
    function appendByte(Output memory out, uint8 byteVal) internal pure {
        ensureCapacity(out, 1);
        out.data[out.len] = bytes1(byteVal);
        out.len++;
    }

    /// @notice Append bytes from the output buffer itself (LZ77 back-reference).
    ///         Copies `length` bytes starting from `dist` bytes behind the write position.
    function appendFromOutput(Output memory out, uint256 dist, uint256 length) internal pure {
        ensureCapacity(out, length);
        // Copy byte by byte. The source and destination may overlap;
        // since source < destination, simple forward copy is correct
        // (equivalent to memmove for non-overlapping or forward-overlapping regions).
        for (uint256 i = 0; i < length; i++) {
            out.data[out.len + i] = out.data[out.len - dist + i];
        }
        out.len += length;
    }

    /// @notice Trim the output to the actual written length
    function finalize(Output memory out) internal pure returns (bytes memory) {
        bytes memory result = new bytes(out.len);
        for (uint256 i = 0; i < out.len; i++) {
            result[i] = out.data[i];
        }
        return result;
    }

    // ─── length and distance code lookup tables ─────────────────────────

    /**
     * @notice Base length values for length codes 257..285.
     *         Index = code - 257, value = base length in bytes.
     */
    function getLengthBase(uint16 code) internal pure returns (uint16) {
        // code 257..264 => 3..10
        if (code <= 264) return uint16(code - 254);
        // code 265..268 => 11..18 (steps of 2)
        if (code <= 268) return uint16(11 + (code - 265) * 2);
        // code 269..272 => 19..34 (steps of 4)
        if (code <= 272) return uint16(19 + (code - 269) * 4);
        // code 273..276 => 35..66 (steps of 8)
        if (code <= 276) return uint16(35 + (code - 273) * 8);
        // code 277..280 => 67..130 (steps of 16)
        if (code <= 280) return uint16(67 + (code - 277) * 16);
        // code 281..284 => 131..258 (steps of 32)
        if (code <= 284) return uint16(131 + (code - 281) * 32);
        // code 285 => 258
        return 258;
    }

    /**
     * @notice Number of extra bits for length codes 257..285.
     */
    function getLengthExtraBits(uint16 code) internal pure returns (uint8) {
        if (code <= 264) return 0;          // 257..264
        if (code <= 268) return 1;          // 265..268
        if (code <= 272) return 2;          // 269..272
        if (code <= 276) return 3;          // 273..276
        if (code <= 280) return 4;          // 277..280
        if (code <= 284) return 5;          // 281..284
        return 0;                            // 285
    }

    /**
     * @notice Base distance values for distance codes 0..29.
     */
    function getDistanceBase(uint16 code) internal pure returns (uint16) {
        if (code <= 3) return uint16(code + 1);          // 0..3 => 1..4
        if (code <= 5) return uint16((code - 2) * 2 + 1); // 4..5 => 5..8
        if (code <= 7) return uint16((code - 4) * 4 + 1); // 6..7 => 9..16
        if (code <= 9) return uint16((code - 6) * 8 + 1); // 8..9 => 17..32
        if (code <= 11) return uint16((code - 8) * 16 + 1); // 10..11 => 33..64
        if (code <= 13) return uint16((code - 10) * 32 + 1); // 12..13 => 65..128
        if (code <= 15) return uint16((code - 12) * 64 + 1); // 14..15 => 129..256
        if (code <= 17) return uint16((code - 14) * 128 + 1); // 16..17 => 257..512
        if (code <= 19) return uint16((code - 16) * 256 + 1); // 18..19 => 513..1024
        if (code <= 21) return uint16((code - 18) * 512 + 1); // 20..21 => 1025..2048
        if (code <= 23) return uint16((code - 20) * 1024 + 1); // 22..23 => 2049..4096
        if (code <= 25) return uint16((code - 22) * 2048 + 1); // 24..25 => 4097..8192
        if (code <= 27) return uint16((code - 24) * 4096 + 1); // 26..27 => 8193..16384
        if (code <= 29) return uint16((code - 26) * 8192 + 1); // 28..29 => 16385..32768
        return 0;
    }

    /**
     * @notice Number of extra bits for distance codes 0..29.
     * @dev Per RFC 1951 section 3.2.5:
     *      code 0-1: 0 extra bits; code >= 2: extra = code/2 - 1
     */
    function getDistanceExtraBits(uint16 code) internal pure returns (uint8) {
        if (code < 2) return 0;
        return uint8(code / 2 - 1);
    }

    // ─── code-length alphabet order ─────────────────────────────────────

    /**
     * @notice Permutation order for the code length alphabet (RFC 1951 section 3.2.7).
     *         Indices: 16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15
     */
    function getCodeLengthOrder(uint8 i) internal pure returns (uint8) {
        // Hardcoded lookup to avoid allocating an array
        if (i == 0) return 16;
        if (i == 1) return 17;
        if (i == 2) return 18;
        if (i == 3) return 0;
        if (i == 4) return 8;
        if (i == 5) return 7;
        if (i == 6) return 9;
        if (i == 7) return 6;
        if (i == 8) return 10;
        if (i == 9) return 5;
        if (i == 10) return 11;
        if (i == 11) return 4;
        if (i == 12) return 12;
        if (i == 13) return 3;
        if (i == 14) return 13;
        if (i == 15) return 2;
        if (i == 16) return 14;
        if (i == 17) return 1;
        if (i == 18) return 15;
        revert("Deflate: invalid code length index");
    }

    // ─── dynamic Huffman table decoding ─────────────────────────────────

    /**
     * @notice Decode a dynamic Huffman block header and return the literal/length
     *         and distance tables, using the provided bit reader.
     * @dev Per RFC 1951 section 3.2.7.
     * @param br The bit reader positioned at the start of the dynamic header
     * @return litLenTable Huffman table for the literal/length alphabet
     * @return distTable Huffman table for the distance alphabet
     */
    function decodeDynamicTables(BitReader.State memory br)
        internal
        pure
        returns (Huffman.Table memory litLenTable, Huffman.Table memory distTable)
    {
        uint16 hlit = uint16(br.readBits(5)) + 257;  // # of lit/len codes
        uint16 hdist = uint16(br.readBits(5)) + 1;    // # of distance codes
        uint8 hclen = uint8(br.readBits(4)) + 4;      // # of code length codes

        // Step 1: read code lengths for the code-length alphabet
        bytes memory codeLenLengths = new bytes(19);
        for (uint8 i = 0; i < hclen; i++) {
            uint8 idx = getCodeLengthOrder(i);
            codeLenLengths[idx] = bytes1(uint8(br.readBits(3)));
        }

        // Build the Huffman table for the code-length alphabet
        Huffman.Table memory codeLenTable = Huffman.buildTable(codeLenLengths);

        // Step 2: decode the literal/length and distance code lengths
        uint16 totalCodes = hlit + hdist;
        bytes memory allLengths = new bytes(totalCodes);
        uint16 n = 0;
        uint8 prevLen = 0;

        while (n < totalCodes) {
            uint16 symbol = Huffman.decodeSymbol(codeLenTable, br);

            if (symbol < 16) {
                // Literal code length
                allLengths[n] = bytes1(uint8(symbol));
                prevLen = uint8(symbol);
                n++;
            } else if (symbol == 16) {
                // Copy previous length 3-6 times
                require(n > 0, "Deflate: repeat without previous");
                uint8 repeat = uint8(br.readBits(2)) + 3;
                require(n + repeat <= totalCodes, "Deflate: too many codes");
                for (uint8 j = 0; j < repeat; j++) {
                    allLengths[n + j] = bytes1(prevLen);
                }
                n += repeat;
            } else if (symbol == 17) {
                // Repeat 0 for 3-10 times
                uint8 repeat = uint8(br.readBits(3)) + 3;
                require(n + repeat <= totalCodes, "Deflate: too many codes");
                for (uint8 j = 0; j < repeat; j++) {
                    allLengths[n + j] = bytes1(0);
                }
                prevLen = 0;
                n += repeat;
            } else if (symbol == 18) {
                // Repeat 0 for 11-138 times
                uint8 repeat = uint8(br.readBits(7)) + 11;
                require(n + repeat <= totalCodes, "Deflate: too many codes");
                for (uint8 j = 0; j < repeat; j++) {
                    allLengths[n + j] = bytes1(0);
                }
                prevLen = 0;
                n += repeat;
            } else {
                revert("Deflate: invalid code length symbol");
            }
        }

        // Split the combined lengths array into lit/len and dist
        bytes memory litLenLengths = new bytes(hlit);
        for (uint16 i = 0; i < hlit; i++) {
            litLenLengths[i] = allLengths[i];
        }

        bytes memory distLengths = new bytes(hdist);
        for (uint16 i = 0; i < hdist; i++) {
            distLengths[i] = allLengths[hlit + i];
        }

        // Build the Huffman tables
        litLenTable = Huffman.buildTable(litLenLengths);
        distTable = Huffman.buildTable(distLengths);
    }

    // ─── main decompression ─────────────────────────────────────────────

    /**
     * @notice Decompress a complete DEFLATE byte stream.
     * @param input The DEFLATE-compressed data (without gzip header/footer)
     * @return The uncompressed data
     */
    function decompress(bytes memory input) internal pure returns (bytes memory) {
        BitReader.State memory br = BitReader.init(input);
        Output memory out = newOutput();

        bool bfinal;
        do {
            bfinal = br.readBit() == 1;
            uint8 btype = uint8(br.readBits(2));

            if (btype == 0) {
                // No compression
                decompressStoredBlock(br, out);
            } else if (btype == 1) {
                // Fixed Huffman
                // Build fixed tables once — in practice we cache them
                Huffman.Table memory litLenTable = Huffman.buildFixedLitLenTable();
                Huffman.Table memory distTable = Huffman.buildFixedDistTable();
                decompressHuffmanBlock(br, out, litLenTable, distTable);
            } else if (btype == 2) {
                // Dynamic Huffman
                (Huffman.Table memory litLenTable, Huffman.Table memory distTable) =
                    decodeDynamicTables(br);
                decompressHuffmanBlock(br, out, litLenTable, distTable);
            } else {
                revert("Deflate: reserved block type (11)");
            }
        } while (!bfinal);

        return finalize(out);
    }

    /**
     * @notice Decompress a stored (uncompressed) block (BTYPE=00).
     */
    function decompressStoredBlock(BitReader.State memory br, Output memory out)
        internal
        pure
    {
        br.skipToByteBoundary();
        uint16 len = br.readAlignedUint16();
        uint16 nlen = br.readAlignedUint16();
        require(len == ~nlen, "Deflate: stored block length mismatch");

        ensureCapacity(out, len);
        bytes memory data = br.readAlignedBytes(len);
        for (uint256 i = 0; i < len; i++) {
            out.data[out.len + i] = data[i];
        }
        out.len += len;
    }

    /**
     * @notice Decompress a Huffman-coded block (BTYPE=01 or BTYPE=10).
     */
    function decompressHuffmanBlock(
        BitReader.State memory br,
        Output memory out,
        Huffman.Table memory litLenTable,
        Huffman.Table memory distTable
    ) internal pure {
        while (true) {
            uint16 symbol = Huffman.decodeSymbol(litLenTable, br);

            if (symbol < 256) {
                // Literal byte
                appendByte(out, uint8(symbol));
            } else if (symbol == 256) {
                // End of block
                break;
            } else {
                // Length/distance pair
                require(symbol >= 257 && symbol <= 285, "Deflate: invalid length code");
                uint16 length = getLengthBase(symbol);
                uint8 lenExtraBits = getLengthExtraBits(symbol);
                if (lenExtraBits > 0) {
                    length += uint16(br.readBits(lenExtraBits));
                }

                uint16 distCode = Huffman.decodeSymbol(distTable, br);
                require(distCode <= 29, "Deflate: invalid distance code");
                uint16 distance = getDistanceBase(distCode);
                uint8 distExtraBits = getDistanceExtraBits(distCode);
                if (distExtraBits > 0) {
                    distance += uint16(br.readBits(distExtraBits));
                }

                require(distance <= out.len, "Deflate: invalid distance (past start)");
                appendFromOutput(out, distance, length);
            }
        }
    }
}
