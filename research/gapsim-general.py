#!/usr/bin/env python3
"""General search for a five-man wheel in which every RED move simultaneously

  * gives check (red cannon battery: red's mover is the screen on one ply, the
    black target is the screen on the other -- the mechanism pinned by
    mx-chk-003 and mx-chk-004), and
  * creates a fresh attack on the same unprotected black target,

while BLACK never checks and never attacks anything of Red's.

Pieces: red king, red cannon (static battery), red chaser, black king, black
target.  Chaser and target range over horse / chariot / cannon.

Usage: python3 gapsim-general.py <dir-containing-pyffish.so>
"""
import contextlib, importlib.util, io, pathlib, sys

HERE = pathlib.Path(__file__).resolve().parent
FILES = "abcdefg"
ALL = [(f, r) for f in range(1, 8) for r in range(1, 8)]
RED_PALACE = [(f, r) for f in range(3, 6) for r in range(1, 4)]
BLACK_PALACE = [(f, r) for f in range(3, 6) for r in range(5, 8)]
HORSE_DELTAS = [(1, 2), (1, -2), (-1, 2), (-1, -2), (2, 1), (2, -1), (-2, 1), (-2, -1)]


def name(s):
    return FILES[s[0] - 1] + str(s[1])


def horse_pairs(s):
    out = []
    for df, dr in HORSE_DELTAS:
        t = (s[0] + df, s[1] + dr)
        if 1 <= t[0] <= 7 and 1 <= t[1] <= 7:
            leg = (s[0] + (df // 2 if abs(df) == 2 else 0),
                   s[1] + (dr // 2 if abs(dr) == 2 else 0))
            out.append((t, leg))
    return out


def ray(s, d):
    out, c = [], (s[0] + d[0], s[1] + d[1])
    while 1 <= c[0] <= 7 and 1 <= c[1] <= 7:
        out.append(c)
        c = (c[0] + d[0], c[1] + d[1])
    return out


DIRS = [(1, 0), (-1, 0), (0, 1), (0, -1)]


def attacks(kind, s, t, occ):
    """Does a piece of `kind` on s attack square t, given occupied set occ?"""
    if kind == "N":
        for tt, leg in horse_pairs(s):
            if tt == t and leg not in occ:
                return True
        return False
    if kind == "R":
        for d in DIRS:
            for c in ray(s, d):
                if c == t:
                    return True
                if c in occ:
                    break
        return False
    if kind == "C":
        for d in DIRS:
            screens = 0
            for c in ray(s, d):
                if c == t:
                    return screens == 1
                if c in occ:
                    screens += 1
                    if screens > 1:
                        break
        return False
    raise ValueError(kind)


def can_move(kind, s, t, occ):
    """Quiet (non-capturing) move of `kind` from s to t; t must be empty."""
    if t in occ:
        return False
    if kind == "N":
        for tt, leg in horse_pairs(s):
            if tt == t and leg not in occ:
                return True
        return False
    for d in DIRS:                      # R and C move alike when not capturing
        for c in ray(s, d):
            if c == t:
                return True
            if c in occ:
                break
    return False


def segment(a, b):
    if a[0] == b[0]:
        lo, hi = sorted((a[1], b[1]))
        return [(a[0], r) for r in range(lo + 1, hi)]
    if a[1] == b[1]:
        lo, hi = sorted((a[0], b[0]))
        return [(f, a[1]) for f in range(lo + 1, hi)]
    return None


def black_attacks_any_red(pos, K, T, tkind):
    occ = set(pos)
    reds = [s for s, p in pos.items() if p.isupper()]
    for r in reds:
        if attacks(tkind, T, r, occ):
            return True
        if abs(K[0] - r[0]) + abs(K[1] - r[1]) == 1:
            return True
    return False


def main():
    out = []
    for K in BLACK_PALACE:
        for C in ALL:
            seg = segment(C, K)
            if not seg or len(seg) < 2:
                continue
            segset = set(seg)
            for X in seg:
                for S2 in seg:
                    if X == S2:
                        continue
                    for ckind in ("N", "R", "C"):
                        for tkind in ("N", "R", "C"):
                            for Y in ALL:
                                if Y in segset or Y in (C, K, X, S2):
                                    continue
                                for S1 in ALL:
                                    if S1 in segset or S1 in (C, K, X, Y, S2):
                                        continue
                                    for WK in RED_PALACE:
                                        if WK in (C, K, X, Y, S1, S2):
                                            continue
                                        base = {K: "k", C: "C", WK: "K"}
                                        if len(base) != 3:
                                            continue
                                        P0 = dict(base); P0[Y] = ckind; P0[S1] = tkind.lower()
                                        R1 = dict(base); R1[X] = ckind; R1[S1] = tkind.lower()
                                        B1 = dict(base); B1[X] = ckind; B1[S2] = tkind.lower()
                                        R2 = dict(base); R2[Y] = ckind; R2[S2] = tkind.lower()
                                        if len(P0) != 5 or len(B1) != 5:
                                            continue
                                        # moves of the wheel
                                        if not can_move(ckind, Y, X, set(P0) - {Y}):
                                            continue
                                        if not can_move(tkind, S1, S2, set(R1) - {S1}):
                                            continue
                                        if not can_move(ckind, X, Y, set(B1) - {X}):
                                            continue
                                        if not can_move(tkind, S2, S1, set(R2) - {S2}):
                                            continue
                                        # fresh attack created by each red move
                                        if attacks(ckind, Y, S1, set(P0)):
                                            continue
                                        if not attacks(ckind, X, S1, set(R1)):
                                            continue
                                        if attacks(ckind, X, S2, set(B1)):
                                            continue
                                        if not attacks(ckind, Y, S2, set(R2)):
                                            continue
                                        # black never touches a red man
                                        if any(black_attacks_any_red(p, K, t, tkind)
                                               for p, t in ((P0, S1), (R1, S1), (B1, S2), (R2, S2))):
                                            continue
                                        out.append(dict(K=K, C=C, X=X, Y=Y, S1=S1, S2=S2,
                                                        WK=WK, ck=ckind, tk=tkind, seg=seg))
    return out


if __name__ == "__main__":
    res = main()
    print(f"geometric candidates: {len(res)}")
    for c in res[:20]:
        print("  " + " ".join(f"{k}={name(c[k])}" for k in ("K", "C", "X", "Y", "S1", "S2", "WK"))
              + f" chaser={c['ck']} target={c['tk']}")
