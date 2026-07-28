#!/usr/bin/env python3
"""Agent-B search: a 4-ply cycle in which white perpetually checks and black
(the checked side) simultaneously sustains a chase.

Detection of black's chase is done by a deletion control: remove one white
non-king piece; if the same 8-ply sequence is still legal and now adjudicates
as a loss for BLACK, black's chase was sustained in the original position.

Usage: python3 b-search3.py <samples> <material w/b> [seed]
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
pf, AXF = B.pyffish, B.AXF

FILES = "abcdefg"
SQUARES = [f + str(r) for r in range(1, 8) for f in FILES]
WPALACE = [f + str(r) for r in (1, 2, 3) for f in "cde"]
BPALACE = [f + str(r) for r in (5, 6, 7) for f in "cde"]


def make_fen(p, stm):
    rows = []
    for r in range(7, 0, -1):
        row, e = "", 0
        for f in FILES:
            c = p.get(f + str(r))
            if c is None:
                e += 1
            else:
                if e:
                    row += str(e)
                    e = 0
                row += c
        if e:
            row += str(e)
        rows.append(row)
    return "/".join(rows) + " " + stm + " - - 0 1"


def flip(f):
    q = f.split()
    q[1] = "b" if q[1] == "w" else "w"
    return " ".join(q)


def kk(f):
    q = f.split()
    return q[0] + " " + q[1]


def playable(fen, moves):
    for i, m in enumerate(moves):
        if m not in pf.legal_moves(AXF, fen, moves[:i]):
            return False
    return True


def main():
    n = int(sys.argv[1])
    mw, mb = sys.argv[2].split("/")
    rng = random.Random(int(sys.argv[3]) if len(sys.argv) > 3 else 3)
    seen, tried, cycles, hits = set(), 0, 0, 0
    for _ in range(n):
        p, u = {}, set()
        wk, bk = rng.choice(WPALACE), rng.choice(BPALACE)
        p[wk], p[bk] = "K", "k"
        u |= {wk, bk}
        for c in mw + mb.lower():
            while True:
                s = rng.choice(SQUARES)
                if s not in u:
                    break
            u.add(s)
            p[s] = c
        f0 = make_fen(p, "w")
        if kk(f0) in seen:
            continue
        seen.add(kk(f0))
        if pf.validate_fen(f0, AXF) != pf.FEN_OK:
            continue
        if pf.gives_check(AXF, flip(f0), []) or pf.gives_check(AXF, f0, []):
            continue
        tried += 1
        bksq = bk
        for m1 in pf.legal_moves(AXF, f0, []):
            f1 = pf.get_fen(AXF, f0, [m1])
            if not pf.gives_check(AXF, f1, []):
                continue
            for m2 in pf.legal_moves(AXF, f0, [m1]):
                if m2[:2] == bksq:
                    continue          # black king move: cannot chase directly
                f2 = pf.get_fen(AXF, f0, [m1, m2])
                if pf.gives_check(AXF, f2, []):
                    continue
                for m3 in pf.legal_moves(AXF, f0, [m1, m2]):
                    f3 = pf.get_fen(AXF, f0, [m1, m2, m3])
                    if not pf.gives_check(AXF, f3, []):
                        continue
                    for m4 in pf.legal_moves(AXF, f0, [m1, m2, m3]):
                        f4 = pf.get_fen(AXF, f0, [m1, m2, m3, m4])
                        if kk(f4) != kk(f0):
                            continue
                        cycles += 1
                        cyc = [m1, m2, m3, m4] * 2
                        base = pf.is_optional_game_end(AXF, f0, cyc)
                        # deletion controls: drop one white non-king piece
                        for sq, pc in list(p.items()):
                            if not pc.isupper() or pc == "K":
                                continue
                            q = dict(p)
                            del q[sq]
                            g0 = make_fen(q, "w")
                            if pf.validate_fen(g0, AXF) != pf.FEN_OK:
                                continue
                            if pf.gives_check(AXF, flip(g0), []):
                                continue
                            if not playable(g0, cyc):
                                continue
                            r = pf.is_optional_game_end(AXF, g0, cyc)
                            if r[0] and r[1] > 30000:
                                hits += 1
                                print("MIXED %s : %s  base=%s  | drop %s%s -> %s"
                                      % (f0, " ".join([m1, m2, m3, m4]), base, pc, sq, r))
                                if hits > 10:
                                    return
    print("material=%s sampled=%d roots=%d checkcycles=%d mixed=%d"
          % (sys.argv[2], n, tried, cycles, hits))


if __name__ == "__main__":
    main()
