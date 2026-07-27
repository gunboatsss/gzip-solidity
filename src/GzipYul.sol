// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
 * @title GzipYul
 * @notice Pure‑Yul gzip decompression with memory‑state architecture.
 */
library GzipYul {
    // Error selectors (pre-computed, used directly in assembly)
    // keccak256("GzipInvalidMagic()")      = 0xb0f25b04
    // keccak256("GzipInputTooShort()")     = 0x6d1e0b23
    // keccak256("GzipCrc32Mismatch(uint32,uint32)") = 0x6d9f3e27
    // keccak256("GzipIsizeMismatch(uint32,uint32)") = 0x61025233

    /// @dev selector 0xb0f25b04
    error GzipInvalidMagic();
    /// @dev selector 0x6d1e0b23
    error GzipInputTooShort();
    /// @dev selector 0x6d9f3e27
    error GzipCrc32Mismatch(uint32 expected, uint32 actual);
    /// @dev selector 0x61025233
    error GzipIsizeMismatch(uint32 expected, uint32 actual);

    function decompress(bytes memory input) internal pure returns (bytes memory output) {
        assembly {
            // ═══════════════════════════════════════════════════════
            //  GZIP HEADER
            // ═══════════════════════════════════════════════════════
            if lt(mload(input), 18) {
                mstore(0, 0x6d1e0b2300000000000000000000000000000000000000000000000000000000)
                revert(0, 4)
            }
            let in_ptr := add(input, 0x20)
            if or(
                iszero(eq(shr(248, mload(in_ptr)), 0x1F)),
                iszero(eq(shr(248, mload(add(in_ptr, 1))), 0x8B))
            ) {
                mstore(0, 0xb0f25b0400000000000000000000000000000000000000000000000000000000)
                revert(0, 4)
            }

            let pos := 2
            let cm := shr(248, mload(add(in_ptr, pos)))
            if iszero(eq(cm, 0x08)) {
                mstore(0, 0xb0f25b0400000000000000000000000000000000000000000000000000000000)
                revert(0, 4)
            }
            pos := add(pos, 1)
            let flg := shr(248, mload(add(in_ptr, pos)))
            pos := add(pos, 7)

            if and(flg, 0x04) {
                let xlen := or(
                    shr(248, mload(add(in_ptr, pos))),
                    shl(8, shr(248, mload(add(in_ptr, add(pos, 1)))))
                )
                pos := add(add(pos, 2), xlen)
            }
            if and(flg, 0x08) {
                for { } and(lt(pos, mload(input)),
                    iszero(iszero(shr(248, mload(add(in_ptr, pos))))))
                    { pos := add(pos, 1) } {}
                if lt(pos, mload(input)) { pos := add(pos, 1) }
            }
            if and(flg, 0x10) {
                for { } and(lt(pos, mload(input)),
                    iszero(iszero(shr(248, mload(add(in_ptr, pos))))))
                    { pos := add(pos, 1) } {}
                if lt(pos, mload(input)) { pos := add(pos, 1) }
            }
            if and(flg, 0x02) { pos := add(pos, 2) }
            if lt(mload(input), add(pos, 8)) {
                mstore(0, 0x6d1e0b2300000000000000000000000000000000000000000000000000000000)
                revert(0, 4)
            }

            let footer_start := sub(mload(input), 8)
            let footer_ptr := add(in_ptr, footer_start)
            let exp_crc := or(or(or(
                shr(248, mload(footer_ptr)),
                shl(8, shr(248, mload(add(footer_ptr, 1))))),
                shl(16, shr(248, mload(add(footer_ptr, 2))))),
                shl(24, shr(248, mload(add(footer_ptr, 3)))))
            let exp_isize := or(or(or(
                shr(248, mload(add(footer_ptr, 4))),
                shl(8, shr(248, mload(add(footer_ptr, 5))))),
                shl(16, shr(248, mload(add(footer_ptr, 6))))),
                shl(24, shr(248, mload(add(footer_ptr, 7)))))

            let clen := sub(sub(mload(input), pos), 8)

            // ═══════════════════════════════════════════════════════
            //  STATE BLOCK (heap-allocated, pointer in scratch 0x00)
            //  +0x00 br_data  +0x20 br_len  +0x40 br_bpos  +0x60 br_bitp
            //  +0x80 ob_data  +0xA0 ob_len  +0xC0 ob_cap
            // ═══════════════════════════════════════════════════════
            let S := mload(0x40)
            mstore(0x40, add(S, 0xE0))
            mstore(0x00, S)

            mstore(add(S, 0x00), add(in_ptr, pos))
            mstore(add(S, 0x20), clen)
            mstore(add(S, 0x40), 0)
            mstore(add(S, 0x60), 0)
            mstore(add(S, 0xA0), 0)
            mstore(add(S, 0xC0), 1024)

            let ob_start := mload(0x40)
            mstore(add(S, 0x80), ob_start)
            mstore(0x40, add(ob_start, 1024))

            // ═══════════════════════════════════════════════════════
            //  YUL HELPERS
            // ═══════════════════════════════════════════════════════

            function readBit(s) -> bit {
                let data := mload(add(s, 0x00))
                let bpos := mload(add(s, 0x40))
                let bitp := mload(add(s, 0x60))
                if iszero(lt(bpos, mload(add(s, 0x20)))) { revert(0, 0) }
                let word := mload(add(data, bpos))
                bit := and(shr(bitp, shr(248, word)), 1)
                bitp := add(bitp, 1)
                if eq(bitp, 8) { bitp := 0  bpos := add(bpos, 1) }
                mstore(add(s, 0x40), bpos)
                mstore(add(s, 0x60), bitp)
            }

            function readBits(s, n) -> val {
                val := 0
                for { let i := 0 } lt(i, n) { i := add(i, 1) } {
                    if readBit(s) { val := or(val, shl(i, 1)) }
                }
            }

            function skipToByte(s) {
                if mload(add(s, 0x60)) {
                    mstore(add(s, 0x60), 0)
                    mstore(add(s, 0x40), add(mload(add(s, 0x40)), 1))
                }
            }

            function lenBase(c) -> b {
                if lt(c, 265) { b := sub(c, 254) leave }
                if lt(c, 269) { b := add(11, mul(sub(c, 265), 2)) leave }
                if lt(c, 273) { b := add(19, mul(sub(c, 269), 4)) leave }
                if lt(c, 277) { b := add(35, mul(sub(c, 273), 8)) leave }
                if lt(c, 281) { b := add(67, mul(sub(c, 277), 16)) leave }
                if lt(c, 285) { b := add(131, mul(sub(c, 281), 32)) leave }
                b := 258
            }
            function lenExtra(c) -> e {
                if lt(c, 265) { e := 0 leave }
                if lt(c, 269) { e := 1 leave }
                if lt(c, 273) { e := 2 leave }
                if lt(c, 277) { e := 3 leave }
                if lt(c, 281) { e := 4 leave }
                if lt(c, 285) { e := 5 leave }
                e := 0
            }
            function distBase(c) -> b {
                switch c
                case 0{b:=1} case 1{b:=2} case 2{b:=3} case 3{b:=4} case 4{b:=5}
                case 5{b:=7} case 6{b:=9} case 7{b:=13} case 8{b:=17} case 9{b:=25}
                case 10{b:=33} case 11{b:=49} case 12{b:=65} case 13{b:=97}
                case 14{b:=129} case 15{b:=193} case 16{b:=257} case 17{b:=385}
                case 18{b:=513} case 19{b:=769} case 20{b:=1025} case 21{b:=1537}
                case 22{b:=2049} case 23{b:=3073} case 24{b:=4097} case 25{b:=6145}
                case 26{b:=8193} case 27{b:=12289} case 28{b:=16385} case 29{b:=24577}
                default{b:=0}
            }
            function distExtra(c) -> e {
                if lt(c, 2) { e := 0 leave }
                e := sub(div(c, 2), 1)
            }
            function clOrder(i) -> o {
                switch i
                case 0{o:=16} case 1{o:=17} case 2{o:=18} case 3{o:=0} case 4{o:=8}
                case 5{o:=7} case 6{o:=9} case 7{o:=6} case 8{o:=10} case 9{o:=5}
                case 10{o:=11} case 11{o:=4} case 12{o:=12} case 13{o:=3}
                case 14{o:=13} case 15{o:=2} case 16{o:=14} case 17{o:=1}
                case 18{o:=15} default{o:=0}
            }

            function decodeFixedLitLen(s) -> sym {
                let code := 0
                for { let i := 0 } lt(i, 7) { i := add(i, 1) } {
                    code := or(shl(1, code), readBit(s))
                }
                if lt(code, 24) { sym := add(256, code) leave }
                code := or(shl(1, code), readBit(s))
                if iszero(lt(code, 48)) {
                    if lt(code, 200) {
                        if lt(code, 192) { sym := sub(code, 48) }
                        if iszero(lt(code, 192)) { sym := add(280, sub(code, 192)) }
                        leave
                    }
                }
                code := or(shl(1, code), readBit(s))
                if iszero(lt(code, 400)) {
                    if lt(code, 512) { sym := add(144, sub(code, 400)) leave }
                }
                // invalid Huffman code — revert without data
                revert(0, 0)
            }

            function htBuild(lens_ptr, lens_len) -> tbl {
                let size := add(560, lens_len)
                tbl := mload(0x40)
                mstore(0x40, add(tbl, size))
                // zero firstCode (16 × uint256 = 512 bytes)
                for { let i := 0 } lt(i, 16) { i := add(i, 1) } {
                    mstore(add(tbl, shl(5, i)), 0)
                }
                // zero blCount (16 bytes at tbl+512)
                mstore(add(tbl, 512), 0)
                mstore(add(tbl, 528), lens_len)
                let dst := add(tbl, 560)
                for { let i := 0 } lt(i, lens_len) { i := add(i, 1) } {
                    let l := shr(248, mload(add(lens_ptr, i)))
                    mstore8(add(dst, i), l)
                    if l {
                        let cp := add(add(tbl, 512), l)
                        mstore8(cp, add(shr(248, mload(cp)), 1))
                    }
                }
                let code := 0
                for { let bits := 1 } lt(bits, 16) { bits := add(bits, 1) } {
                    code := shl(1, add(code,
                        shr(248, mload(add(add(tbl, 512), sub(bits, 1))))))
                    mstore(add(tbl, shl(5, bits)), code)
                }
            }

            function htDecode(tbl, s) -> sym {
                let code := 0
                let nSyms := mload(add(tbl, 528))
                for { let l := 1 } lt(l, 16) { l := add(l, 1) } {
                    code := or(shl(1, code), readBit(s))
                    let cnt := shr(248, mload(add(add(tbl, 512), l)))
                    if iszero(cnt) { continue }
                    let first := mload(add(tbl, shl(5, l)))
                    if and(iszero(lt(code, first)), lt(code, add(first, cnt))) {
                        let off := sub(code, first)
                        let c := 0
                        let ls := add(tbl, 560)
                        for { let x := 0 } lt(x, nSyms) { x := add(x, 1) } {
                            if eq(shr(248, mload(add(ls, x))), l) {
                                if eq(c, off) { sym := x leave }
                                c := add(c, 1)
                            }
                        }
                        leave
                    }
                }
            }

            function decodeDynamic(s) -> lit_tbl, dist_tbl {
                let hlit  := add(readBits(s, 5), 257)
                let hdist := add(readBits(s, 5), 1)
                let hclen := add(readBits(s, 4), 4)

                let cl_lens := mload(0x40)
                mstore(0x40, add(cl_lens, 19))
                mstore(cl_lens, 0)
                mstore(add(cl_lens, 16), 0)
                for { let i := 0 } lt(i, hclen) { i := add(i, 1) } {
                    mstore8(add(cl_lens, clOrder(i)), readBits(s, 3))
                }
                let cl_tbl := htBuild(cl_lens, 19)

                let total := add(hlit, hdist)
                let all := mload(0x40)
                mstore(0x40, add(all, total))
                let n := 0
                let prev := 0

                for { } lt(n, total) { } {
                    let sym := htDecode(cl_tbl, s)
                    switch sym
                    case 16 {
                        if iszero(n) { revert(0, 0) }
                        let rpt := add(readBits(s, 2), 3)
                        if gt(add(n, rpt), total) { revert(0, 0) }
                        for { let j := 0 } lt(j, rpt) { j := add(j, 1) } {
                            mstore8(add(all, add(n, j)), prev)
                        }
                        n := add(n, rpt)
                    }
                    case 17 {
                        let rpt := add(readBits(s, 3), 3)
                        if gt(add(n, rpt), total) { revert(0, 0) }
                        for { let j := 0 } lt(j, rpt) { j := add(j, 1) } {
                            mstore8(add(all, add(n, j)), 0)
                        }
                        prev := 0
                        n := add(n, rpt)
                    }
                    case 18 {
                        let rpt := add(readBits(s, 7), 11)
                        if gt(add(n, rpt), total) { revert(0, 0) }
                        for { let j := 0 } lt(j, rpt) { j := add(j, 1) } {
                            mstore8(add(all, add(n, j)), 0)
                        }
                        prev := 0
                        n := add(n, rpt)
                    }
                    default {
                        if iszero(lt(sym, 16)) { revert(0, 0) }
                        mstore8(add(all, n), sym)
                        prev := sym
                        n := add(n, 1)
                    }
                }

                let ll := mload(0x40)
                mstore(0x40, add(ll, hlit))
                for { let i := 0 } lt(i, hlit) { i := add(i, 1) } {
                    mstore8(add(ll, i), shr(248, mload(add(all, i))))
                }
                let dl := mload(0x40)
                mstore(0x40, add(dl, hdist))
                for { let i := 0 } lt(i, hdist) { i := add(i, 1) } {
                    mstore8(add(dl, i), shr(248, mload(add(all, add(hlit, i)))))
                }
                lit_tbl  := htBuild(ll, hlit)
                dist_tbl := htBuild(dl, hdist)
            }

            // ── output buffer ──────────────────────────────────────
            function obGrow(s, need) {
                let olen := mload(add(s, 0xA0))
                let req := add(olen, need)
                let ocap := mload(add(s, 0xC0))
                if gt(req, ocap) {
                    let nc := ocap
                    for { } lt(nc, req) { nc := shl(1, nc) } {}
                    let nd := mload(0x40)
                    mstore(0x40, add(nd, nc))
                    mcopy(nd, mload(add(s, 0x80)), olen)
                    mstore(add(s, 0x80), nd)
                    mstore(add(s, 0xC0), nc)
                }
            }
            function obPut(s, b) {
                obGrow(s, 1)
                let olen := mload(add(s, 0xA0))
                mstore8(add(mload(add(s, 0x80)), olen), b)
                mstore(add(s, 0xA0), add(olen, 1))
            }
            function obCopy(s, dist, length) {
                obGrow(s, length)
                let od := mload(add(s, 0x80))
                let ol := mload(add(s, 0xA0))
                if iszero(lt(dist, length)) {
                    mcopy(add(od, ol), sub(add(od, ol), dist), length)
                }
                if lt(dist, length) {
                    for { let i := 0 } lt(i, length) { i := add(i, 1) } {
                        mstore8(
                            add(add(od, ol), i),
                            shr(248, mload(add(add(od, sub(ol, dist)), i)))
                        )
                    }
                }
                mstore(add(s, 0xA0), add(ol, length))
            }

            function crc32(ptr, plen) -> crc {
                crc := 0xFFFFFFFF
                let end := add(ptr, plen)
                for { } lt(ptr, end) { ptr := add(ptr, 1) } {
                    crc := xor(crc, shr(248, mload(ptr)))
                    for { let j := 0 } lt(j, 8) { j := add(j, 1) } {
                        let lsb := and(crc, 1)
                        crc := shr(1, crc)
                        if lsb { crc := xor(crc, 0xEDB88320) }
                    }
                }
                crc := xor(crc, 0xFFFFFFFF)
            }

            // ═══════════════════════════════════════════════════════
            //  LOG helpers (write to event topics)
            // ═══════════════════════════════════════════════════════

            // ═══════════════════════════════════════════════════════
            //  MAIN BLOCK LOOP
            // ═══════════════════════════════════════════════════════

            for { } 1 { } {
                let bfinal := readBit(S)
                let btype := readBits(S, 2)


                switch btype
                case 0 {
                    skipToByte(S)
                    let len := or(readBits(S, 8), shl(8, readBits(S, 8)))
                    let nlen := or(readBits(S, 8), shl(8, readBits(S, 8)))
                    if iszero(eq(len, and(not(nlen), 0xFFFF))) { revert(0, 0) }
                    obGrow(S, len)
                    let od := mload(add(S, 0x80))
                    let ol := mload(add(S, 0xA0))
                    for { let i := 0 } lt(i, len) { i := add(i, 1) } {
                        mstore8(add(add(od, ol), i), readBits(S, 8))
                    }
                    mstore(add(S, 0xA0), add(ol, len))
                }
                case 1 {
                    for { } 1 { } {
                        let sym := decodeFixedLitLen(S)


                        if lt(sym, 256) {
                            obPut(S, sym)
                            continue
                        }
                        if eq(sym, 256) { break }
                        if or(lt(sym, 257), gt(sym, 285)) { revert(0, 0) }
                        let ln := lenBase(sym)
                        let ex := lenExtra(sym)


                        if ex { ln := add(ln, readBits(S, ex)) }
                        // Read 5-bit distance code using Huffman ordering:
                        // code = (code<<1) | bit  (NOT val|(bit<<i) as readBits does)
                        let dc := 0
                        for { let i := 0 } lt(i, 5) { i := add(i, 1) } {
                            dc := or(shl(1, dc), readBit(S))
                        }


                        if gt(dc, 29) { revert(0, 0) }
                        let ds := distBase(dc)
                        let dx := distExtra(dc)


                        if dx { ds := add(ds, readBits(S, dx)) }


                        if gt(ds, mload(add(S, 0xA0))) {
                            revert(0, 0)
                        }
                        obCopy(S, ds, ln)
                    }
                }
                case 2 {
                    let lit, dist := decodeDynamic(S)
                    for { } 1 { } {
                        let sym := htDecode(lit, S)
                        if lt(sym, 256) { obPut(S, sym) continue }
                        if eq(sym, 256) { break }
                        if or(lt(sym, 257), gt(sym, 285)) { revert(0, 0) }
                        let ln := lenBase(sym)
                        let ex := lenExtra(sym)
                        if ex { ln := add(ln, readBits(S, ex)) }
                        let dc := htDecode(dist, S)
                        if gt(dc, 29) { revert(0, 0) }
                        let ds := distBase(dc)
                        let dx := distExtra(dc)
                        if dx { ds := add(ds, readBits(S, dx)) }
                        if gt(ds, mload(add(S, 0xA0))) { revert(0, 0) }
                        obCopy(S, ds, ln)
                    }
                }
                default { revert(0, 0) }

                if bfinal { break }
            }

            // ═══════════════════════════════════════════════════════
            //  FINALIZE
            // ═══════════════════════════════════════════════════════
            let olen := mload(add(S, 0xA0))
            output := mload(0x40)
            mstore(output, olen)
            mstore(0x40, add(add(output, 0x20), olen))
            mcopy(add(output, 0x20), mload(add(S, 0x80)), olen)

            let act_crc := crc32(add(output, 0x20), olen)


            if iszero(eq(act_crc, exp_crc)) {
                mstore(0, 0x6d9f3e2700000000000000000000000000000000000000000000000000000000)
                mstore(4, exp_crc)
                mstore(36, act_crc)
                revert(0, 68)
            }
            if iszero(eq(and(olen, 0xFFFFFFFF), exp_isize)) {
                mstore(0, 0x6102523300000000000000000000000000000000000000000000000000000000)
                mstore(4, exp_isize)
                mstore(36, and(olen, 0xFFFFFFFF))
                revert(0, 68)
            }
        }
    }
}
