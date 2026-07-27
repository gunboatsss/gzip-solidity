// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import {Test, console2} from "forge-std/Test.sol";
import {GzipAssembly} from "../src/GzipAssembly.sol";

contract DebugAsmTest is Test {
    function h2b(string memory h) internal pure returns (bytes memory b) {
        bytes memory s = bytes(h);
        b = new bytes(s.length / 2);
        for (uint256 i = 0; i < b.length; i++) {
            uint8 hi = uint8(s[i*2]); uint8 lo = uint8(s[i*2+1]);
            if (hi >= 97) hi -= 87; else if (hi >= 65) hi -= 55; else hi -= 48;
            if (lo >= 97) lo -= 87; else if (lo >= 65) lo -= 55; else lo -= 48;
            b[i] = bytes1(uint8((hi << 4) | lo));
        }
    }
    
    function test_abcPasses() public {
        bytes memory gz = h2b("1f8b08000000000000034b4c4a4e842100342a6e5a0c000000");
        bytes memory r = GzipAssembly.decompress(gz);
        console2.log("result len:", r.length);
        console2.logBytes(r);
        assertEq(r, bytes("abcabcabcabc"));
    }
}
