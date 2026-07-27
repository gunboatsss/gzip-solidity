// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Deflate} from "./lib/Deflate.sol";

/**
 * @title Gzip
 * @notice Gzip decompression library (RFC 1952)
 * @dev Parses gzip headers, decompresses the DEFLATE payload, and verifies
 *      the CRC-32 checksum and uncompressed size (ISIZE).
 *
 *      Usage:
 *        bytes memory decompressed = Gzip.decompress(gzipBytes);
 *
 *      Reverts on invalid header, checksum mismatch, or truncated input.
 */
library Gzip {
    // ─── gzip magic and flags ───────────────────────────────────────────

    uint8 private constant ID1 = 0x1F;
    uint8 private constant ID2 = 0x8B;
    uint8 private constant CM_DEFLATE = 0x08;

    // Flag bits
    uint8 private constant FLG_FTEXT    = 0x01;
    uint8 private constant FLG_FHCRC    = 0x02;
    uint8 private constant FLG_FEXTRA   = 0x04;
    uint8 private constant FLG_FNAME    = 0x08;
    uint8 private constant FLG_FCOMMENT = 0x10;

    // ─── errors ────────────────────────────────────────────────────────

    error GzipInvalidMagic();
    error GzipUnsupportedMethod(uint8 cm);
    error GzipInputTooShort();
    error GzipCrc32Mismatch(uint32 expected, uint32 actual);
    error GzipIsizeMismatch(uint32 expected, uint32 actual);

    // ─── main entry point ──────────────────────────────────────────────

    /**
     * @notice Decompress a complete gzip-compressed byte array.
     * @param input The gzip-compressed data
     * @return output The uncompressed data
     */
    function decompress(bytes memory input) internal pure returns (bytes memory output) {
        if (input.length < 18) revert GzipInputTooShort(); // header(10) + footer(8) min

        uint256 pos = 0;

        // ── parse header ──────────────────────────────────────────────
        if (uint8(input[pos]) != ID1 || uint8(input[pos + 1]) != ID2) {
            revert GzipInvalidMagic();
        }
        pos += 2;

        uint8 cm = uint8(input[pos]);
        if (cm != CM_DEFLATE) revert GzipUnsupportedMethod(cm);
        pos += 1;

        uint8 flg = uint8(input[pos]);
        pos += 1;

        // MTIME (4 bytes) — ignored
        pos += 4;

        // XFL — ignored
        pos += 1;

        // OS — ignored
        pos += 1;

        // ── optional header fields ─────────────────────────────────────
        if (flg & FLG_FEXTRA != 0) {
            // XLEN is little-endian uint16
            uint16 xlen = uint16(uint8(input[pos]))
                | (uint16(uint8(input[pos + 1])) << 8);
            pos += 2;
            pos += xlen;
        }

        if (flg & FLG_FNAME != 0) {
            pos = skipNullTerminated(input, pos);
        }

        if (flg & FLG_FCOMMENT != 0) {
            pos = skipNullTerminated(input, pos);
        }

        if (flg & FLG_FHCRC != 0) {
            // CRC16 of the header (2 bytes) — skip
            pos += 2;
        }

        // ── extract compressed and footer ──────────────────────────────
        // The compressed data runs from `pos` to `input.length - 8`.
        // The last 8 bytes are CRC32 (4) + ISIZE (4).
        if (input.length < pos + 8) revert GzipInputTooShort();

        uint256 compressedLen = input.length - pos - 8;
        bytes memory compressed = new bytes(compressedLen);
        for (uint256 i = 0; i < compressedLen; i++) {
            compressed[i] = input[pos + i];
        }

        // Read footer (last 8 bytes)
        uint256 footerStart = input.length - 8;
        uint32 expectedCrc32 =
            uint32(uint8(input[footerStart]))
            | (uint32(uint8(input[footerStart + 1])) << 8)
            | (uint32(uint8(input[footerStart + 2])) << 16)
            | (uint32(uint8(input[footerStart + 3])) << 24);

        uint32 expectedIsize =
            uint32(uint8(input[footerStart + 4]))
            | (uint32(uint8(input[footerStart + 5])) << 8)
            | (uint32(uint8(input[footerStart + 6])) << 16)
            | (uint32(uint8(input[footerStart + 7])) << 24);

        // ── decompress ─────────────────────────────────────────────────
        output = Deflate.decompress(compressed);

        // ── verify CRC32 ──────────────────────────────────────────────
        uint32 actualCrc32 = crc32(output);
        if (actualCrc32 != expectedCrc32) {
            revert GzipCrc32Mismatch(expectedCrc32, actualCrc32);
        }

        // ── verify ISIZE (uncompressed length mod 2^32) ────────────────
        uint32 actualIsize = uint32(output.length & 0xFFFFFFFF);
        if (actualIsize != expectedIsize) {
            revert GzipIsizeMismatch(expectedIsize, actualIsize);
        }
    }

    // ─── CRC-32 ────────────────────────────────────────────────────────

    /**
     * @notice Compute the CRC-32 (ISO-HDLC / gzip / PKZIP) of the input bytes.
     * @dev Uses the reflected polynomial 0xEDB88320.
     *      Initial value 0xFFFFFFFF, final XOR with 0xFFFFFFFF.
     */
    function crc32(bytes memory data) internal pure returns (uint32) {
        uint32 crc = 0xFFFFFFFF;
        for (uint256 i = 0; i < data.length; i++) {
            uint8 byteVal = uint8(data[i]);
            crc = crc ^ uint32(byteVal);
            for (uint8 j = 0; j < 8; j++) {
                if ((crc & 1) != 0) {
                    crc = (crc >> 1) ^ 0xEDB88320;
                } else {
                    crc = crc >> 1;
                }
            }
        }
        return ~crc; // equivalent to crc ^ 0xFFFFFFFF
    }

    // ─── helpers ───────────────────────────────────────────────────────

    /**
     * @notice Advance `pos` past a null-terminated string (byte 0x00).
     */
    function skipNullTerminated(bytes memory input, uint256 pos)
        internal
        pure
        returns (uint256)
    {
        while (pos < input.length && uint8(input[pos]) != 0) {
            pos++;
        }
        if (pos < input.length) {
            pos++; // skip the null byte
        }
        return pos;
    }
}
