#!/usr/bin/env python3
"""Search for a Mini Xiangqi wheel in which EVERY red move simultaneously
gives check and renews a chase of the same unprotected black piece.

Skeleton (a cannon battery, as pinned by mx-chk-003 / mx-chk-004):

  white cannon C is static and aimed at the black king K along a rank or file;
  the squares strictly between C and K are the "segment".
  white horse H shuttles X <-> Y, with X on the segment and Y off it.
  black horse T shuttles S1 <-> S2, with S2 on the segment and S1 off it.

  R1: H Y->X   segment holds {X}      -> 1 screen -> check
  B1: T S1->S2 segment holds {X,S2}   -> 2 screens -> no check (interposition)
  R2: H X->Y   segment holds {S2}     -> 1 screen -> check
  B2: T S2->S1 segment holds {}       -> 0 screens -> no check, back to start

  For the chase, require the white horse to attack the black horse after every
  white move: X attacks S1 and Y attacks S2.  A horse's attack is never along a
  line and the two squares of a horse shuttle have disjoint attack sets, so each
  such attack is unambiguously new from the square the horse now occupies --
  renewal holds under either reading of the accepted renewal rule.

Emits candidates; pyffish validation is done separately.
"""
import itertools
import sys

FILES = "abcdefg"


def name(s):
    f, r = s
    return FILES[f - 1] + str(r)


ALL = [(f, r) for f in range(1, 8) for r in range(1, 8)]
RED_PALACE = [(f, r) for f in range(3, 6) for r in range(1, 4)]
BLACK_PALACE = [(f, r) for f in range(3, 6) for r in range(5, 8)]

HORSE_DELTAS = [(1, 2), (1, -2), (-1, 2), (-1, -2), (2, 1), (2, -1), (-2, 1), (-2, -1)]


def horse_targets(s):
    """(target, blocking_square) pairs for a horse on s, ignoring occupancy."""
    out = []
    f, r = s
    for df, dr in HORSE_DELTAS:
        t = (f + df, r + dr)
        if not (1 <= t[0] <= 7 and 1 <= t[1] <= 7):
            continue
        block = (f + (df // 2 if abs(df) == 2 else 0), r + (dr // 2 if abs(dr) == 2 else 0))
        out.append((t, block))
    return out


def horse_attacks(s, t, occupied):
    for tt, block in horse_targets(s):
        if tt == t and block not in occupied:
            return True
    return False


def segment(a, b):
    """Squares strictly between a and b on a shared rank or file, else None."""
    if a[0] == b[0]:
        lo, hi = sorted((a[1], b[1]))
        return [(a[0], r) for r in range(lo + 1, hi)]
    if a[1] == b[1]:
        lo, hi = sorted((a[0], b[0]))
        return [(f, a[1]) for f in range(lo + 1, hi)]
    return None


def king_adjacent(k, s):
    return abs(k[0] - s[0]) + abs(k[1] - s[1]) == 1


def main():
    found = []
    for K in BLACK_PALACE:
        for C in ALL:
            if C == K:
                continue
            seg = segment(C, K)
            if not seg or len(seg) < 2:
                continue
            segset = set(seg)
            for X, S2 in itertools.permutations(seg, 2):
                for Y, _b in horse_targets(X):
                    if Y in segset or Y == K or Y == C:
                        continue
                    for S1, _b2 in horse_targets(S2):
                        if S1 in segset or S1 in (K, C, X, Y):
                            continue
                        occ_after_R1 = {C, K, X, S1}
                        occ_after_R2 = {C, K, Y, S2}
                        if not horse_attacks(X, S1, occ_after_R1):
                            continue
                        if not horse_attacks(Y, S2, occ_after_R2):
                            continue
                        # black horse must never be defended by its own king
                        if king_adjacent(K, S1) or king_adjacent(K, S2):
                            continue
                        for WK in RED_PALACE:
                            if WK in (C, K, X, Y, S1, S2):
                                continue
                            found.append(dict(K=K, C=C, X=X, Y=Y, S1=S1, S2=S2, WK=WK, seg=seg))
    print(f"raw geometric candidates: {len(found)}")
    for c in found[:40]:
        print(
            "  K=%s C=%s seg=%s X=%s Y=%s S1=%s S2=%s WK=%s"
            % (
                name(c["K"]), name(c["C"]), "".join(name(s) for s in c["seg"]),
                name(c["X"]), name(c["Y"]), name(c["S1"]), name(c["S2"]), name(c["WK"]),
            )
        )
    return found


if __name__ == "__main__":
    main()
