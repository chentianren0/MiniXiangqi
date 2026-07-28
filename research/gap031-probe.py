#!/usr/bin/env python3
"""Probe for the mx-chs-031 gap: original vs. proposed remedy.

For each candidate history, report at every prefix:
  - the position identity (placement + side to move) and its occurrence count
  - what the engine's optional-game-end says

Usage: python3 gap031-probe.py <dir-with-pyffish>
"""
import sys

sys.path.insert(0, sys.argv[1])
import pyffish as sf

INI = """
[mxq_target:minixiangqi]
chasingRule = axf
nMoveRule = 0
promotedSoldiersChaseable = false
"""
sf.load_variant_config(INI)
V = "mxq_target"

CASES = {
    "mx-chs-030 (approved)": (
        "4k2/7/c6/7/7/7/R1K4 w - - 0 1",
        ["a1a3", "a5b5", "a3b3", "b5a5", "b3a3", "a5b5", "a3b3", "b5a5", "b3a3"],
    ),
    "mx-chs-031 ORIGINAL (rejected)": (
        "4k2/7/c6/7/1R5/7/2K4 w - - 0 1",
        ["b3a3", "a5b5", "a3b3", "b5a5", "b3a3", "a5b5", "a3b3", "b5a5", "b3a3"],
    ),
    "mx-chs-031 REMEDY (c3 start)": (
        "4k2/7/c6/7/2R4/7/2K4 w - - 0 1",
        ["c3a3", "a5b5", "a3b3", "b5a5", "b3a3", "a5b5", "a3b3", "b5a5", "b3a3"],
    ),
}


def ident(fen):
    f = fen.split()
    return f[0] + " " + f[1]


for name, (start, moves) in CASES.items():
    print("=" * 78)
    print(name)
    print("  start:", start)
    print("  moves:", " ".join(moves))
    seen = {}
    first_terminal = None
    for n in range(len(moves) + 1):
        prefix = moves[:n]
        if n > 0:
            legal = sf.legal_moves(V, start, moves[: n - 1])
            legal_note = "legal" if moves[n - 1] in legal else "!!! ILLEGAL !!!"
        else:
            legal_note = "-"
        fen = sf.get_fen(V, start, prefix)
        key = ident(fen)
        seen[key] = seen.get(key, 0) + 1
        ended, value = sf.is_optional_game_end(V, start, prefix)
        chk = sf.gives_check(V, start, prefix)
        if ended and first_terminal is None:
            first_terminal = (n, value)
        flag = "  <== 3rd occurrence" if seen[key] == 3 else ""
        print(
            f"  ply {n}: {fen:<34} occ={seen[key]}  end={str(ended):<5} val={value:<6}"
            f" check={str(chk):<5} {legal_note}{flag}"
        )
    print(f"  earliest engine optional end: {first_terminal}")
    print(f"  final fen: {sf.get_fen(V, start, moves)}")
