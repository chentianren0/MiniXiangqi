#!/usr/bin/env python3
"""Probe one Mini Xiangqi cycle under one pyffish build.

    python3 kt-probe.py <build-dir> <start-fen> <m1 m2 m3 m4 ...>

Replays the cycle three times, prints the per-ply check flags and the
`is_optional_game_end` verdict at 8, 9 and 10 plies (and the boundary at one
cycle less), plus a deletion-control hint.  Workspace-only research scratch.
"""
import sys

VARIANT = "mxq"
INI = """
[mxq:minixiangqi]
chasingRule = axf
nMoveRule = 0
promotedSoldiersChaseable = false
"""
MATE = 32000


def main():
    build, fen = sys.argv[1], sys.argv[2]
    cyc = sys.argv[3].split()
    sys.path.insert(0, build)
    import pyffish as sf
    sf.load_variant_config(INI)

    print(f"build : {build}")
    print(f"start : {fen}")
    print(f"cycle : {' '.join(cyc)}")
    hist = cyc * 4
    flags = []
    for i in range(len(hist)):
        legal = sf.legal_moves(VARIANT, fen, hist[:i])
        if hist[i] not in legal:
            print(f"  ILLEGAL at ply {i}: {hist[i]} not in {sorted(legal)}")
            hist = hist[:i]
            break
        flags.append("T" if sf.gives_check(VARIANT, fen, hist[:i + 1]) else "f")
    print(f"stm    : {fen.split()[1]}  (ply 0 = first move by that side)")
    print(f"check  : {'.' if not sf.gives_check(VARIANT, fen, []) else 'T'} | " + " ".join(flags))
    for n in range(2, len(hist) + 1):
        ended, value = sf.is_optional_game_end(VARIANT, fen, hist[:n])
        if ended:
            stm = sf.get_fen(VARIANT, fen, hist[:n]).split()[1]
            if value == 0:
                verdict = "draw / claimable"
            elif value > 0:
                verdict = ("RED wins" if stm == "w" else "BLACK wins") + f" ({value})"
            else:
                verdict = ("BLACK wins" if stm == "w" else "RED wins") + f" ({value})"
            print(f"  ply {n:>2}: ended stm={stm} value={value:<7} -> {verdict}")
    print(f"  final fen: {sf.get_fen(VARIANT, fen, hist)}")


if __name__ == "__main__":
    main()
