// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {Gzip} from "../src/Gzip.sol";
import {GzipAssembly} from "../src/GzipAssembly.sol";
import {GzipYul} from "../src/GzipYul.sol";

contract GasCompareTest is Test {
    using Gzip for bytes;

    function h2b(string memory h) internal pure returns (bytes memory b) {
        bytes memory s = bytes(h);
        b = new bytes(s.length / 2);
        for (uint256 i = 0; i < b.length; i++) {
            uint8 hi = uint8(s[i * 2]); uint8 lo = uint8(s[i * 2 + 1]);
            if (hi >= 97) hi -= 87; else if (hi >= 65) hi -= 55; else hi -= 48;
            if (lo >= 97) lo -= 87; else if (lo >= 65) lo -= 55; else lo -= 48;
            b[i] = bytes1(uint8((hi << 4) | lo));
        }
    }

    function _cmp(string memory name, string memory hexStr, bytes memory expected) internal {
        bytes memory gz = h2b(hexStr);

        uint256 g0 = gasleft();
        bytes memory r0 = Gzip.decompress(gz);
        uint256 used0 = g0 - gasleft();

        uint256 g1 = gasleft();
        bytes memory r1 = GzipAssembly.decompress(gz);
        uint256 used1 = g1 - gasleft();

        uint256 g2 = gasleft();
        bytes memory r2 = GzipYul.decompress(gz);
        uint256 used2 = g2 - gasleft();

        if (expected.length > 0) {
            assertEq(r0, expected, "sol");
            assertEq(r1, expected, "asm");
            assertEq(r2, expected, "yul");
        } else {
            assertEq(r0.length, r1.length, "asm len");
            assertEq(r0.length, r2.length, "yul len");
        }

        uint256 yulWin = used2 < used0 ? (used0 - used2) * 100 / used0 : 0;
        console2.log(string(abi.encodePacked(name, " Gzip:", vm.toString(used0),
            " Asm:", vm.toString(used1), " Yul:", vm.toString(used2),
            " YulSave:", vm.toString(yulWin), "%")));
    }

    function test_empty() public {
        _cmp("empty   ", "1f8b080000000000000303000000000000000000", "");
    }
    function test_X() public {
        _cmp("X       ", "1f8b08000000000000038b00004b36b2b701000000", bytes("X"));
    }
    function test_hello() public {
        _cmp("hello   ", "1f8b0800000000000003f348cdc9c9d75108cf2fca49510400d0c34aec0d000000", bytes("Hello, World!"));
    }
    function test_abc() public {
        _cmp("abcRpt  ", "1f8b08000000000000034b4c4a4e842100342a6e5a0c000000", bytes("abcabcabcabc"));
    }
    function test_fox() public {
        _cmp("quickFox", "1f8b08000000000000030bc94855282ccd4cce56482aca2fcf5348cbaf50c82acd2d2856c82f4b2d5228014ae72456552aa4e4a7eb298490a01800a70ae99a59000000", bytes("The quick brown fox jumps over the lazy dog. The quick brown fox jumps over the lazy dog."));
    }
    function test_500x() public {
        bytes memory gz = h2b("1f8b0800000000000003aba81805230d000051ceb20af4010000");
        uint256 g0 = gasleft(); bytes memory r0 = Gzip.decompress(gz); uint256 u0 = g0 - gasleft();
        uint256 g1 = gasleft(); bytes memory r1 = GzipAssembly.decompress(gz); uint256 u1 = g1 - gasleft();
        uint256 g2 = gasleft(); bytes memory r2 = GzipYul.decompress(gz); uint256 u2 = g2 - gasleft();
        assertEq(r0.length, 500); assertEq(r1.length, 500); assertEq(r2.length, 500);
        uint256 yw = u2 < u0 ? (u0 - u2) * 100 / u0 : 0;
        console2.log(string(abi.encodePacked("500x    Gzip:", vm.toString(u0),
            " Asm:", vm.toString(u1), " Yul:", vm.toString(u2),
            " YulSave:", vm.toString(yw), "%")));
    }
    function test_dyn() public {
        _cmp("dynamic ", "1f8b080000000000000305c1810140201440c155de044d6381e453c257546a7a77931752092e32676d17ab7eece5bc1fb44ae6f5c2614767d1cd4c5e4825b8c89cb55dacfab197f37ed02a99d70b871d9d453733792195e02273d676b1eac75ecefb41ab645e2f1c767416ddcc0f0c9c14af84000000", bytes("The quick brown fox jumps over the lazy dog.The quick brown fox jumps over the lazy dog.The quick brown fox jumps over the lazy dog."));
    }
    function test_tar() public {
        bytes memory gz = h2b("1f8b08085a6b676a0003617263686976652e74617200edd4410ac2301085e1ac3dc59c4092a689e7a99a6aa1a66047f4f836082288b8d2a2fcdf661699c5c0e44ddbf5c92df5a2e673ec24c6ba54b70af6b1de54b571a1f22ec6107c65acf3367823f68333dd9d466d8e226677caeba1d1f155dfbbf71fd596fdcb66c89ab28eb24fc7b4987b267c4fd97f3577fe6b47fe67d2e441a7d04bf90772ee742fdbae6da72b9055345d9463f0dfcadefddcf9b7f139ff81fc7fc37868fa9e9003000000000000000000c0cfbb02c2d3890200280000");
        uint256 g0 = gasleft(); bytes memory r0 = Gzip.decompress(gz); uint256 u0 = g0 - gasleft();
        uint256 g1 = gasleft(); bytes memory r1 = GzipAssembly.decompress(gz); uint256 u1 = g1 - gasleft();
        uint256 g2 = gasleft(); bytes memory r2 = GzipYul.decompress(gz); uint256 u2 = g2 - gasleft();
        assertEq(r0.length, r1.length); assertEq(r0.length, r2.length);
        uint256 yw = u2 < u0 ? (u0 - u2) * 100 / u0 : 0;
        console2.log(string(abi.encodePacked("tarGz   Gzip:", vm.toString(u0),
            " Asm:", vm.toString(u1), " Yul:", vm.toString(u2),
            " YulSave:", vm.toString(yw), "%")));
    }
}
