#!/usr/bin/env python3
"""Same wheel search, but allow one or two extra men on the black horse's
horse-legs so that the chase is one-way: Red's horse attacks the black horse
and the black horse does not attack back.

Usage: python3 gapsim-blocked.py <dir-containing-pyffish.so>
"""
import contextlib, importlib.util, io, itertools, pathlib, sys

HERE = pathlib.Path(__file__).resolve().parent


def _load(nm, f):
    sp = importlib.util.spec_from_file_location(nm, HERE / f)
    m = importlib.util.module_from_spec(sp)
    sp.loader.exec_module(m)
    return m


S = _load("gapsim_search", "gapsim-search.py")
V = _load("gapsim_validate", "gapsim-validate.py")
VARIANT = V.VARIANT
n = S.name

BLOCKERS = ["C", "P", "R", "p", "r", "c"]


def leg(a, b):
    df, dr = b[0] - a[0], b[1] - a[1]
    return (a[0] + (df // 2 if abs(df) == 2 else 0), a[1] + (dr // 2 if abs(dr) == 2 else 0))


def main():
    sys.path.insert(0, sys.argv[1])
    import pyffish as sf

    sf.load_variant_config(V.INI)
    print(f"engine: {sf.info()}")
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        cands = S.main()

    results = []
    for c in cands:
        K, C, X, Y, S1, S2, WK = (c[k] for k in ("K", "C", "X", "Y", "S1", "S2", "WK"))
        segset = set(c["seg"])
        core = {K: "k", C: "C", WK: "K"}
        if len(core) != 3:
            continue

        need = []
        for src, dst in ((S1, X), (S2, Y)):
            L = leg(src, dst)
            if L not in (C, WK):
                need.append(L)
        need = sorted(set(need))
        if len(need) != 1:            # keep the piece count at six
            continue
        L = need[0]
        if L in segset or L in (K, C, WK, X, Y, S1, S2):
            continue
        if L in (leg(X, Y), leg(Y, X), leg(X, S1), leg(Y, S2), leg(S1, S2), leg(S2, S1)):
            continue

        for blocker in BLOCKERS:
            pieces = dict(core)
            pieces[L] = blocker
            p0 = dict(pieces); p0[Y] = "N"; p0[S1] = "n"
            if len(p0) != 6:
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

            aR1 = dict(pieces); aR1[X] = "N"; aR1[S1] = "n"
            aB1 = dict(pieces); aB1[X] = "N"; aB1[S2] = "n"
            aR2 = dict(pieces); aR2[Y] = "N"; aR2[S2] = "n"
            aB2 = dict(pieces); aB2[Y] = "N"; aB2[S1] = "n"

            # Red's horse attacks the black horse after each red move
            w1 = sf.legal_moves(VARIANT, V.flip(V.fen_of(aR1, "b")), [])
            w2 = sf.legal_moves(VARIANT, V.flip(V.fen_of(aR2, "b")), [])
            if (n(X) + n(S1)) not in w1 or (n(Y) + n(S2)) not in w2:
                continue

            # Black attacks nothing of Red's in any of the four states
            def black_hits(pos):
                fen = V.fen_of(pos, "b")
                moves = sf.legal_moves(VARIANT, fen, []) if fen.split()[1] == "b" else []
                return [m for m in moves
                        if pos.get((S.FILES.index(m[2]) + 1, int(m[3])), "").isupper()]
            hits = []
            for pos in (aR1, aB1, aR2, aB2):
                hits += black_hits(pos)
            if hits:
                continue

            # the black horse must be undefended on both of its squares
            def defended_by_black(pos, sq):
                q = {k: v for k, v in pos.items() if k != sq}
                q[sq] = "P"
                return any(m[2:4] == n(sq) for m in sf.legal_moves(VARIANT, V.fen_of(q, "b"), []))
            if defended_by_black(aR1, S1) or defended_by_black(aR2, S2):
                continue

            results.append((blocker, n(L), start, mv, c))

    print(f"\none-way-chase wheels: {len(results)}")
    for blocker, L, start, mv, c in results:
        print(f"  blocker {blocker}@{L}  {start}  {' '.join(mv[:4])}  "
              f"(K={n(c['K'])} C={n(c['C'])} X={n(c['X'])} Y={n(c['Y'])} "
              f"S1={n(c['S1'])} S2={n(c['S2'])} WK={n(c['WK'])})")
    return results


if __name__ == "__main__":
    main()
