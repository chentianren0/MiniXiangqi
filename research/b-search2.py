#!/usr/bin/env python3
"""Agent-B search v2: closed repetition cycles in which the side to move is in
check at EVERY state (the necessary and sufficient shape of a mutual perpetual
check under Fairy-Stockfish's adjudication), at cycle length 4 and 6.

Usage: python3 b-search2.py <samples> <material w/b> [seed]
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


def key(f):
    q = f.split()
    return q[0] + " " + q[1]


def main():
    n = int(sys.argv[1])
    mw, mb = sys.argv[2].split("/")
    rng = random.Random(int(sys.argv[3]) if len(sys.argv) > 3 else 1)
    succ_cache = {}

    def succ(f):
        """states reachable in one ply where the new side to move is in check"""
        r = succ_cache.get(f)
        if r is None:
            r = []
            for m in pf.legal_moves(AXF, f, []):
                g = pf.get_fen(AXF, f, [m])
                if pf.gives_check(AXF, g, []):
                    r.append((m, g))
            succ_cache[f] = r
        return r

    seen, tried, hits, d4, d6 = set(), 0, 0, 0, 0
    for i in range(n):
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
        if key(f0) in seen:
            continue
        seen.add(key(f0))
        if pf.validate_fen(f0, AXF) != pf.FEN_OK:
            continue
        if pf.gives_check(AXF, flip(f0), []):
            continue
        if not pf.gives_check(AXF, f0, []):
            continue
        tried += 1
        k0 = key(f0)
        lvl1 = succ(f0)
        if not lvl1:
            continue
        for m1, f1 in lvl1:
            for m2, f2 in succ(f1):
                for m3, f3 in succ(f2):
                    for m4, f4 in succ(f3):
                        if key(f4) == k0:
                            d4 += 1
                            hits += 1
                            print("CYCLE4 %s : %s %s %s %s -> %s"
                                  % (f0, m1, m2, m3, m4,
                                     pf.is_optional_game_end(AXF, f0, [m1, m2, m3, m4] * 2)))
                            if hits > 20:
                                return
                            continue
                        for m5, f5 in succ(f4):
                            for m6, f6 in succ(f5):
                                if key(f6) == k0:
                                    d6 += 1
                                    hits += 1
                                    mv = [m1, m2, m3, m4, m5, m6]
                                    print("CYCLE6 %s : %s -> %s"
                                          % (f0, " ".join(mv),
                                             pf.is_optional_game_end(AXF, f0, mv * 2)))
                                    if hits > 20:
                                        return
    print("material=%s sampled=%d in-check-legal=%d cycles4=%d cycles6=%d"
          % (sys.argv[2], n, tried, d4, d6))


if __name__ == "__main__":
    main()
