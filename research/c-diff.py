#!/usr/bin/env python3
"""Differential of is_optional_game_end between two pyffish builds.

Usage: python3 c-diff.py dump  <build-dir> <variant> <seed> <positions> <out-file>
       python3 c-diff.py cmp   <file-a> <file-b>

Enumerates random small positions, finds 4-ply cycles that restore the position,
and records the adjudication of the 8-, 9- and 10-ply histories built from each
cycle. Workspace scratch file for the fs-chase worktree; part of no repository.
"""
import sys
import os
import random

FILES = "abcdefg"
SQ7 = [f + str(r) for r in range(1, 8) for f in FILES]
WPAL7 = ["c1", "d1", "e1", "c2", "d2", "e2", "c3", "d3", "e3"]
BPAL7 = ["c5", "d5", "e5", "c6", "d6", "e6", "c7", "d7", "e7"]

INI = """
[mxqaxf:minixiangqi]
chasingRule = axf
nMoveRule = 0

[mxqexempt:minixiangqi]
chasingRule = axf
nMoveRule = 0
promotedSoldiersChaseable = false
"""


XFILES = "abcdefghi"
XSQ = [f + str(r) for r in range(1, 11) for f in XFILES]
XWPAL = [f + str(r) for r in range(1, 4) for f in "def"]
XBPAL = [f + str(r) for r in range(8, 11) for f in "def"]
XINVENTORY = ["R", "R", "C", "C", "N", "N", "A", "A", "B", "B", "P", "P", "P"]


def make_fen_x(pieces, stm):
    rows = []
    for r in range(10, 0, -1):
        row, empty = "", 0
        for f in XFILES:
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


def random_pos_x(rng):
    used, pieces = set(), {}
    wk, bk = rng.choice(XWPAL), rng.choice(XBPAL)
    pieces[wk] = "K"
    pieces[bk] = "k"
    used.update([wk, bk])
    for upper, n in ((True, rng.randint(2, 5)), (False, rng.randint(2, 5))):
        for t in rng.sample(XINVENTORY, n):
            free = [s for s in XSQ if s not in used]
            if not free:
                break
            s = rng.choice(free)
            pieces[s] = t if upper else t.lower()
            used.add(s)
    return make_fen_x(pieces, rng.choice(["w", "b"]))


def make_fen(pieces, stm):
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


# Mini Xiangqi inventory per side, minus the king.
INVENTORY = ["R", "R", "C", "C", "N", "N", "P", "P", "P", "P", "P"]


def random_pos(rng):
    used = set()
    pieces = {}
    wk = rng.choice(WPAL7)
    bk = rng.choice(BPAL7)
    pieces[wk] = "K"
    pieces[bk] = "k"
    used.update([wk, bk])
    nw = rng.randint(2, 5)
    nb = rng.randint(2, 5)
    for pool, upper in ((rng.sample(INVENTORY, nw), True), (rng.sample(INVENTORY, nb), False)):
        for t in pool:
            free = [s for s in SQ7 if s not in used]
            if not free:
                break
            s = rng.choice(free)
            pieces[s] = t if upper else t.lower()
            used.add(s)
    return make_fen(pieces, rng.choice(["w", "b"]))


def rev(m):
    return m[2:4] + m[0:2]


def cycles(sf, variant, fen, cap):
    """4-ply cycles m1 m2 rev(m1) rev(m2) that return to the start position."""
    out = []
    try:
        m1s = sf.legal_moves(variant, fen, [])
    except Exception:
        return out
    for m1 in m1s:
        if len(m1) != 4:
            continue
        try:
            m2s = sf.legal_moves(variant, fen, [m1])
        except Exception:
            continue
        for m2 in m2s:
            if len(m2) != 4:
                continue
            cyc = [m1, m2, rev(m1), rev(m2)]
            try:
                if sf.get_fen(variant, fen, cyc).split()[:2] != fen.split()[:2]:
                    continue
            except Exception:
                continue
            out.append(cyc)
            if len(out) >= cap:
                return out
    return out


def dump(build, variant, seed, npos, outfile):
    sys.path.insert(0, os.path.abspath(build))
    import pyffish as sf
    sf.load_variant_config(INI)
    rng = random.Random(seed)
    gen = random_pos_x if variant in ("xiangqi", "manchu", "supply") else random_pos
    lines = []
    ncyc = 0
    for _ in range(npos):
        fen = gen(rng)
        # Histories that begin at the first of the three occurrences.
        for cyc in cycles(sf, variant, fen, 6):
            ncyc += 1
            for extra in (0, 1, 2):
                mv = cyc * 2 + cyc[:extra]
                try:
                    r = sf.is_optional_game_end(variant, fen, mv)
                except Exception:
                    r = ("err", 0)
                lines.append("%s|%s|%s|%s" % (fen, " ".join(mv), r[0], r[1] if r[0] else "-"))
        # Histories that begin one move BEFORE the first occurrence: an entry move,
        # then the wheel. This is the shape the repetition window's parity depends on.
        try:
            entries = sf.legal_moves(variant, fen, [])
        except Exception:
            entries = []
        for entry in entries[:8]:
            try:
                after = sf.get_fen(variant, fen, [entry])
            except Exception:
                continue
            for cyc in cycles(sf, variant, after, 3):
                ncyc += 1
                for extra in (0, 1):
                    mv = [entry] + cyc * 2 + cyc[:extra]
                    try:
                        r = sf.is_optional_game_end(variant, fen, mv)
                    except Exception:
                        r = ("err", 0)
                    lines.append("%s|%s|%s|%s" % (fen, " ".join(mv), r[0], r[1] if r[0] else "-"))
    with open(outfile, "w") as fh:
        fh.write("\n".join(lines) + "\n")
    sys.stderr.write("%s %s: %d cycles, %d adjudications\n" % (build, variant, ncyc, len(lines)))


def cmp_files(a, b):
    la = open(a).read().splitlines()
    lb = open(b).read().splitlines()
    if len(la) != len(lb):
        print("LENGTH MISMATCH %d vs %d" % (len(la), len(lb)))
    diffs = 0
    for x, y in zip(la, lb):
        if x != y:
            diffs += 1
            if diffs <= 20:
                print("A: %s\nB: %s" % (x, y))
    print("compared %d rows, %d differing" % (min(len(la), len(lb)), diffs))
    return diffs


if __name__ == "__main__":
    if sys.argv[1] == "dump":
        dump(sys.argv[2], sys.argv[3], int(sys.argv[4]), int(sys.argv[5]), sys.argv[6])
    else:
        sys.exit(1 if cmp_files(sys.argv[2], sys.argv[3]) else 0)
