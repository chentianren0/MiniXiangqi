#!/usr/bin/env python3
"""pyffish validation of the gapsim-general.py candidates.

Usage: python3 gapsim-general-check.py <dir-containing-pyffish.so>
"""
import importlib.util, json, pathlib, sys

HERE = pathlib.Path(__file__).resolve().parent
sp = importlib.util.spec_from_file_location("gapsim_general", HERE / "gapsim-general.py")
G = importlib.util.module_from_spec(sp)
sp.loader.exec_module(G)

VARIANT = "mxq_target"
INI = """
[mxq_target:minixiangqi]
chasingRule = axf
nMoveRule = 0
promotedSoldiersChaseable = false
"""
n = G.name


def fen_of(pl, stm, half=0, full=1):
    rows = []
    for r in range(7, 0, -1):
        row, empty = "", 0
        for f in range(1, 8):
            p = pl.get((f, r))
            if p is None:
                empty += 1
            else:
                if empty:
                    row += str(empty); empty = 0
                row += p
        if empty:
            row += str(empty)
        rows.append(row)
    return "/".join(rows) + f" {stm} - - {half} {full}"


def flip(fen):
    p = fen.split(); p[1] = "b" if p[1] == "w" else "w"; return " ".join(p)


def main():
    sys.path.insert(0, sys.argv[1])
    import pyffish as sf
    sf.load_variant_config(INI)
    print(f"engine: {sf.info()}")

    cands = G.main()
    print(f"geometric candidates: {len(cands)}")
    good = []
    for c in cands:
        K, C, X, Y, S1, S2, WK = (c[k] for k in ("K", "C", "X", "Y", "S1", "S2", "WK"))
        ck, tk = c["ck"], c["tk"]
        base = {K: "k", C: "C", WK: "K"}
        P0 = dict(base); P0[Y] = ck; P0[S1] = tk.lower()
        start = fen_of(P0, "w")
        mv = [n(Y) + n(X), n(S1) + n(S2), n(X) + n(Y), n(S2) + n(S1)] * 2

        ok, checks = True, []
        for i in range(len(mv)):
            if mv[i] not in sf.legal_moves(VARIANT, start, mv[:i]):
                ok = False; break
            checks.append(sf.gives_check(VARIANT, start, mv[: i + 1]))
        if not ok or checks != [True, False, True, False] * 2:
            continue
        if sf.get_fen(VARIANT, start, mv) != fen_of(P0, "w", 8, 5):
            continue

        R1 = dict(base); R1[X] = ck; R1[S1] = tk.lower()
        R2 = dict(base); R2[Y] = ck; R2[S2] = tk.lower()
        # red really can capture the target after each of its own moves
        if (n(X) + n(S1)) not in sf.legal_moves(VARIANT, flip(fen_of(R1, "b")), []):
            continue
        if (n(Y) + n(S2)) not in sf.legal_moves(VARIANT, flip(fen_of(R2, "b")), []):
            continue
        # the target is undefended on both squares
        def defended(pos, sq):
            q = {k: v for k, v in pos.items() if k != sq}
            q[sq] = "P"
            return any(m[2:4] == n(sq) for m in sf.legal_moves(VARIANT, fen_of(q, "b"), []))
        if defended(R1, S1) or defended(R2, S2):
            continue
        good.append((start, mv, c))

    print(f"\nfully validated wheels: {len(good)}")
    for start, mv, c in good:
        print(f"  {start}   {' '.join(mv[:4])}   chaser={c['ck']}@{n(c['Y'])}/{n(c['X'])} "
              f"target={c['tk']}@{n(c['S1'])}/{n(c['S2'])} cannon={n(c['C'])} "
              f"kings {n(c['WK'])}/{n(c['K'])}")
    json.dump([{"start": s, "moves": m,
                "c": {k: (n(v) if isinstance(v, tuple) else v)
                      for k, v in cc.items() if k != "seg"}}
               for s, m, cc in good], open(HERE / "gapsim-wheels.json", "w"), indent=1)
    return good


if __name__ == "__main__":
    main()
