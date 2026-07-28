#!/usr/bin/env python3
"""Validate the geometric candidates from gapsim-search.py with pyffish.

Every surviving candidate is a wheel in which each red move simultaneously
gives check and renews a chase of the same unprotected black horse, while
Black neither checks nor attacks anything of Red's.

Usage: python3 gapsim-validate.py <dir-containing-pyffish.so>
"""
import contextlib
import importlib.util
import io
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("gapsim_search", HERE / "gapsim-search.py")
S = importlib.util.module_from_spec(spec)
spec.loader.exec_module(S)

VARIANT = "mxq_target"
INI = """
[mxq_target:minixiangqi]
chasingRule = axf
nMoveRule = 0
promotedSoldiersChaseable = false
"""


def fen_of(placement, stm, half=0, full=1):
    rows = []
    for r in range(7, 0, -1):
        row, empty = "", 0
        for f in range(1, 8):
            p = placement.get((f, r))
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
    return "/".join(rows) + f" {stm} - - {half} {full}"


def flip(fen):
    parts = fen.split()
    parts[1] = "b" if parts[1] == "w" else "w"
    return " ".join(parts)


def black_attacks_white(pos, K, T):
    """True if the black king or the black horse attacks any white piece."""
    occ = set(pos)
    whites = [s for s, p in pos.items() if p.isupper()]
    for w in whites:
        if S.horse_attacks(T, w, occ):
            return True
        if abs(K[0] - w[0]) + abs(K[1] - w[1]) == 1:
            return True
    return False


def main():
    sys.path.insert(0, sys.argv[1])
    import pyffish as sf

    sf.load_variant_config(INI)
    print(f"engine: {sf.info()}")

    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        cands = S.main()

    n = S.name
    survivors = []
    for c in cands:
        K, C, X, Y, S1, S2, WK = c["K"], c["C"], c["X"], c["Y"], c["S1"], c["S2"], c["WK"]
        base = {K: "k", C: "C", WK: "K"}
        if len(base) != 3:
            continue
        p0 = dict(base)
        p0[Y] = "N"
        p0[S1] = "n"
        if len(p0) != 5:
            continue
        start = fen_of(p0, "w")
        mv = [n(Y) + n(X), n(S1) + n(S2), n(X) + n(Y), n(S2) + n(S1)] * 2

        ok = True
        checks = []
        for i in range(len(mv)):
            legal = sf.legal_moves(VARIANT, start, mv[:i])
            if mv[i] not in legal:
                ok = False
                break
            checks.append(sf.gives_check(VARIANT, start, mv[: i + 1]))
        if not ok:
            continue
        if checks != [True, False, True, False, True, False, True, False]:
            continue
        if sf.get_fen(VARIANT, start, mv) != fen_of(p0, "w", 8, 5):
            continue

        after_R1 = dict(base); after_R1[X] = "N"; after_R1[S1] = "n"
        after_B1 = dict(base); after_B1[X] = "N"; after_B1[S2] = "n"
        after_R2 = dict(base); after_R2[Y] = "N"; after_R2[S2] = "n"
        after_B2 = dict(base); after_B2[Y] = "N"; after_B2[S1] = "n"

        # Red attacks the black horse after each of its own moves (engine probe).
        w1 = sf.legal_moves(VARIANT, flip(fen_of(after_R1, "b")), [])
        w2 = sf.legal_moves(VARIANT, flip(fen_of(after_R2, "b")), [])
        if (n(X) + n(S1)) not in w1 or (n(Y) + n(S2)) not in w2:
            continue

        # Black never attacks anything of Red's, at any of the four board states.
        if any(black_attacks_white(p, K, t) for p, t in
               ((after_R1, S1), (after_B1, S2), (after_R2, S2), (after_B2, S1))):
            continue

        # No flying-general defence of the black horse.
        if K[0] == WK[0]:
            between = [(K[0], r) for r in range(min(K[1], WK[1]) + 1, max(K[1], WK[1]))]
            if S1 in between or S2 in between:
                continue

        survivors.append((start, mv, c))

    print(f"\nvalidated wheels: {len(survivors)}")
    for start, mv, c in survivors:
        print(f"  {start}   {' '.join(mv[:4])}   "
              f"(K={n(c['K'])} C={n(c['C'])} X={n(c['X'])} Y={n(c['Y'])} "
              f"S1={n(c['S1'])} S2={n(c['S2'])} WK={n(c['WK'])})")
    return survivors


if __name__ == "__main__":
    main()
