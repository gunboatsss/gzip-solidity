// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {Gzip} from "../src/Gzip.sol";

/// @notice Thin wrapper to make the internal Gzip library callable externally
///         (needed for vm.expectRevert to work across call depth)
contract GzipWrapper {
    function decompress(bytes memory input) external pure returns (bytes memory) {
        return Gzip.decompress(input);
    }
}

contract GzipTest is Test {
    using Gzip for bytes;

    // ─── helper: convert hex string to bytes ───────────────────────────

    function hexToBytes(string memory hexStr) internal pure returns (bytes memory) {
        bytes memory str = bytes(hexStr);
        require(str.length % 2 == 0, "hex: even length required");
        bytes memory out = new bytes(str.length / 2);
        for (uint256 i = 0; i < out.length; i++) {
            uint8 hi = hexCharToUint8(str[i * 2]);
            uint8 lo = hexCharToUint8(str[i * 2 + 1]);
            out[i] = bytes1(uint8((hi << 4) | lo));
        }
        return out;
    }

    function hexCharToUint8(bytes1 c) internal pure returns (uint8) {
        uint8 val = uint8(c);
        if (val >= 48 && val <= 57) return val - 48; // 0-9
        if (val >= 65 && val <= 70) return val - 65 + 10; // A-F
        if (val >= 97 && val <= 102) return val - 97 + 10; // a-f
        revert("hex: invalid char");
    }

    // ─── basic decompression tests (fixed Huffman, BTYPE=01) ───────────

    function test_decompress_empty() public {
        bytes memory gz = hexToBytes(
            "1f8b080000000000000303000000000000000000"
        );
        bytes memory result = gz.decompress();
        assertEq(result.length, 0, "empty file should produce 0 bytes");
    }

    function test_decompress_helloWorld() public {
        bytes memory gz = hexToBytes(
            "1f8b0800000000000003f348cdc9c9d75108cf2fca49510400d0c34aec0d000000"
        );
        bytes memory result = gz.decompress();
        assertEq(result, bytes("Hello, World!"), "hello world mismatch");
    }

    function test_decompress_abcRepeat() public {
        bytes memory gz = hexToBytes(
            "1f8b08000000000000034b4c4a4e842100342a6e5a0c000000"
        );
        bytes memory result = gz.decompress();
        assertEq(result, bytes("abcabcabcabc"), "abc repeat mismatch");
    }

    function test_decompress_quickFox() public {
        bytes memory gz = hexToBytes(
            "1f8b08000000000000030bc94855282ccd4cce56482aca2fcf5348cbaf50c82acd2d2856c82f4b2d5228014ae72456552aa4e4a7eb298490a01800a70ae99a59000000"
        );
        bytes memory result = gz.decompress();
        assertEq(
            result,
            bytes(
                "The quick brown fox jumps over the lazy dog. The quick brown fox jumps over the lazy dog."
            ),
            "quick fox mismatch"
        );
    }

    function test_decompress_singleByte() public {
        bytes memory gz = hexToBytes(
            "1f8b08000000000000038b00004b36b2b701000000"
        );
        bytes memory result = gz.decompress();
        assertEq(result, bytes("X"), "single byte X");
    }

    function test_decompress_fiftyAs() public {
        bytes memory gz = hexToBytes(
            "1f8b080000000000000373742415000034f94e5832000000"
        );
        bytes memory result = gz.decompress();
        bytes memory expected =
            bytes("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA");
        assertEq(result, expected, "50 A's");
    }

    function test_decompress_AtoFpattern() public {
        bytes memory gz = hexToBytes(
            "1f8b0800000000000003737404022720707676767171717575757303007c82dc2e14000000"
        );
        bytes memory result = gz.decompress();
        assertEq(result, bytes("AAAAABBBBCCCDDDEEEFF"), "A-F pattern");
    }

    function test_decompress_fiveHundredX() public {
        bytes memory gz = hexToBytes(
            "1f8b0800000000000003aba81805230d000051ceb20af4010000"
        );
        bytes memory result = gz.decompress();
        assertEq(result.length, 500, "500 x's length");
        for (uint256 i = 0; i < result.length; i++) {
            assertEq(result[i], bytes1("x"), "all bytes should be x");
        }
    }

    // ─── dynamic Huffman tests (BTYPE=10) ──────────────────────────────

    function test_decompress_dynamicHuffman_phrase() public {
        // "The quick brown fox jumps over the lazy dog." x 3 (132 bytes uncompressed)
        bytes memory gz = hexToBytes(
            "1f8b080000000000000305c1810140201440c155de044d6381e453c257546a7a77931752092e32676d17ab7eece5bc1fb44ae6f5c2614767d1cd4c5e4825b8c89cb55dacfab197f37ed02a99d70b871d9d453733792195e02273d676b1eac75ecefb41ab645e2f1c767416ddcc0f0c9c14af84000000"
        );
        bytes memory result = gz.decompress();
        bytes memory expected = bytes(
            "The quick brown fox jumps over the lazy dog."
            "The quick brown fox jumps over the lazy dog."
            "The quick brown fox jumps over the lazy dog."
        );
        assertEq(result, expected, "dynamic huffman phrase");
    }

    function test_decompress_dynamicHuffman_alphabet() public {
        // "ABCDEFGHIJKLMNOPQRSTUVWXYZ" x 5 (130 bytes uncompressed)
        bytes memory gz = hexToBytes(
            "1f8b080000000000000305c1850100200800b0dbc4003bb0f0ff43dc1468631d920f31e5525b1f3cd73e579e026dac43f221a65c6aeb83e7dae7ca53a08d75483ec4944b6d7df05cfb5c790ab4b10ec9879872a9ad0f9e6b9f2b4f8136d621f910532eb5f5c173ed73e57d165db1fa82000000"
        );
        bytes memory result = gz.decompress();
        bytes memory expected = bytes(
            "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
            "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
            "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
            "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
            "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        );
        assertEq(result, expected, "dynamic huffman alphabet");
    }

    // ─── error cases ───────────────────────────────────────────────────

    function test_decompress_invalidMagic() public {
        GzipWrapper wrapper = new GzipWrapper();
        bytes memory bad =
            hexToBytes("0000000000000000000000000000000000000000");
        vm.expectRevert(Gzip.GzipInvalidMagic.selector);
        wrapper.decompress(bad);
    }

    function test_decompress_tooShort() public {
        GzipWrapper wrapper = new GzipWrapper();
        bytes memory bad = hexToBytes("1f8b");
        vm.expectRevert(Gzip.GzipInputTooShort.selector);
        wrapper.decompress(bad);
    }

    // ─── CRC-32 ────────────────────────────────────────────────────────

    function test_crc32_empty() public {
        bytes memory empty = "";
        uint32 crc = Gzip.crc32(empty);
        assertEq(crc, 0, "crc32 of empty data should be 0");
    }

    function test_crc32_known() public {
        // CRC32 of "123456789" should be 0xCBF43926
        bytes memory data = bytes("123456789");
        uint32 crc = Gzip.crc32(data);
        assertEq(crc, 0xCBF43926, "crc32 check value");
    }

    // ─── real-world tar.gz test ────────────────────────────────────────

    function test_decompress_tarGz() public {
        // A tar archive with 3 files, gzip-compressed (211 bytes -> 10240 bytes)
        // Created via: tar cf archive.tar file1.txt file2.txt file3.txt && gzip
        bytes memory gz = hexToBytes(
            "1f8b08085a6b676a0003617263686976652e74617200edd4410ac2301085e1ac"
            "3dc59c4092a689e7a99a6aa1a66047f4f836082288b8d2a2fcdf661699c5c0e4"
            "4ddbf5c92df5a2e673ec24c6ba54b70af6b1de54b571a1f22ec6107c65acf336"
            "7823f68333dd9d466d8e226677caeba1d1f155dfbbf71fd596fdcb66c89ab28e"
            "b24fc7b4987b267c4fd97f3577fe6b47fe67d2e441a7d04bf90772ee742fdbae"
            "6da72b9055345d9463f0dfcadefddcf9b7f139ff81fc7fc37868fa9e90030000"
            "00000000000000c0cfbb02c2d3890200280000"
        );
        bytes memory result = gz.decompress();

        // Tar files are padded to 512-byte blocks, so 3 tiny files = 10240 bytes
        assertEq(result.length, 10240, "tar.gz decompressed size");

        // Check ustar magic at offset 257 (standard tar header field)
        // bytes 257-261 should be "ustar" = 0x7573746172
        assertEq(uint8(result[257]), 0x75, "tar ustar[0] 'u'");
        assertEq(uint8(result[258]), 0x73, "tar ustar[1] 's'");
        assertEq(uint8(result[259]), 0x74, "tar ustar[2] 't'");
        assertEq(uint8(result[260]), 0x61, "tar ustar[3] 'a'");
        assertEq(uint8(result[261]), 0x72, "tar ustar[4] 'r'");

        // First file entry should be "file1.txt" (bytes 0-8)
        assertEq(uint8(result[0]), 0x66, "f");      // 'f'
        assertEq(uint8(result[1]), 0x69, "i");      // 'i'
        assertEq(uint8(result[2]), 0x6c, "l");      // 'l'
        assertEq(uint8(result[3]), 0x65, "e");      // 'e'
        assertEq(uint8(result[4]), 0x31, "1");      // '1'
        assertEq(uint8(result[5]), 0x2e, ".");      // '.'
        assertEq(uint8(result[6]), 0x74, "t");      // 't'
        assertEq(uint8(result[7]), 0x78, "x");      // 'x'
        assertEq(uint8(result[8]), 0x74, "t");      // 't'

        // Check file contents: "file1 contents here\n" at offset 512
        // First byte 'f' (0x66), and last byte newline (0x0a) at position 512+19=531
        assertEq(uint8(result[512]), 0x66, "file1 cont f");
        assertEq(uint8(result[531]), 0x0a, "file1 cont newline");

        // Check second file name: "file2.txt" at offset 1024
        assertEq(uint8(result[1024]), 0x66, "file2 f");
        assertEq(uint8(result[1025]), 0x69, "file2 i");

        // Check third file name: "file3.txt" at offset 2048
        assertEq(uint8(result[2048]), 0x66, "file3 f");
        assertEq(uint8(result[2053]), 0x2e, "file3 .");
    }
}
