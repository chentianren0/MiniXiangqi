#!/usr/bin/env python3
"""Agent-B bounded search for 4-ply repetition cycles with special properties.

Mode 'mutualcheck': every state of the cycle has the side to move in check.
Mode 'mixed'      : black is in check at every black turn (white perpetually
                    checks) and black's replies are not king moves (so a
                    simultaneous chase by black is at least possible).

Usage: python3 b-search.py <mode> <samples> [material]
"""
import importlib.util
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("bprobe", os.path.join(HERE, "b-probe.py"))
B = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(B)
B.setup()
pyffish = B.pyffish
AXF = B.AXF

FILES = "abcdefg"
SQUARES = [f + str(r) for r in range(1, 8) for f in FILES]
WPAL = [f + str(r) for r in "cde" for r in [1, 2, 3] for f in "cde"]
WPALACE = [f + str(r) for r in (1, 2, 3) for f in "cde"]
BPALACE = [f + str(r) for r in (5, 6, 7) for f in "cde"]


def make_fen(pieces, stm):
    """pieces: dict square -> piece char."""
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
    return "/".join(rows) + " " + stm + " - - 0 1"


def flip(fen):
    p = fen.split()
    p[1] = "b" if p[1] == "w" else "w"
    return " ".join(p)


def placement(fen):
    p = fen.split()
    return p[0] + " " + p[1]


def in_check(fen):
    return pyffish.gives_check(AXF, fen, [])


def legal(fen):
    return pyffish.legal_moves(AXF, fen, [])


def after(fen, mv):
    return pyffish.get_fen(AXF, fen, [mv])


def sample(material_w, material_b, rng):
    pieces = {}
    used = set()
    wk = rng.choice(WPALACE)
    bk = rng.choice(BPALACE)
    pieces[wk] = "K"
    pieces[bk] = "k"
    used |= {wk, bk}
    for p in material_w:
        while True:
            s = rng.choice(SQUARES)
            if s not in used:
                break
        used.add(s)
        pieces[s] = p
    for p in material_b:
        while True:
            s = rng.choice(SQUARES)
            if s not in used:
                break
        used.add(s)
        pieces[s] = p.lower()
    return pieces


def cycles_all_in_check(fen0, need_check_every_state):
    """DFS 4 plies, no captures, returning to fen0's placement."""
    out = []
    tgt = placement(fen0)
    for m1 in legal(fen0):
        f1 = after(fen0, m1)
        if need_check_every_state and not in_check(f1):
            continue
        for m2 in legal(f1):
            f2 = after(f1, m2)
            if need_check_every_state and not in_check(f2):
                continue
            for m3 in legal(f2):
                f3 = after(f2, m3)
                if need_check_every_state and not in_check(f3):
                    continue
                for m4 in legal(f3):
                    f4 = after(f3, m4)
                    if placement(f4) == tgt:
                        out.append([m1, m2, m3, m4])
    return out


def main():
    mode = sys.argv[1]
    n = int(sys.argv[2])
    mat = sys.argv[3] if len(sys.argv) > 3 else "RC/rc"
    mw, mb = mat.split("/")
    rng = random.Random(20260727)
    seen = set()
    hits = 0
    tried = 0
    for _ in range(n):
        pieces = sample(mw, mb, rng)
        fen0 = make_fen(pieces, "w")
        if placement(fen0) in seen:
            continue
        seen.add(placement(fen0))
        if pyffish.validate_fen(fen0, AXF) != pyffish.FEN_OK:
            continue
        # legality: the side NOT to move must not be attacked
        if in_check(flip(fen0)):
            continue
        if mode == "mutualcheck":
            if not in_check(fen0):
                continue
            tried += 1
            cycs = cycles_all_in_check(fen0, True)
        else:  # mixed: white checks every move; white never in check
            if in_check(fen0):
                continue
            tried += 1
            cycs = []
            for m1 in legal(fen0):
                f1 = after(fen0, m1)
                if not in_check(f1):
                    continue
                for m2 in legal(f1):
                    if m2[:2] in [s for s, p in pieces.items() if p == "k"]:
                        continue  # black king move: cannot chase directly
                    f2 = after(f1, m2)
                    if in_check(f2):
                        continue
                    for m3 in legal(f2):
                        f3 = after(f2, m3)
                        if not in_check(f3):
                            continue
                        for m4 in legal(f3):
                            f4 = after(f3, m4)
                            if placement(f4) == placement(fen0):
                                cycs.append([m1, m2, m3, m4])
            cycs = [c for c in cycs if c[1][:2] != c[3][:2] or True]
        for c in cycs:
            res = pyffish.is_optional_game_end(AXF, fen0, c * 2)
            hits += 1
            print("HIT %-42s %s -> %s" % (fen0, " ".join(c), res))
            if hits > 40:
                print("(stopped after 40 hits)")
                return
    print("mode=%s material=%s sampled=%d legal-and-filtered=%d hits=%d"
          % (mode, mat, n, tried, hits))


if __name__ == "__main__":
    main()
