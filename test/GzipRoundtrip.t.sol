// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import {Test, console2} from "forge-std/Test.sol";
import {Gzip} from "../src/Gzip.sol";
import {GzipYul} from "../src/GzipYul.sol";

contract GzipRoundtripTest is Test {

    bytes constant GZ_binary = hex"1f8b08000000000000ff01c80037ff390c8c7d7247342cd8100f2f6f770d65d670e58e0351d8ae8e4f6eac342fc231b7b08716eb3fc12896b96223177494287733c28ee8ba53bdb56b8824577d53ecc28a70a61c7510a1cd89216ca16cffcaea4987477e86dbccb97046fc2e18384e51d820c5c3ef80053a88ae3996de50e801865b3698654ebf5200a5fa0939b99d7a1d7b282bf8234041f35487d86c669fccbfe0e73d7e7320ad0a757003241e752210a924798ef86d43f27cf2d0613031dcb5d8d2ef1b321fcead377f6261e547d85d8eec7f26e232b4ea16a9c8000000";
    bytes constant GZ_dynamic = hex"1f8b08000000000002ff0bc94855282ccd4cce56482aca2fcf5348cbaf50c82acd2d2856c82f4b2d5228014ae72456552aa4e4a7eb85d0482d000c9c14af84000000";
    bytes constant GZ_empty = hex"1f8b08000000000000ff03000000000000000000";
    bytes constant GZ_hello = hex"1f8b08000000000000fff348cdc9c9d75108cf2fca49510400d0c34aec0d000000";
    bytes constant GZ_repeated = hex"1f8b08000000000000ff73741c05230d00008f3381d8f4010000";
    bytes constant GZ_stored_100b = hex"1f8b08000000000000ff0164009bff000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f60616263f532c95864000000";
    bytes constant GZ_stored_1024b = hex"1f8b08000000000000ff010004fffb000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f606162636465666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9fa0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebfc0c1c2c3c4c5c6c7c8c9cacbcccdcecfd0d1d2d3d4d5d6d7d8d9dadbdcdddedfe0e1e2e3e4e5e6e7e8e9eaebecedeeeff0f1f2f3f4f5f6f7f8f9fafbfcfdfeff000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f606162636465666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9fa0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebfc0c1c2c3c4c5c6c7c8c9cacbcccdcecfd0d1d2d3d4d5d6d7d8d9dadbdcdddedfe0e1e2e3e4e5e6e7e8e9eaebecedeeeff0f1f2f3f4f5f6f7f8f9fafbfcfdfeff000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f606162636465666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9fa0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebfc0c1c2c3c4c5c6c7c8c9cacbcccdcecfd0d1d2d3d4d5d6d7d8d9dadbdcdddedfe0e1e2e3e4e5e6e7e8e9eaebecedeeeff0f1f2f3f4f5f6f7f8f9fafbfcfdfeff000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f606162636465666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9fa0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebfc0c1c2c3c4c5c6c7c8c9cacbcccdcecfd0d1d2d3d4d5d6d7d8d9dadbdcdddedfe0e1e2e3e4e5e6e7e8e9eaebecedeeeff0f1f2f3f4f5f6f7f8f9fafbfcfdfeff264c0bb700040000";
    bytes constant GZ_stored_10b = hex"1f8b08000000000000ff010a00f5ff0001020304050607080946d76c450a000000";
    bytes constant GZ_stored_1byte = hex"1f8b08000000000000ff010100feff5a6757bc5901000000";
    bytes constant GZ_stored_256b = hex"1f8b08000000000000ff010001fffe000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f606162636465666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9fa0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebfc0c1c2c3c4c5c6c7c8c9cacbcccdcecfd0d1d2d3d4d5d6d7d8d9dadbdcdddedfe0e1e2e3e4e5e6e7e8e9eaebecedeeeff0f1f2f3f4f5f6f7f8f9fafbfcfdfeff738c052900010000";
    bytes constant GZ_stored_50b = hex"1f8b08000000000000ff013200cdff000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f3031ff790cb532000000";

    function test_allFiles() external view {
        assertEq(GzipYul.decompress(GZ_binary), Gzip.decompress(GZ_binary), "binary");
        assertEq(GzipYul.decompress(GZ_dynamic), Gzip.decompress(GZ_dynamic), "dynamic");
        assertEq(GzipYul.decompress(GZ_empty), Gzip.decompress(GZ_empty), "empty");
        assertEq(GzipYul.decompress(GZ_hello), Gzip.decompress(GZ_hello), "hello");
        assertEq(GzipYul.decompress(GZ_repeated), Gzip.decompress(GZ_repeated), "repeated");
        assertEq(GzipYul.decompress(GZ_stored_100b), Gzip.decompress(GZ_stored_100b), "stored_100b");
        assertEq(GzipYul.decompress(GZ_stored_1024b), Gzip.decompress(GZ_stored_1024b), "stored_1024b");
        assertEq(GzipYul.decompress(GZ_stored_10b), Gzip.decompress(GZ_stored_10b), "stored_10b");
        assertEq(GzipYul.decompress(GZ_stored_1byte), Gzip.decompress(GZ_stored_1byte), "stored_1byte");
        assertEq(GzipYul.decompress(GZ_stored_256b), Gzip.decompress(GZ_stored_256b), "stored_256b");
        assertEq(GzipYul.decompress(GZ_stored_50b), Gzip.decompress(GZ_stored_50b), "stored_50b");
    }

    function test_gasComparison() external view {
        uint256 g0a = gasleft(); Gzip.decompress(GZ_binary); uint256 r_binary = g0a - gasleft();
        uint256 g0b = gasleft(); GzipYul.decompress(GZ_binary); uint256 y_binary = g0b - gasleft();
        console2.log(string.concat("binary ref:", vm.toString(r_binary), " yul:", vm.toString(y_binary)));
        uint256 g1a = gasleft(); Gzip.decompress(GZ_dynamic); uint256 r_dynamic = g1a - gasleft();
        uint256 g1b = gasleft(); GzipYul.decompress(GZ_dynamic); uint256 y_dynamic = g1b - gasleft();
        console2.log(string.concat("dynamic ref:", vm.toString(r_dynamic), " yul:", vm.toString(y_dynamic)));
        uint256 g2a = gasleft(); Gzip.decompress(GZ_empty); uint256 r_empty = g2a - gasleft();
        uint256 g2b = gasleft(); GzipYul.decompress(GZ_empty); uint256 y_empty = g2b - gasleft();
        console2.log(string.concat("empty ref:", vm.toString(r_empty), " yul:", vm.toString(y_empty)));
        uint256 g3a = gasleft(); Gzip.decompress(GZ_hello); uint256 r_hello = g3a - gasleft();
        uint256 g3b = gasleft(); GzipYul.decompress(GZ_hello); uint256 y_hello = g3b - gasleft();
        console2.log(string.concat("hello ref:", vm.toString(r_hello), " yul:", vm.toString(y_hello)));
        uint256 g4a = gasleft(); Gzip.decompress(GZ_repeated); uint256 r_repeated = g4a - gasleft();
        uint256 g4b = gasleft(); GzipYul.decompress(GZ_repeated); uint256 y_repeated = g4b - gasleft();
        console2.log(string.concat("repeated ref:", vm.toString(r_repeated), " yul:", vm.toString(y_repeated)));
        uint256 g5a = gasleft(); Gzip.decompress(GZ_stored_100b); uint256 r_stored_100b = g5a - gasleft();
        uint256 g5b = gasleft(); GzipYul.decompress(GZ_stored_100b); uint256 y_stored_100b = g5b - gasleft();
        console2.log(string.concat("stored_100b ref:", vm.toString(r_stored_100b), " yul:", vm.toString(y_stored_100b)));
        uint256 g6a = gasleft(); Gzip.decompress(GZ_stored_1024b); uint256 r_stored_1024b = g6a - gasleft();
        uint256 g6b = gasleft(); GzipYul.decompress(GZ_stored_1024b); uint256 y_stored_1024b = g6b - gasleft();
        console2.log(string.concat("stored_1024b ref:", vm.toString(r_stored_1024b), " yul:", vm.toString(y_stored_1024b)));
        uint256 g7a = gasleft(); Gzip.decompress(GZ_stored_10b); uint256 r_stored_10b = g7a - gasleft();
        uint256 g7b = gasleft(); GzipYul.decompress(GZ_stored_10b); uint256 y_stored_10b = g7b - gasleft();
        console2.log(string.concat("stored_10b ref:", vm.toString(r_stored_10b), " yul:", vm.toString(y_stored_10b)));
        uint256 g8a = gasleft(); Gzip.decompress(GZ_stored_1byte); uint256 r_stored_1byte = g8a - gasleft();
        uint256 g8b = gasleft(); GzipYul.decompress(GZ_stored_1byte); uint256 y_stored_1byte = g8b - gasleft();
        console2.log(string.concat("stored_1byte ref:", vm.toString(r_stored_1byte), " yul:", vm.toString(y_stored_1byte)));
        uint256 g9a = gasleft(); Gzip.decompress(GZ_stored_256b); uint256 r_stored_256b = g9a - gasleft();
        uint256 g9b = gasleft(); GzipYul.decompress(GZ_stored_256b); uint256 y_stored_256b = g9b - gasleft();
        console2.log(string.concat("stored_256b ref:", vm.toString(r_stored_256b), " yul:", vm.toString(y_stored_256b)));
        uint256 g10a = gasleft(); Gzip.decompress(GZ_stored_50b); uint256 r_stored_50b = g10a - gasleft();
        uint256 g10b = gasleft(); GzipYul.decompress(GZ_stored_50b); uint256 y_stored_50b = g10b - gasleft();
        console2.log(string.concat("stored_50b ref:", vm.toString(r_stored_50b), " yul:", vm.toString(y_stored_50b)));
    }
}
