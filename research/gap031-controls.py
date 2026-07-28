#!/usr/bin/env python3
"""Controls proving the remedy's chase component is real and its target unprotected.

Same nine-ply history as the proposed mx-chs-031 remedy, with only the chased
piece changed:
  A) cannon -> soldier            : soldiers are excluded chase targets (contract)
                                    => neutral claimable repetition
  B) cannon defended by a chariot : protected target is no chase (contract)
                                    => neutral claimable repetition
  C) unchanged remedy             : unprotected cannon => Red loses

Usage: python3 gap031-controls.py <dir-with-pyffish>
"""
import sys

sys.path.insert(0, sys.argv[1])
import pyffish as sf

sf.load_variant_config("""
[mxq_target:minixiangqi]
chasingRule = axf
nMoveRule = 0
promotedSoldiersChaseable = false
""")
V = "mxq_target"

WHEEL = ["c3a3", "a5b5", "a3b3", "b5a5", "b3a3", "a5b5", "a3b3", "b5a5", "b3a3"]

CASES = [
    ("C  remedy: unprotected cannon      ", "4k2/7/c6/7/2R4/7/2K4 w - - 0 1"),
    ("A  control: soldier target (exempt)", "4k2/7/p6/7/2R4/7/2K4 w - - 0 1"),
    ("B  control: cannon defended by rook", "4k2/7/c5r/7/2R4/7/2K4 w - - 0 1"),
]

for name, start in CASES:
    illegal = None
    for i in range(len(WHEEL)):
        if WHEEL[i] not in sf.legal_moves(V, start, WHEEL[:i]):
            illegal = (i, WHEEL[i])
            break
    if illegal:
        print(f"{name}  {start}  -> move {illegal[0]} {illegal[1]} ILLEGAL")
        continue
    ended, value = sf.is_optional_game_end(V, start, WHEEL)
    e8, v8 = sf.is_optional_game_end(V, start, WHEEL[:8])
    e5, v5 = sf.is_optional_game_end(V, start, WHEEL[:5])
    print(f"{name}  {start}")
    print(f"     ply5 {(e5, v5)}   ply8 {(e8, v8)}   ply9 {(ended, value)}"
          f"   final {sf.get_fen(V, start, WHEEL)}")
