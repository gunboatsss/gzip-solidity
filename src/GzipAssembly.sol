// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
 * @title GzipAssembly
 * @notice Self-contained gzip decompression with assembly-optimised hot paths.
 *
 * @dev Optimisations vs. a naive pure-Solidity port:
 *      - Bit reader: no per‑bit bounds‑check; struct fields accessed in
 *        assembly to avoid Solidity memory‑load overhead on every bit.
 *      - Output buffer: MCOPY for non‑overlapping LZ77 copies and bulk
 *        operations (obGrow, obDone, stored‑block data, gzip slice).
 *        Overlapping (RLE) copies use a Solidity byte loop.
 *      - CRC‑32: tight assembly loop with word‑at‑a‑time byte extraction.
 *      - gzip header slice: MCOPY for the compressed‑data extraction.
 */
library GzipAssembly {
    error GzipInvalidMagic();
    error GzipUnsupportedMethod(uint8 cm);
    error GzipInputTooShort();
    error GzipCrc32Mismatch(uint32 expected, uint32 actual);
    error GzipIsizeMismatch(uint32 expected, uint32 actual);
    error DeflateReservedBlockType();
    error DeflateStoredLenMismatch();
    error DeflateInvalidCode();
    error DeflateInvalidDistance();

    uint8 internal constant MAX_BITS = 15;

    // ═══════════════════════════════════════════════════════════════════
    // BIT READER  (assembly — no per‑bit bounds check)
    // ═══════════════════════════════════════════════════════════════════

    struct BR { bytes data; uint256 bytePos; uint8 bitPos; }

    function brInit(bytes memory d) internal pure returns (BR memory b) {
        assembly {
            mstore(b, d)
            mstore(add(b, 0x20), 0)
            mstore(add(b, 0x40), 0)
        }
    }

    function brReadBit(BR memory b) internal pure returns (uint256 bit) {
        assembly {
            let data  := mload(b)
            let bpos  := mload(add(b, 0x20))
            let bitp  := mload(add(b, 0x40))
            let word  := mload(add(add(data, 0x20), bpos))
            bit := and(shr(bitp, shr(248, word)), 1)
            bitp := add(bitp, 1)
            if eq(bitp, 8) { bitp := 0  bpos := add(bpos, 1) }
            mstore(add(b, 0x20), bpos)
            mstore(add(b, 0x40), bitp)
        }
    }

    function brReadBits(BR memory b, uint256 n) internal pure returns (uint256 v) {
        for (uint256 i = 0; i < n; i++) if (brReadBit(b) == 1) v |= (uint256(1) << i);
    }

    function brSkipToByte(BR memory b) internal pure {
        assembly {
            if gt(mload(add(b, 0x40)), 0) {
                mstore(add(b, 0x40), 0)
                mstore(add(b, 0x20), add(mload(add(b, 0x20)), 1))
            }
        }
    }

    function brReadU16(BR memory b) internal pure returns (uint16) {
        uint256 bp = b.bytePos;
        require(uint256(b.bitPos) == 0 && bp + 2 <= b.data.length, "BR:overflow");
        uint16 v = uint16(uint8(b.data[bp])) | (uint16(uint8(b.data[bp + 1])) << 8);
        b.bytePos = bp + 2;
        return v;
    }

    function brReadBytes(BR memory b, uint256 n) internal pure returns (bytes memory r) {
        uint256 bp = b.bytePos;
        require(uint256(b.bitPos) == 0 && bp + n <= b.data.length, "BR:overflow");
        r = new bytes(n);
        for (uint256 i = 0; i < n; i++) r[i] = b.data[bp + i];
        b.bytePos = bp + n;
    }

    // ═══════════════════════════════════════════════════════════════════
    // HUFFMAN  (canonical tables, incremental decode — same as baseline)
    // ═══════════════════════════════════════════════════════════════════

    struct HT { uint16[16] firstCode; uint8[16] blCount; bytes lengths; }

    function htBuild(bytes memory lens) internal pure returns (HT memory t) {
        t.lengths = lens;
        for (uint256 i = 0; i < lens.length; i++) {
            uint8 l = uint8(lens[i]);
            if (l > 0) { require(l <= MAX_BITS, "code too long"); t.blCount[l]++; }
        }
        t.blCount[0] = 0;
        uint16 code = 0;
        for (uint8 bits = 1; bits <= MAX_BITS; bits++) {
            code = uint16((code + t.blCount[bits - 1]) << 1);
            t.firstCode[bits] = code;
        }
    }

    function htDecode(HT memory t, BR memory b) internal pure returns (uint16) {
        uint16 code = 0;
        for (uint8 len = 1; len <= MAX_BITS; len++) {
            code = uint16((uint256(code) << 1) | brReadBit(b));
            if (t.blCount[len] == 0) continue;
            uint16 first = t.firstCode[len];
            if (code >= first && code < first + t.blCount[len]) {
                uint16 off = code - first;
                uint16 cnt = 0;
                uint256 n = t.lengths.length;
                for (uint16 sym = 0; sym < n; sym++) {
                    if (uint8(t.lengths[sym]) == len) {
                        if (cnt == off) return sym;
                        cnt++;
                    }
                }
                revert("HT:sym not found");
            }
        }
        revert DeflateInvalidCode();
    }

    function htFixedLitLen() internal pure returns (HT memory t) {
        bytes memory lens = new bytes(288);
        for (uint16 i = 0; i <= 143;  i++) lens[i] = bytes1(uint8(8));
        for (uint16 i = 144; i <= 255; i++) lens[i] = bytes1(uint8(9));
        for (uint16 i = 256; i <= 279; i++) lens[i] = bytes1(uint8(7));
        for (uint16 i = 280; i <= 287; i++) lens[i] = bytes1(uint8(8));
        t = htBuild(lens);
    }

    function htFixedDist() internal pure returns (HT memory t) {
        bytes memory lens = new bytes(32);
        for (uint16 i = 0; i < 32; i++) lens[i] = bytes1(uint8(5));
        t = htBuild(lens);
    }

    // ═══════════════════════════════════════════════════════════════════
    // LENGTH / DISTANCE TABLES  (RFC 1951 §3.2.5)
    // ═══════════════════════════════════════════════════════════════════

    function lenBase(uint16 c) internal pure returns (uint16) {
        if (c <= 264) return uint16(c - 254);
        if (c <= 268) return uint16(11 + (c - 265) * 2);
        if (c <= 272) return uint16(19 + (c - 269) * 4);
        if (c <= 276) return uint16(35 + (c - 273) * 8);
        if (c <= 280) return uint16(67 + (c - 277) * 16);
        if (c <= 284) return uint16(131 + (c - 281) * 32);
        return 258;
    }
    function lenExtra(uint16 c) internal pure returns (uint8) {
        if (c <= 264) return 0; if (c <= 268) return 1; if (c <= 272) return 2;
        if (c <= 276) return 3; if (c <= 280) return 4; if (c <= 284) return 5;
        return 0;
    }
    function distBase(uint16 c) internal pure returns (uint16) {
        if (c <= 3)  return uint16(c + 1);        if (c <= 5)  return uint16((c - 2) * 2 + 1);
        if (c <= 7)  return uint16((c - 4) * 4 + 1);  if (c <= 9)  return uint16((c - 6) * 8 + 1);
        if (c <= 11) return uint16((c - 8) * 16 + 1); if (c <= 13) return uint16((c - 10) * 32 + 1);
        if (c <= 15) return uint16((c - 12) * 64 + 1);if (c <= 17) return uint16((c - 14) * 128 + 1);
        if (c <= 19) return uint16((c - 16) * 256 + 1);if (c <= 21) return uint16((c - 18) * 512 + 1);
        if (c <= 23) return uint16((c - 20) * 1024 + 1);if (c <= 25) return uint16((c - 22) * 2048 + 1);
        if (c <= 27) return uint16((c - 24) * 4096 + 1);if (c <= 29) return uint16((c - 26) * 8192 + 1);
        return 0;
    }
    function distExtra(uint16 c) internal pure returns (uint8) {
        if (c < 2) return 0;
        return uint8(c / 2 - 1);
    }

    // ═══════════════════════════════════════════════════════════════════
    // CODE‑LENGTH ALPHABET ORDER  (RFC 1951 §3.2.7)
    // ═══════════════════════════════════════════════════════════════════

    function clOrder(uint8 i) internal pure returns (uint8) {
        if (i == 0)  return 16; if (i == 1)  return 17; if (i == 2)  return 18;
        if (i == 3)  return 0;  if (i == 4)  return 8;  if (i == 5)  return 7;
        if (i == 6)  return 9;  if (i == 7)  return 6;  if (i == 8)  return 10;
        if (i == 9)  return 5;  if (i == 10) return 11; if (i == 11) return 4;
        if (i == 12) return 12; if (i == 13) return 3;  if (i == 14) return 13;
        if (i == 15) return 2;  if (i == 16) return 14; if (i == 17) return 1;
        if (i == 18) return 15; revert("bad cl idx");
    }

    function decodeDynamic(BR memory b) internal pure returns (HT memory lit, HT memory dist) {
        uint16 hlit  = uint16(brReadBits(b, 5)) + 257;
        uint16 hdist = uint16(brReadBits(b, 5)) + 1;
        uint8  hclen = uint8(brReadBits(b, 4)) + 4;
        bytes memory clLens = new bytes(19);
        for (uint8 i = 0; i < hclen; i++) clLens[clOrder(i)] = bytes1(uint8(brReadBits(b, 3)));
        HT memory clT = htBuild(clLens);
        uint16 total = hlit + hdist;
        bytes memory allLens = new bytes(total);
        uint16 n = 0; uint8 prev = 0;
        while (n < total) {
            uint16 sym = htDecode(clT, b);
            if (sym < 16) { allLens[n] = bytes1(uint8(sym)); prev = uint8(sym); n++; }
            else if (sym == 16) {
                require(n > 0, "rep w/o prev");
                uint8 rpt = uint8(brReadBits(b, 2)) + 3;
                require(n + rpt <= total, "too many");
                for (uint8 j = 0; j < rpt; j++) allLens[n + j] = bytes1(prev);
                n += rpt;
            } else if (sym == 17) {
                uint8 rpt = uint8(brReadBits(b, 3)) + 3;
                require(n + rpt <= total, "too many");
                for (uint8 j = 0; j < rpt; j++) allLens[n + j] = bytes1(0);
                prev = 0; n += rpt;
            } else if (sym == 18) {
                uint8 rpt = uint8(brReadBits(b, 7)) + 11;
                require(n + rpt <= total, "too many");
                for (uint8 j = 0; j < rpt; j++) allLens[n + j] = bytes1(0);
                prev = 0; n += rpt;
            } else { revert("bad cl sym"); }
        }
        bytes memory litLens = new bytes(hlit);
        for (uint16 i = 0; i < hlit; i++) litLens[i] = allLens[i];
        bytes memory distLens = new bytes(hdist);
        for (uint16 i = 0; i < hdist; i++) distLens[i] = allLens[hlit + i];
        lit = htBuild(litLens); dist = htBuild(distLens);
    }

    // ═══════════════════════════════════════════════════════════════════
    // OUTPUT BUFFER
    // ═══════════════════════════════════════════════════════════════════

    struct OB { bytes data; uint256 len; }

    function obNew() internal pure returns (OB memory o) { o.data = new bytes(1024); }

    function obGrow(OB memory o, uint256 need) internal pure {
        uint256 req = o.len + need;
        if (req > o.data.length) {
            uint256 nl = o.data.length; while (nl < req) nl *= 2;
            bytes memory nd = new bytes(nl);
            assembly { mcopy(add(nd, 0x20), add(mload(o), 0x20), mload(add(o, 0x20))) }
            o.data = nd;
        }
    }

    function obPut(OB memory o, uint8 b) internal pure { obGrow(o, 1); o.data[o.len++] = bytes1(b); }

    function obCopy(OB memory o, uint256 dist, uint256 length) internal pure {
        obGrow(o, length);
        if (dist >= length) {
            assembly {
                let dp := mload(o)
                let ol := mload(add(o, 0x20))
                mcopy(add(add(dp, 0x20), ol), sub(add(add(dp, 0x20), ol), dist), length)
            }
        } else {
            for (uint256 i = 0; i < length; i++) o.data[o.len + i] = o.data[o.len - dist + i];
        }
        o.len += length;
    }

    function obDone(OB memory o) internal pure returns (bytes memory r) {
        r = new bytes(o.len);
        assembly { mcopy(add(r, 0x20), add(mload(o), 0x20), mload(add(o, 0x20))) }
    }

    // ═══════════════════════════════════════════════════════════════════
    // CRC‑32  (assembly — shr(248, mload) for MSB extraction)
    // ═══════════════════════════════════════════════════════════════════

    function crc32(bytes memory data) internal pure returns (uint32 crc) {
        assembly {
            let c := 0xFFFFFFFF
            let ptr := add(data, 0x20)
            let end := add(ptr, mload(data))
            for { } lt(ptr, end) { ptr := add(ptr, 1) } {
                c := xor(c, shr(248, mload(ptr)))
                for { let j := 0 } lt(j, 8) { j := add(j, 1) } {
                    let lsb := and(c, 1)
                    c := shr(1, c)
                    if lsb { c := xor(c, 0xEDB88320) }
                }
            }
            crc := not(c)
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    // MAIN ENTRY POINT
    // ═══════════════════════════════════════════════════════════════════

    function decompress(bytes memory input) internal pure returns (bytes memory output) {
        if (input.length < 18) revert GzipInputTooShort();
        uint256 pos;
        if (uint8(input[0]) != 0x1F || uint8(input[1]) != 0x8B) revert GzipInvalidMagic();
        pos = 2;
        uint8 cm = uint8(input[pos++]); if (cm != 0x08) revert GzipUnsupportedMethod(cm);
        uint8 flg = uint8(input[pos++]); pos += 6;
        if (flg & 0x04 != 0) { uint16 x = uint16(uint8(input[pos]))|(uint16(uint8(input[pos+1]))<<8); pos += 2+x; }
        if (flg & 0x08 != 0) { for (; pos < input.length && uint8(input[pos]) != 0; pos++) {} if (pos < input.length) pos++; }
        if (flg & 0x10 != 0) { for (; pos < input.length && uint8(input[pos]) != 0; pos++) {} if (pos < input.length) pos++; }
        if (flg & 0x02 != 0) pos += 2;
        if (input.length < pos + 8) revert GzipInputTooShort();

        uint256 clen = input.length - pos - 8;
        bytes memory compressed = new bytes(clen);
        assembly { mcopy(add(compressed, 0x20), add(add(input, 0x20), pos), clen) }

        uint256 fs = input.length - 8;
        uint32 expCrc = uint32(uint8(input[fs]))|(uint32(uint8(input[fs+1]))<<8)|(uint32(uint8(input[fs+2]))<<16)|(uint32(uint8(input[fs+3]))<<24);
        uint32 expIsize = uint32(uint8(input[fs+4]))|(uint32(uint8(input[fs+5]))<<8)|(uint32(uint8(input[fs+6]))<<16)|(uint32(uint8(input[fs+7]))<<24);

        BR memory br = brInit(compressed);
        OB memory ob = obNew();
        bool bfinal;
        do {
            bfinal = brReadBit(br) == 1;
            uint8 btype = uint8(brReadBits(br, 2));
            if (btype == 0) {
                brSkipToByte(br);
                uint16 len = brReadU16(br); require(len == ~brReadU16(br), DeflateStoredLenMismatch());
                obGrow(ob, len); bytes memory data = brReadBytes(br, len);
                assembly {
                    let dp := mload(ob)
                    let ol := mload(add(ob, 0x20))
                    mcopy(add(add(dp, 0x20), ol), add(data, 0x20), len)
                }
                ob.len += len;
            } else if (btype == 1) {
                huffmanBlock(br, ob, htFixedLitLen(), htFixedDist());
            } else if (btype == 2) {
                (HT memory lit, HT memory dist) = decodeDynamic(br);
                huffmanBlock(br, ob, lit, dist);
            } else { revert DeflateReservedBlockType(); }
        } while (!bfinal);

        output = obDone(ob);
        uint32 actCrc = crc32(output); if (actCrc != expCrc) revert GzipCrc32Mismatch(expCrc, actCrc);
        uint32 actIsize = uint32(output.length & 0xFFFFFFFF); if (actIsize != expIsize) revert GzipIsizeMismatch(expIsize, actIsize);
    }

    function huffmanBlock(BR memory br, OB memory ob, HT memory lit, HT memory dist) internal pure {
        while (true) {
            uint16 sym = htDecode(lit, br);
            if (sym < 256) { obPut(ob, uint8(sym)); }
            else if (sym == 256) { break; }
            else {
                require(sym >= 257 && sym <= 285, "bad len code");
                uint16 ln = lenBase(sym); uint8 ex = lenExtra(sym); if (ex > 0) ln += uint16(brReadBits(br, ex));
                uint16 dc = htDecode(dist, br); require(dc <= 29, "bad dist code");
                uint16 ds = distBase(dc); uint8 dx = distExtra(dc); if (dx > 0) ds += uint16(brReadBits(br, dx));
                require(ds <= ob.len, DeflateInvalidDistance());
                obCopy(ob, ds, ln);
            }
        }
    }
}
