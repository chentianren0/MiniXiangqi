#!/usr/bin/env python3
"""Independent verification probe for mx-chs-031 (written by the verifier, not the builder).

Usage: python3 vfy031-probe.py <build-dir> [more-build-dirs...]

For each named case it walks every prefix of the move history and reports, per ply:
  - the FEN reached
  - the occurrence count of (piece placement, side to move) among plies 0..n
  - is_optional_game_end (flag, and value ONLY when the flag is true)
  - whether the side to move is in check
"""
import json
import pathlib
import sys

INI = """
[mxq_target:minixiangqi]
chasingRule = axf
nMoveRule = 0
promotedSoldiersChaseable = false
"""
V = "mxq_target"

FX = pathlib.Path("/Users/tianren/coding/minixiangqi/gap-chs031/fixtures/rules")


def ident(fen):
    """Position identity per docs/xiangqi-rules.md line 38: placement + side to move only."""
    p = fen.split()
    return (p[0], p[1])


def walk(sf, name, start, moves, verbose=True):
    counts = {}
    rows = []
    for n in range(len(moves) + 1):
        pre = moves[:n]
        fen = sf.get_fen(V, start, pre)
        k = ident(fen)
        counts[k] = counts.get(k, 0) + 1
        ended, value = sf.is_optional_game_end(V, start, pre)
        chk = sf.gives_check(V, start, pre)
        rows.append((n, fen, counts[k], ended, value if ended else None, chk))
    if verbose:
        print(f"--- {name}")
        for n, fen, occ, ended, value, chk in rows:
            print(f"  ply {n}: occ={occ} end={ended} val={value} check={chk}  {fen}")
    first_end = next(((n, v) for n, f, o, e, v, c in rows if e), None)
    print(f"  earliest optional end: {first_end}")
    return rows


def legality(sf, start, moves):
    for i in range(len(moves)):
        legal = sf.legal_moves(V, start, moves[:i])
        if moves[i] not in legal:
            return f"ILLEGAL at ply {i+1}: {moves[i]} not in {sorted(legal)}"
    return "all moves legal at their turn"


def main():
    for build in sys.argv[1:]:
        sys.path.insert(0, build)
        for m in [m for m in list(sys.modules) if m == "pyffish"]:
            del sys.modules[m]
        import pyffish as sf
        sf.load_variant_config(INI)
        print(f"\n================ build {build}  ({sf.info()})")

        fx = json.loads((FX / "mx-chs-031.json").read_text())
        f30 = json.loads((FX / "mx-chs-030.json").read_text())

        print(legality(sf, fx["start_fen"], fx["moves"]))
        r31 = walk(sf, "mx-chs-031 REMEDY", fx["start_fen"], fx["moves"])
        r30 = walk(sf, "mx-chs-030 PAIR", f30["start_fen"], f30["moves"])

        # The rejected original: same wheel entered from b3, which is ON the wheel.
        r_orig = walk(sf, "mx-chs-031 ORIGINAL (b3 start, rejected)",
                      "4k2/7/c6/7/1R5/7/2K4 w - - 0 1",
                      ["b3a3", "a5b5", "a3b3", "b5a5", "b3a3", "a5b5", "a3b3", "b5a5", "b3a3"],
                      verbose=True)

        # assertions of the fixture, checked directly
        final = sf.get_fen(V, fx["start_fen"], fx["moves"])
        a = fx["assertions"]
        print(f"  result_fen match: {final == a['result_fen']}  ({final})")
        print(f"  in_check match:   {sf.gives_check(V, fx['start_fen'], fx['moves']) == a['in_check']}")
        print(f"  result_fen == mx-chs-030 result_fen: "
              f"{a['result_fen'] == f30['assertions']['result_fen']}")

        # pairing: plies 1..9 identical to 030, ply 0 differs
        same = [ident(sf.get_fen(V, fx["start_fen"], fx["moves"][:n]))
                == ident(sf.get_fen(V, f30["start_fen"], f30["moves"][:n]))
                for n in range(1, 10)]
        print(f"  plies 1-9 position-identical to mx-chs-030: {all(same)} {same}")
        print(f"  ply 0 differs: "
              f"{ident(sf.get_fen(V, fx['start_fen'], [])) != ident(sf.get_fen(V, f30['start_fen'], []))}")

        # VACUITY: no strictly shorter prefix may already be terminal
        early = [(n, e) for n, f, o, e, v, c in r31[:-1] if e]
        print(f"  VACUITY: terminal prefixes strictly shorter than 9: {early or 'none'}")
        print(f"  ply 9 terminal: {(r31[-1][3], r31[-1][4])}")

        # boundary declared by the fixture
        b = fx["boundary"]
        row = r31[b["prefix_len"]]
        print(f"  boundary prefix_len={b['prefix_len']}: occ={row[2]} end={row[3]} val={row[4]}")

        sys.path.remove(build)
        del sys.modules["pyffish"]


if __name__ == "__main__":
    main()
