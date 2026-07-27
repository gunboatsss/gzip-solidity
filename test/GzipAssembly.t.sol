// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {GzipAssembly} from "../src/GzipAssembly.sol";

contract GzipAssemblyTest is Test {
    function hexToBytes(string memory h) internal pure returns (bytes memory b) {
        bytes memory s = bytes(h);
        require(s.length % 2 == 0, "hex");
        b = new bytes(s.length / 2);
        for (uint256 i = 0; i < b.length; i++) {
            uint8 hi = hc(s[i * 2]);
            uint8 lo = hc(s[i * 2 + 1]);
            b[i] = bytes1(uint8((hi << 4) | lo));
        }
    }

    function hc(bytes1 c) internal pure returns (uint8 v) {
        v = uint8(c);
        if (v >= 48 && v <= 57) return v - 48;
        if (v >= 65 && v <= 70) return v - 55;
        if (v >= 97 && v <= 102) return v - 87;
        revert("bad hex");
    }

    // external wrapper so vm.expectRevert can catch across call depth
    function extDecompress(bytes memory input) external pure returns (bytes memory) {
        return GzipAssembly.decompress(input);
    }

    function test_empty() public {
        bytes memory gz =
            hexToBytes("1f8b080000000000000303000000000000000000");
        assertEq(GzipAssembly.decompress(gz).length, 0);
    }

    function test_singleByte() public {
        bytes memory gz =
            hexToBytes("1f8b08000000000000038b00004b36b2b701000000");
        assertEq(GzipAssembly.decompress(gz), bytes("X"));
    }

    function test_helloWorld() public {
        bytes memory gz = hexToBytes(
            "1f8b0800000000000003f348cdc9c9d75108cf2fca49510400d0c34aec0d000000"
        );
        assertEq(GzipAssembly.decompress(gz), bytes("Hello, World!"));
    }

    function test_abcRepeat() public {
        bytes memory gz =
            hexToBytes("1f8b08000000000000034b4c4a4e842100342a6e5a0c000000");
        assertEq(GzipAssembly.decompress(gz), bytes("abcabcabcabc"));
    }

    function test_quickFox() public {
        bytes memory gz = hexToBytes(
            "1f8b08000000000000030bc94855282ccd4cce56482aca2fcf5348cbaf50c82acd2d2856c82f4b2d5228014ae72456552aa4e4a7eb298490a01800a70ae99a59000000"
        );
        assertEq(
            GzipAssembly.decompress(gz),
            bytes(
                "The quick brown fox jumps over the lazy dog. The quick brown fox jumps over the lazy dog."
            )
        );
    }

    function test_500x() public {
        bytes memory gz =
            hexToBytes("1f8b0800000000000003aba81805230d000051ceb20af4010000");
        bytes memory r = GzipAssembly.decompress(gz);
        assertEq(r.length, 500);
        for (uint256 i = 0; i < r.length; i++) assertEq(r[i], bytes1("x"));
    }

    function test_dynamicHuffman() public {
        bytes memory gz = hexToBytes(
            "1f8b080000000000000305c1810140201440c155de044d6381e453c257546a7a77931752092e32676d17ab7eece5bc1fb44ae6f5c2614767d1cd4c5e4825b8c89cb55dacfab197f37ed02a99d70b871d9d453733792195e02273d676b1eac75ecefb41ab645e2f1c767416ddcc0f0c9c14af84000000"
        );
        assertEq(
            GzipAssembly.decompress(gz),
            bytes(
                "The quick brown fox jumps over the lazy dog."
                "The quick brown fox jumps over the lazy dog."
                "The quick brown fox jumps over the lazy dog."
            )
        );
    }

    function test_invalidMagic() public {
        bytes memory bad =
            hexToBytes("0000000000000000000000000000000000000000");
        vm.expectRevert(GzipAssembly.GzipInvalidMagic.selector);
        this.extDecompress(bad);
    }

    function test_tooShort() public {
        bytes memory bad = hexToBytes("1f8b");
        vm.expectRevert(GzipAssembly.GzipInputTooShort.selector);
        this.extDecompress(bad);
    }

    function test_tarGz() public {
        bytes memory gz = hexToBytes(
            "1f8b08085a6b676a0003617263686976652e74617200edd4410ac2301085e1ac"
            "3dc59c4092a689e7a99a6aa1a66047f4f836082288b8d2a2fcdf661699c5c0e4"
            "4ddbf5c92df5a2e673ec24c6ba54b70af6b1de54b571a1f22ec6107c65acf336"
            "7823f68333dd9d466d8e226677caeba1d1f155dfbbf71fd596fdcb66c89ab28e"
            "b24fc7b4987b267c4fd97f3577fe6b47fe67d2e441a7d04bf90772ee742fdbae"
            "6da72b9055345d9463f0dfcadefddcf9b7f139ff81fc7fc37868fa9e90030000"
            "00000000000000c0cfbb02c2d3890200280000"
        );
        bytes memory r = this.extDecompress(gz);
        assertEq(r.length, 10240, "tar size");
        assertEq(uint8(r[257]), 0x75);
        assertEq(uint8(r[258]), 0x73);
        assertEq(uint8(r[259]), 0x74);
        assertEq(uint8(r[260]), 0x61);
        assertEq(uint8(r[261]), 0x72);
    }
}
