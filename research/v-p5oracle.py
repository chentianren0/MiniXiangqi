#!/usr/bin/env python3
"""P5 reachability oracle, independent of the implementer's.

Every chase-target path except the discovered-check one masks chaseExempt, so if the
chased side owns nothing but its king and unpromoted soldiers, a non-empty chase set
against it can only have come from the discovered-check path. Run this against the
final build and against the P5-reverted build and diff: any difference is a position
where the P5 mask changes an adjudication.

Usage: python3 v-p5oracle.py <dir-with-pyffish.so> <seed> <samples>
"""
import random
import sys
import pathlib

BUILD = pathlib.Path(sys.argv[1]).resolve()
SEED = int(sys.argv[2])
SAMPLES = int(sys.argv[3])
sys.path.insert(0, str(BUILD))
import pyffish as sf  # noqa: E402

sf.load_variant_config("""
[xqexempt:xiangqi]
promotedSoldiersChaseable = false
""")
V = "xqexempt"


def reverse(m):
    return m[2:4] + m[0:2]


def make_fen(rng):
    grid = [[None] * 9 for _ in range(10)]
    pf = [3, 4, 5]
    wk = (rng.choice([0, 1, 2]), rng.choice(pf))
    bk = (rng.choice([7, 8, 9]), rng.choice(pf))
    grid[wk[0]][wk[1]] = "K"
    grid[bk[0]][bk[1]] = "k"
    # Black: king plus unpromoted soldiers only (rank index >= 5 keeps them unpromoted)
    for _ in range(rng.randint(1, 3)):
        r, f = rng.randrange(5, 10), rng.randrange(9)
        if grid[r][f] is None:
            grid[r][f] = "p"
    # White: anything
    for _ in range(rng.randint(3, 6)):
        r, f = rng.randrange(10), rng.randrange(9)
        if grid[r][f] is None:
            grid[r][f] = rng.choice("RRNNCC")
    rows = []
    for r in range(9, -1, -1):
        row, empty = "", 0
        for f in range(9):
            c = grid[r][f]
            if c is None:
                empty += 1
            else:
                if empty:
                    row += str(empty)
                    empty = 0
                row += c
        if empty:
            row += str(empty)
        rows.append(row)
    fen = "/".join(rows) + f" {rng.choice('wb')} - - 0 1"
    try:
        return fen if sf.validate_fen(fen, V) == sf.FEN_OK else None
    except Exception:  # noqa: BLE001
        return None


def quiet(fen, moves):
    return [m for m in sf.legal_moves(V, fen, moves)
            if len(m) == 4 and not sf.is_capture(V, fen, moves, m)]


rng = random.Random(SEED)
emitted = 0
attempt = 0
while emitted < SAMPLES and attempt < SAMPLES * 400:
    attempt += 1
    fen = make_fen(rng)
    if fen is None:
        continue
    try:
        hist = []
        for _ in range(rng.choice([1, 2])):
            q = quiet(fen, hist)
            if not q:
                break
            hist.append(rng.choice(q))
        if not hist:
            continue
        l1 = quiet(fen, hist)
        rng.shuffle(l1)
        for m1 in l1[:12]:
            h1 = hist + [m1]
            l2 = quiet(fen, h1)
            rng.shuffle(l2)
            for m2 in l2[:12]:
                h2 = h1 + [m2]
                if reverse(m1) not in sf.legal_moves(V, fen, h2):
                    continue
                h3 = h2 + [reverse(m1)]
                if reverse(m2) not in sf.legal_moves(V, fen, h3):
                    continue
                h4 = h3 + [reverse(m2)]
                if sf.get_fen(V, fen, h4).split()[:2] != sf.get_fen(V, fen, hist).split()[:2]:
                    continue
                w = [m1, m2, reverse(m1), reverse(m2)]
                full = hist + w * 3
                for L in (len(hist) + n for n in (8, 9, 10, 11, 12)):
                    mv = full[:L]
                    flag, value = sf.is_optional_game_end(V, fen, mv)
                    print(f"p5\t{fen}\t{int(flag)}\t{value if flag else 0}\t{' '.join(mv)}")
                emitted += 1
    except Exception:  # noqa: BLE001
        continue
