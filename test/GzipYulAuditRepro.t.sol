// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import {Test} from "forge-std/Test.sol";
import {Gzip} from "../src/Gzip.sol";
import {GzipYul} from "../src/GzipYul.sol";

contract GzipYulAuditRepro is Test {
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

    function _expectBothOk(string memory hexGz, bytes memory expected) internal {
        bytes memory gz = h2b(hexGz);
        assertEq(Gzip.decompress(gz), expected, "ref");
        assertEq(GzipYul.decompress(gz), expected, "yul");
    }

    function yul(bytes memory input) external pure returns (bytes memory) { return GzipYul.decompress(input); }

    function test_stored1Byte() public { _expectBothOk("1f8b08000000000000ff010100feff5a6757bc5901000000", bytes("Z")); }
    function test_storedLong() public { _expectBothOk("1f8b08000000000000ff012a00d5ff53746f72656420626c6f636b207061796c6f61642031323334353637383930217172737475767778797a9db811b12a000000", bytes("Stored block payload 1234567890!qrstuvwxyz")); }
    function test_multiBlock() public { _expectBothOk("1f8b08000000000000ff000400fbff41414141010400fbff42424242c40f60db08000000", bytes("AAAABBBB")); }
    function test_storedThenDeflate() public { _expectBothOk("1f8b08000000000000ff000a00f5ff73746f726564706172744b494dcb492c492d482c2a0100f5fb130c15000000", bytes("storedpartdeflatepart")); }
    function test_fextra() public { assertEq(GzipYul.decompress(h2b("1f8b08040000000000ff0300aabbccf348cdc9c9d75148ad28294a5448cb4ccd495104004e590eeb13000000")), bytes("Hello, extra field!")); }
    function test_fcomment() public { assertEq(GzipYul.decompress(h2b("1f8b08100000000000ff74686973206973206120636f6d6d656e74004bcecfcd4dcd2b5148cb494c5728492d2e01009090c2a011000000")), bytes("comment flag test")); }
    function test_crc32Mismatch() public { bytes memory gz = h2b("1f8b08000000000002ff2b492d2e01000000000004000000"); vm.expectRevert(abi.encodeWithSelector(GzipYul.GzipCrc32Mismatch.selector, uint32(0), uint32(0xd87f7e0c))); this.yul(gz); }
    function test_isizeMismatch() public { bytes memory gz = h2b("1f8b08000000000002ff2b492d2e01000c7e7fd800000000"); vm.expectRevert(abi.encodeWithSelector(GzipYul.GzipIsizeMismatch.selector, uint32(0), uint32(4))); this.yul(gz); }
    function test_unsupportedMethod() public { bytes memory gz = h2b("1f8b090000000000000303000000000000000000"); vm.expectRevert(abi.encodeWithSelector(GzipYul.GzipUnsupportedMethod.selector, uint8(9))); this.yul(gz); }
}
