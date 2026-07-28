#!/usr/bin/env python3
"""Reachability oracle for the discovered-check chase-exemption gap (P5).

Give the chased side ONLY a king plus soldiers, and register the variant with
promotedSoldiersChaseable = false. Then chaseExempt covers every piece that side
owns, so the addChased path (position.cpp:2995) and the fake-roots path (:3066)
can contribute nothing. Any perpetual-chase verdict against that side therefore
came from the discovered-check path, which is the path P5 masks. Zero hits on an
unmasked build means the gap did not change an outcome in the sampled space.

Usage: python3 c-p5reach.py <build-dir> [samples]
Workspace scratch file for the fs-chase worktree; part of no repository.
"""
import sys
import os
import random

sys.path.insert(0, os.path.abspath(sys.argv[1]))
import pyffish  # noqa: E402

MX = "mxqexempt"
BUILTIN = "minixiangqi"
pyffish.load_variant_config(
    "[mxqexempt:minixiangqi]\nchasingRule = axf\nnMoveRule = 0\npromotedSoldiersChaseable = false\n")

FILES = "abcdefg"
SQ = [f + str(r) for r in range(1, 8) for f in FILES]
WPAL = ["c1", "d1", "e1", "c2", "d2", "e2", "c3", "d3", "e3"]
BPAL = ["c5", "d5", "e5", "c6", "d6", "e6", "c7", "d7", "e7"]
SETS = [["R", "C"], ["R", "N"], ["C", "N"], ["R", "C", "N"], ["C", "C"],
        ["R", "R"], ["N", "N"], ["R", "C", "C"], ["R", "R", "C"], ["R", "C", "N", "P"]]


def make_fen(pieces, stm="w"):
    rows = []
    for r in range(7, 0, -1):
        row, empty = "", 0
        for f in FILES:
            p = pieces.get(f + str(r))
            if p is None:
                empty += 1
            else:
                if empty:
                    row += str(empty)
                    empty = 0
                row += p
        if empty:
            row += str(empty)
        rows.append(row)
    return "/".join(rows) + " %s - - 0 1" % stm


def random_pos(rng, white_types):
    used, pieces = set(), {}
    wk, bk = rng.choice(WPAL), rng.choice(BPAL)
    pieces[wk] = "K"
    pieces[bk] = "k"
    used.update([wk, bk])
    for t in white_types:
        s = rng.choice([q for q in SQ if q not in used])
        pieces[s] = t
        used.add(s)
    for _ in range(rng.choice([1, 2, 3])):
        s = rng.choice([q for q in SQ if q not in used])
        pieces[s] = "p"
        used.add(s)
    return make_fen(pieces)


def find_cycles(fen, budget=400):
    hits, n = [], 0
    try:
        m1s = pyffish.legal_moves(MX, fen, [])
    except Exception:
        return hits
    for m1 in m1s:
        for m2 in pyffish.legal_moves(MX, fen, [m1]):
            for m3 in pyffish.legal_moves(MX, fen, [m1, m2]):
                for m4 in pyffish.legal_moves(MX, fen, [m1, m2, m3]):
                    n += 1
                    if n > budget:
                        return hits
                    seq = [m1, m2, m3, m4]
                    if pyffish.get_fen(MX, fen, seq).split()[0] != fen.split()[0]:
                        continue
                    full = seq * 2
                    if any(pyffish.gives_check(MX, fen, full[:k]) for k in range(len(full) + 1)):
                        continue
                    try:
                        f, v = pyffish.is_optional_game_end(MX, fen, full)
                        fb, vb = pyffish.is_optional_game_end(BUILTIN, fen, full)
                    except Exception:
                        continue
                    if f and v != 0 and (not fb or vb == 0):
                        hits.append((seq, v))
    return hits


def main():
    rng = random.Random(20260728)
    n = int(sys.argv[2]) if len(sys.argv) > 2 else 20000
    tried = legal = 0
    found = []
    for i in range(n):
        fen = random_pos(rng, SETS[i % len(SETS)])
        tried += 1
        if pyffish.validate_fen(fen, MX) != pyffish.FEN_OK:
            continue
        try:
            if not pyffish.legal_moves(MX, fen, []):
                continue
        except Exception:
            continue
        legal += 1
        for seq, v in find_cycles(fen):
            found.append((fen, seq, v))
            print("HIT", fen, " ".join(seq), v)
            if len(found) > 8:
                print("stopping early")
                return
    print("build=%s tried=%d legal=%d hits=%d" % (sys.argv[1], tried, legal, len(found)))


main()
