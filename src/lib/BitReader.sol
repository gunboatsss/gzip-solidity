// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
 * @title BitReader
 * @notice Utility for reading bits from a byte stream (LSB-first packing per DEFLATE spec)
 * @dev Used by DEFLATE/gzip decompression. Tracks position across byte and bit boundaries.
 */
library BitReader {
    struct State {
        bytes data;
        uint256 bytePos; // current byte index
        uint8 bitPos;    // current bit position within the current byte (0-7)
    }

    /**
     * @notice Initialize a new BitReader over the given byte array
     */
    function init(bytes memory data) internal pure returns (State memory) {
        return State({data: data, bytePos: 0, bitPos: 0});
    }

    /**
     * @notice Read a single bit (0 or 1). Advances the bit position.
     * @dev Bits are packed LSB-first: bit 0 is the least-significant bit of a byte.
     */
    function readBit(State memory self) internal pure returns (uint8) {
        require(self.bytePos < self.data.length, "BitReader: EOF");
        uint8 byteVal = uint8(self.data[self.bytePos]);
        uint8 bit = uint8((byteVal >> self.bitPos) & 1);
        self.bitPos++;
        if (self.bitPos == 8) {
            self.bitPos = 0;
            self.bytePos++;
        }
        return bit;
    }

    /**
     * @notice Read n bits into a uint256 (LSB first). Advances position by n bits.
     * @param n Number of bits to read (max 256)
     * @return value The bits assembled as an unsigned integer
     */
    function readBits(State memory self, uint8 n) internal pure returns (uint256) {
        uint256 result = 0;
        for (uint8 i = 0; i < n; i++) {
            if (readBit(self) == 1) {
                result |= (uint256(1) << i);
            }
        }
        return result;
    }

    /**
     * @notice Read n bits as a uint16 (convenience for small values like lengths/distances)
     */
    function readBits16(State memory self, uint8 n) internal pure returns (uint16) {
        return uint16(readBits(self, n));
    }

    /**
     * @notice Read n bits as a uint8
     */
    function readBits8(State memory self, uint8 n) internal pure returns (uint8) {
        return uint8(readBits(self, n));
    }

    /**
     * @notice Skip to the next byte boundary. If already aligned, does nothing.
     */
    function skipToByteBoundary(State memory self) internal pure {
        if (self.bitPos != 0) {
            self.bitPos = 0;
            self.bytePos++;
        }
    }

    /**
     * @notice Read n bytes (requires byte alignment). Advances byte position by n.
     */
    function readAlignedBytes(State memory self, uint256 n)
        internal
        pure
        returns (bytes memory)
    {
        require(self.bitPos == 0, "BitReader: not aligned");
        require(self.bytePos + n <= self.data.length, "BitReader: overflow");
        bytes memory result = new bytes(n);
        for (uint256 i = 0; i < n; i++) {
            result[i] = self.data[self.bytePos + i];
        }
        self.bytePos += n;
        return result;
    }

    /**
     * @notice Read a uint16 from two aligned bytes (little-endian). Requires byte alignment.
     */
    function readAlignedUint16(State memory self) internal pure returns (uint16) {
        bytes memory b = readAlignedBytes(self, 2);
        return uint16(uint8(b[0])) | (uint16(uint8(b[1])) << 8);
    }

    /**
     * @notice Read a uint32 from four aligned bytes (little-endian). Requires byte alignment.
     */
    function readAlignedUint32(State memory self) internal pure returns (uint32) {
        bytes memory b = readAlignedBytes(self, 4);
        return
            uint32(uint8(b[0])) |
            (uint32(uint8(b[1])) << 8) |
            (uint32(uint8(b[2])) << 16) |
            (uint32(uint8(b[3])) << 24);
    }

    /**
     * @notice Returns true if the reader has more data (bytes or bits) available
     */
    function hasMore(State memory self) internal pure returns (bool) {
        return
            self.bytePos < self.data.length ||
            (self.bytePos == self.data.length && self.bitPos > 0);
    }

    /**
     * @notice Returns true if currently at a byte boundary
     */
    function isByteAligned(State memory self) internal pure returns (bool) {
        return self.bitPos == 0;
    }
}
