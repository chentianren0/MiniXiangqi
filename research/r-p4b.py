#!/usr/bin/env python3
"""Is B's P4 (discovered-check path ignores chaseExempt) REACHABLE as a sustained violation?

Oracle: give the victim side ONLY a king plus soldiers. Under the accepted contract and
under the fork's addChased/fake-roots masks, that side can never be perpetually chased.
Any AXF chase violation against such a side must have come from the unmasked
discovered-check path at position.cpp:3081-3091 -> P4 is reachable.
"""
import sys, os, random, itertools
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from r_harness import *  # noqa
import pyffish  # noqa

setup()
FILES = "abcdefg"
SQ = [f + str(r) for r in range(1, 8) for f in FILES]
WP = ["c1", "d1", "e1", "c2", "d2", "e2", "c3", "d3", "e3"]
BP = ["c5", "d5", "e5", "c6", "d6", "e6", "c7", "d7", "e7"]


def make_fen(pieces, stm="w"):
    grid = {}
    for sq, p in pieces.items():
        grid[sq] = p
    rows = []
    for r in range(7, 0, -1):
        row, empty = "", 0
        for f in FILES:
            p = grid.get(f + str(r))
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
    """White: king + given piece types.  Black: king + 1-2 soldiers only."""
    used = set()
    pieces = {}
    wk = rng.choice(WP); pieces[wk] = "K"; used.add(wk)
    bk = rng.choice(BP); pieces[bk] = "k"; used.add(bk)
    for t in white_types:
        free = [s for s in SQ if s not in used]
        s = rng.choice(free); pieces[s] = t; used.add(s)
    for _ in range(rng.choice([1, 2])):
        free = [s for s in SQ if s not in used]
        s = rng.choice(free); pieces[s] = "p"; used.add(s)
    return make_fen(pieces)


def find_cycles(fen, budget=400):
    """Search 4-ply cycles w1 b1 w2 b2 restoring the position; return violations."""
    hits = []
    try:
        wm = pyffish.legal_moves(MX, fen, [])
    except Exception:
        return hits
    if not wm:
        return hits
    n = 0
    for m1 in wm:
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
                    # no ply may be a check: isolates the CHASE branch
                    if any(pyffish.gives_check(MX, fen, full[:k]) for k in range(len(full) + 1)):
                        continue
                    try:
                        f, v = pyffish.is_optional_game_end(MX, fen, full)
                        fb, vb = pyffish.is_optional_game_end(BUILTIN, fen, full)
                    except Exception:
                        continue
                    # built-in has no chasing rule: a decisive AXF value with a
                    # built-in draw is necessarily a chase verdict
                    if f and v != 0 and (not fb or vb == 0):
                        hits.append((seq, v))
    return hits


def main():
    rng = random.Random(20260727)
    sets = [["R", "C"], ["R", "N"], ["C", "N"], ["R", "C", "N"], ["C", "C"], ["R", "R"], ["N", "N"], ["R", "C", "C"]]
    tried = legalpos = 0
    found = []
    for i in range(int(sys.argv[1]) if len(sys.argv) > 1 else 20000):
        ws = sets[i % len(sets)]
        fen = random_pos(rng, ws)
        tried += 1
        if pyffish.validate_fen(fen, MX) != pyffish.FEN_OK:
            continue
        try:
            if not pyffish.legal_moves(MX, fen, []):
                continue
        except Exception:
            continue
        legalpos += 1
        for seq, v in find_cycles(fen):
            found.append((fen, seq, v))
            print("HIT", fen, " ".join(seq), v)
            if len(found) > 8:
                print("stopping early"); return
    print("tried=%d legal=%d hits=%d" % (tried, legalpos, len(found)))


main()

