// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import {Test} from "forge-std/Test.sol";
import {GzipYul} from "../src/GzipYul.sol";

contract GzipYulTest is Test {
    function h2b(string memory h) internal pure returns (bytes memory b) {
        bytes memory s = bytes(h);
        require(s.length % 2 == 0, "hex");
        b = new bytes(s.length / 2);
        for (uint256 i = 0; i < b.length; i++) {
            uint8 hi = uint8(s[i*2]); uint8 lo = uint8(s[i*2+1]);
            if (hi >= 97) hi -= 87; else if (hi >= 65) hi -= 55; else hi -= 48;
            if (lo >= 97) lo -= 87; else if (lo >= 65) lo -= 55; else lo -= 48;
            b[i] = bytes1(uint8((hi << 4) | lo));
        }
    }
    function test_empty() public {
        assertEq(GzipYul.decompress(h2b("1f8b080000000000000303000000000000000000")).length, 0);
    }
    function test_helloWorld() public {
        assertEq(GzipYul.decompress(h2b("1f8b0800000000000003f348cdc9c9d75108cf2fca49510400d0c34aec0d000000")), bytes("Hello, World!"));
    }
    function test_singleByte() public {
        assertEq(GzipYul.decompress(h2b("1f8b08000000000000038b00004b36b2b701000000")), bytes("X"));
    }
    function test_abcRepeat() public {
        assertEq(GzipYul.decompress(h2b("1f8b08000000000000034b4c4a4e842100342a6e5a0c000000")), bytes("abcabcabcabc"));
    }
    function test_quickFox() public {
        assertEq(GzipYul.decompress(h2b("1f8b08000000000000030bc94855282ccd4cce56482aca2fcf5348cbaf50c82acd2d2856c82f4b2d5228014ae72456552aa4e4a7eb298490a01800a70ae99a59000000")), bytes("The quick brown fox jumps over the lazy dog. The quick brown fox jumps over the lazy dog."));
    }
    function test_500x() public {
        bytes memory r = GzipYul.decompress(h2b("1f8b0800000000000003aba81805230d000051ceb20af4010000"));
        assertEq(r.length, 500);
        for (uint256 i = 0; i < r.length; i++) assertEq(r[i], bytes1("x"));
    }
    function test_dynamicHuffman() public {
        assertEq(GzipYul.decompress(h2b("1f8b080000000000000305c1810140201440c155de044d6381e453c257546a7a77931752092e32676d17ab7eece5bc1fb44ae6f5c2614767d1cd4c5e4825b8c89cb55dacfab197f37ed02a99d70b871d9d453733792195e02273d676b1eac75ecefb41ab645e2f1c767416ddcc0f0c9c14af84000000")), bytes("The quick brown fox jumps over the lazy dog.The quick brown fox jumps over the lazy dog.The quick brown fox jumps over the lazy dog."));
    }

    function test_dynamicSimple() public {
        bytes memory gz = h2b("1f8b080000000000000305c10101000000c1b06c38fd23d924c9b69304a06db7edd9b23d3718000000");
        bytes memory expected = bytes("AAAABBBBCCCCDDDDEEEEFFFF");
        bytes memory r = GzipYul.decompress(gz);
        assertEq(r, expected, "dynamic simple");
    }

    function test_errorSelectors() public {
        bytes memory bad = h2b("0000000000000000000000000000000000000000");
        vm.expectRevert(GzipYul.GzipInvalidMagic.selector);
        this.extDecompress(bad);
    }

    function test_errorTooShort() public {
        bytes memory bad = h2b("1f8b");
        vm.expectRevert(GzipYul.GzipInputTooShort.selector);
        this.extDecompress(bad);
    }

    function extDecompress(bytes memory input) external pure returns (bytes memory) {
        return GzipYul.decompress(input);
    }
}
