#!/usr/bin/env python3
"""Rank the surviving wheels: Black must never chase (no attack on a white piece
after a black move); report whether Red's horse stands en prise after its own
moves, and whether it is defended there.

Usage: python3 gapsim-rank.py <dir-containing-pyffish.so>
"""
import contextlib, importlib.util, io, pathlib, sys

HERE = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("gapsim_search", HERE / "gapsim-search.py")
S = importlib.util.module_from_spec(spec)
spec.loader.exec_module(S)
spec2 = importlib.util.spec_from_file_location("gapsim_validate", HERE / "gapsim-validate.py")
V = importlib.util.module_from_spec(spec2)
spec2.loader.exec_module(V)

VARIANT = V.VARIANT


def main():
    sys.path.insert(0, sys.argv[1])
    import pyffish as sf

    sf.load_variant_config(V.INI)
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        cands = S.main()
    n = S.name

    rows = []
    for c in cands:
        K, C, X, Y, S1, S2, WK = (c[k] for k in ("K", "C", "X", "Y", "S1", "S2", "WK"))
        base = {K: "k", C: "C", WK: "K"}
        if len(base) != 3:
            continue
        p0 = dict(base); p0[Y] = "N"; p0[S1] = "n"
        if len(p0) != 5:
            continue
        start = V.fen_of(p0, "w")
        mv = [n(Y) + n(X), n(S1) + n(S2), n(X) + n(Y), n(S2) + n(S1)] * 2
        ok, checks = True, []
        for i in range(len(mv)):
            if mv[i] not in sf.legal_moves(VARIANT, start, mv[:i]):
                ok = False; break
            checks.append(sf.gives_check(VARIANT, start, mv[: i + 1]))
        if not ok or checks != [True, False, True, False] * 2:
            continue
        if sf.get_fen(VARIANT, start, mv) != V.fen_of(p0, "w", 8, 5):
            continue

        aR1 = dict(base); aR1[X] = "N"; aR1[S1] = "n"
        aB1 = dict(base); aB1[X] = "N"; aB1[S2] = "n"
        aR2 = dict(base); aR2[Y] = "N"; aR2[S2] = "n"
        aB2 = dict(base); aB2[Y] = "N"; aB2[S1] = "n"

        w1 = sf.legal_moves(VARIANT, V.flip(V.fen_of(aR1, "b")), [])
        w2 = sf.legal_moves(VARIANT, V.flip(V.fen_of(aR2, "b")), [])
        if (n(X) + n(S1)) not in w1 or (n(Y) + n(S2)) not in w2:
            continue

        # Black must not attack a white piece after either of its own moves
        if V.black_attacks_white(aB1, K, S2) or V.black_attacks_white(aB2, K, S1):
            continue
        if K[0] == WK[0]:
            between = [(K[0], r) for r in range(min(K[1], WK[1]) + 1, max(K[1], WK[1]))]
            if S1 in between or S2 in between:
                continue

        mutual1 = S.horse_attacks(S1, X, set(aR1))
        mutual2 = S.horse_attacks(S2, Y, set(aR2))
        # is Red's horse defended on X / on Y?  probe: can a white piece recapture there
        def defended(pos, sq):
            q = dict(pos); q[sq] = "n"          # pretend a black piece stands there
            fen = V.fen_of(q, "w")
            return any(m[2:4] == n(sq) for m in sf.legal_moves(VARIANT, fen, []))
        defX = defended({k: v for k, v in aR1.items() if k != X}, X)
        defY = defended({k: v for k, v in aR2.items() if k != Y}, Y)
        rows.append((mutual1 + mutual2, not (defX and defY), start, mv, c, mutual1, mutual2, defX, defY))

    rows.sort(key=lambda r: (r[0], r[1]))
    print(f"wheels where Black never chases: {len(rows)}")
    for score, undef, start, mv, c, m1, m2, dX, dY in rows[:25]:
        print(f"  mutual={m1},{m2} defX={dX} defY={dY}  {start}  {' '.join(mv[:4])}  "
              f"(K={n(c['K'])} C={n(c['C'])} X={n(c['X'])} Y={n(c['Y'])} S1={n(c['S1'])} S2={n(c['S2'])} WK={n(c['WK'])})")


if __name__ == "__main__":
    main()
