#!/usr/bin/env python3
"""Build a deterministic corpus of repetition histories for the P3 differential.

Usage: python3 p3-corpus.py <dir-with-pyffish.so> <out.json>

Each entry is (variant, start_fen, moves).  Histories are built as
    [entry move] + 4-ply cycle x 2   (+ optionally one more ply)
so that both side-to-move parities and both "entry move" kinds (chasing /
quiet) are covered.  The corpus is generated once and then evaluated by
p3-eval.py against the unpatched and patched builds.
"""
import json
import random
import sys

sys.path.insert(0, sys.argv[1])
import pyffish as sf  # noqa: E402

OUT = sys.argv[2]

MXQ = "mxq"
sf.load_variant_config(f"""
[{MXQ}:minixiangqi]
chasingRule = axf
nMoveRule = 0
promotedSoldiersChaseable = false
""")

corpus = []


def add(variant, fen, moves):
    corpus.append((variant, fen, list(moves)))


# ---------------------------------------------------------------------------
# 1. every prefix of every xiangqi optional-game-end history already in the
#    fork's own test.py (these are the cases upstream pins)
TESTPY = [
    ("2bakabnr/9/r1n1c4/2p1p1p1p/PP7/9/4P1P1P/2C3NC1/9/1NBAKAB1R w - - 0 1",
     ["c3a3", "a8b8", "a3b3", "b8a8", "b3a3", "a8b8", "a3b3", "b8a8", "b3a3", "a8b8", "a3b3", "b8a8"]),
    ("2bakabr1/9/9/r1p1p1p2/p7R/P8/9/9/9/CC1AKA3 w - - 0 1",
     ["a5a6", "a7b7", "a6b6", "b7a7", "b6a6", "a7b7", "a6b6", "b7a7", "b6a6"]),
    ("2bakabr1/9/9/r1p1p1p2/p7R/P8/9/9/9/1C1AKA3 w - - 0 1",
     ["a5a6", "a7b7", "a6b6", "b7a7", "b6a6", "a7b7", "a6b6", "b7a7", "b6a6"]),
    ("5k3/9/9/5C3/5c3/5C3/9/9/5p3/4K4 w - - 0 1", 3 * ["f5d5", "f6d6", "d5f5", "d6f6"]),
    ("4k4/7n1/9/4pR3/9/9/4P4/9/9/4K4 w - - 0 1",
     ["f7h7"] + 2 * ["h9f8", "h7h8", "f8g6", "h8g8", "g6i7", "g8g7", "i7h9", "g7h7"]),
    ("9/3kc4/3a5/3P5/9/4p4/9/4K4/9/3C5 w - - 0 1", 3 * ["d7e7", "e5d5", "e7d7", "d5e5"]),
    ("3k5/9/9/9/9/5p3/9/5p3/5K3/5C3 w - - 0 1", 3 * ["f2e2", "f3e3", "e2f2", "e3f3"]),
    ("3k5/4P4/4b4/3C5/4c4/9/9/9/9/5K3 w - - 0 1", 3 * ["d7e7", "e8g6", "e7d7", "g6e8"]),
    ("3k5/9/9/9/9/9/9/9/cr1CAK3/9 w - - 0 1", 3 * ["d2d4", "b2b4", "d4d2", "b4b2"]),
    ("4k4/9/4b4/2c2nR2/9/9/9/9/9/3K5 w - - 0 1", 3 * ["g7g6", "f7g9", "g6g7", "g9f7"]),
    ("3P5/3k5/3nn4/9/9/9/9/9/9/5K3 w - - 0 1", 3 * ["d10e10", "d9e9", "e10d10", "e9d9"]),
    ("4ck3/9/9/9/9/2r1R4/9/9/4A4/3AK4 w - - 0 1", 3 * ["e5e4", "c5c4", "e4e5", "c4c5"]),
    ("4k4/9/9/c1c6/9/r8/9/9/C8/3K5 w - - 0 1", 3 * ["a2c2", "a5c5", "c2a2", "c5a5"]),
    ("9/4c4/3k5/3r5/9/9/4C4/9/4K4/3R5 w - - 0 1", 3 * ["e4d4", "d7e7", "d4e4", "e7d7"]),
    ("3k5/6c2/9/7P1/6c2/6P2/9/9/9/5K3 w - - 0 1", 3 * ["h7g7", "g6h6", "g7h7", "h6g6"]),
    ("4ck3/9/9/9/9/2r1R1N2/6N2/9/4A4/3AK4 w - - 0 1", 3 * ["e5e4", "c5c4", "e4e5", "c4c5"]),
    ("5k3/9/9/c8/9/P1P6/9/2C6/9/3K5 w - - 0 1", 3 * ["c3a3", "a7c7", "a3c3", "c7a7"]),
    ("4k4/9/r1r6/9/PPPP5/9/9/9/1C7/5K3 w - - 0 1",
     ["b2a2"] + 2 * ["a8b8", "a2c2", "c8d8", "c2b2", "b8a8", "b2d2", "d8c8", "d2a2"]),
    ("3k2b2/4P4/4b4/9/8p/6Bc1/6P1P/3AB4/4pp3/1p1K3R1[] w - - 0 1", 3 * ["h1h2", "h5h4", "h2h1", "h4h5"]),
    ("2baka1r1/C4rN2/9/1Rp1p4/9/9/4P4/9/4A4/4KA3 w - - 0 1",
     ["b7b9"] + 2 * ["f10e9", "b9b10", "e9f10", "b10b9"]),
    ("5k3/9/9/9/9/9/7r1/9/2nRA3c/4K4 w - - 0 1", 3 * ["e2f1", "h4h2", "f1e2", "h2h4"]),
    ("4k4/4c4/9/4p4/9/9/3rn4/3NR4/4K4/9 b - - 0 1", 3 * ["e4g5", "e2f2", "g5e4", "f2e2"]),
    ("5k3/9/9/9/9/1N2P1C2/9/4BC3/9/cr1RK4 w - - 0 1", 3 * ["b5c3", "b1c1", "c3b5", "c1b1"]),
    ("5k3/9/9/9/9/4c4/3n5/3NBA3/4A4/4K4 w - - 0 1", 3 * ["e1d1", "e5d5", "d1e1", "d5e5"]),
    ("5k3/9/9/9/9/4c4/3r5/3NB4/4A4/4K4 w - - 0 1", 3 * ["e1d1", "e5d5", "d1e1", "d5e5"]),
    ("5k3/9/9/9/9/9/9/9/9/3NK1cr1 w - - 0 1", 3 * ["d1c3", "h1h3", "c3d1", "h3h1"]),
    ("3k5/9/9/3n5/9/9/3r5/9/9/3NK4 w - - 0 1", 3 * ["d1c3", "d4c4", "c3d1", "c4d4"]),
    ("3k5/9/9/9/9/9/3r5/9/9/3NK4 w - - 0 1", 3 * ["d1c3", "d4c4", "c3d1", "c4d4"]),
    ("4k4/9/9/9/4n4/9/5C3/9/4N4/4K4 w - - 0 1", 3 * ["e2g1", "e10f10", "g1e2", "f10e10"]),
    ("5k3/9/9/9/9/1C7/1r7/9/1C7/4K4 w - - 0 1", 3 * ["b5c5", "b4c4", "c5b5", "c4b4"]),
    ("4ka3/c2R1R2c/4b4/9/9/9/9/9/9/4K4 w - - 0 1", 3 * ["f9f7", "f10e9", "f7f9", "e9f10"]),
]
for fen, moves in TESTPY:
    for n in range(4, len(moves) + 1):
        add("xiangqi", fen, moves[:n])

# ---------------------------------------------------------------------------
# 2. the same test.py wheels, but entered through one extra legal "lead-in"
#    move so that the first of the three occurrences is created by a move that
#    is not part of the cycle.  This is exactly the shape the defect needs.
def cycle_from(variant, fen, cycle_len=4, budget=1200, need=6):
    """Find cycles of cycle_len plies that restore the board from `fen`."""
    out = []
    n = 0
    try:
        l1 = sf.legal_moves(variant, fen, [])
    except Exception:
        return out
    base = fen.split()[0]
    for m1 in l1:
        for m2 in sf.legal_moves(variant, fen, [m1]):
            for m3 in sf.legal_moves(variant, fen, [m1, m2]):
                for m4 in sf.legal_moves(variant, fen, [m1, m2, m3]):
                    n += 1
                    if n > budget or len(out) >= need:
                        return out
                    seq = [m1, m2, m3, m4]
                    if sf.get_fen(variant, fen, seq).split()[0] == base:
                        out.append(seq)
    return out


rng = random.Random(20260727)
lead_added = 0
for fen, moves in TESTPY:
    # the position after the wheel's first move, then re-enter it by every legal
    # predecessor-style lead-in: use each legal move of the side to move as an
    # entry, and re-derive a cycle from the resulting position.
    try:
        entries = sf.legal_moves("xiangqi", fen, [])
    except Exception:
        continue
    rng.shuffle(entries)
    for e in entries[:6]:
        f2 = sf.get_fen("xiangqi", fen, [e])
        for cyc in cycle_from("xiangqi", f2, need=2, budget=600):
            add("xiangqi", fen, [e] + cyc * 2)
            add("xiangqi", fen, [e] + cyc * 2 + cyc[:1])
            add("xiangqi", fen, [e] + cyc * 3)
            lead_added += 3

# ---------------------------------------------------------------------------
# 3. random sparse positions, both variants, with a lead-in move
FILES7 = "abcdefg"
SQ7 = [f + str(r) for r in range(1, 8) for f in FILES7]
WP7 = ["c1", "d1", "e1", "c2", "d2", "e2", "c3", "d3", "e3"]
BP7 = ["c5", "d5", "e5", "c6", "d6", "e6", "c7", "d7", "e7"]


def make_fen7(pieces, stm="w"):
    rows = []
    for r in range(7, 0, -1):
        row, empty = "", 0
        for f in FILES7:
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
    return "/".join(rows) + f" {stm} - - 0 1"


SETS = [["R", "c"], ["R", "n"], ["C", "r"], ["N", "r"], ["R", "C", "r", "c"],
        ["R", "r"], ["C", "c"], ["N", "n"], ["R", "c", "p"], ["C", "r", "P"],
        ["R", "N", "r", "c"], ["C", "N", "r", "n"]]

rand_added = 0
attempts = 0
while rand_added < 900 and attempts < 9000:
    attempts += 1
    ts = SETS[attempts % len(SETS)]
    used = set()
    pieces = {}
    wk = rng.choice(WP7); pieces[wk] = "K"; used.add(wk)
    bk = rng.choice(BP7); pieces[bk] = "k"; used.add(bk)
    ok = True
    for t in ts:
        free = [s for s in SQ7 if s not in used]
        s = rng.choice(free); pieces[s] = t; used.add(s)
    fen = make_fen7(pieces)
    try:
        if sf.validate_fen(fen, MXQ) != sf.FEN_OK:
            continue
        entries = sf.legal_moves(MXQ, fen, [])
    except Exception:
        continue
    if not entries:
        continue
    rng.shuffle(entries)
    for e in entries[:3]:
        f2 = sf.get_fen(MXQ, fen, [e])
        for cyc in cycle_from(MXQ, f2, need=2, budget=500):
            for v in (MXQ, "minixiangqi"):
                add(v, fen, [e] + cyc * 2)
                add(v, fen, [e] + cyc * 2 + cyc[:1])
                add(v, fen, [e] + cyc * 3)
                rand_added += 3
        if rand_added >= 900:
            break

json.dump(corpus, open(OUT, "w"))
print(f"corpus entries: {len(corpus)}  (test.py prefixes + {lead_added} lead-in xiangqi + {rand_added} random)")
