#!/usr/bin/env python3
"""Prefix sweep (vacuity) and inherited-threshold sweep."""
import json
import pathlib
import sys

sys.path.insert(0, sys.argv[1])
import pyffish as sf

GOOD, BAD = "sw_good", "sw_bad"
sf.load_variant_config(f"""
[{GOOD}:minixiangqi]
chasingRule = axf
nMoveRule = 0
promotedSoldiersChaseable = false

[{BAD}:minixiangqi]
chasingRule = axf
promotedSoldiersChaseable = false
""")

d = pathlib.Path(sys.argv[2])
fx = json.loads((d / "mx-cnt-001.json").read_text())
start, moves = fx["start_fen"], fx["moves"]

print("prefix sweep over the 104-ply history (engine, both variants):")
first_good = first_bad = None
for n in range(len(moves) + 1):
    eg, vg = sf.is_optional_game_end(GOOD, start, moves[:n])
    eb, vb = sf.is_optional_game_end(BAD, start, moves[:n])
    if eg and first_good is None:
        first_good = (n, vg, sf.get_fen(GOOD, start, moves[:n]))
    if eb and first_bad is None:
        first_bad = (n, vb, sf.get_fen(BAD, start, moves[:n]))
print(f"  first prefix that is an optional end, correct variant  : {first_good}")
print(f"  first prefix that is an optional end, misconfig variant: {first_bad}")
print(f"  margin between the false draw and the asserted ply     : "
      f"{len(moves) - first_bad[0] if first_bad else 'n/a'} plies")

print("\ninherited-threshold sweep on a bare position, field 5 = 96..106:")
for cfg, label in ((GOOD, "nMoveRule = 0"), (BAD, "inherited nMoveRule")):
    hits = []
    for n in range(96, 107):
        fen = f"2k4/7/7/7/7/7/4K2 w - - {n} 1"
        ended, _ = sf.is_optional_game_end(cfg, fen, [])
        if ended:
            hits.append(n)
    print(f"  {label:<22} ends at field-5 values {hits}")

print("\nwould a variant with some other nonzero nMoveRule still pass mx-cnt-001?")
for n in (30, 50, 51, 52, 53, 60):
    name = f"sw_n{n}"
    sf.load_variant_config(f"[{name}:minixiangqi]\nchasingRule = axf\nnMoveRule = {n}\npromotedSoldiersChaseable = false\n")
    ended, _ = sf.is_optional_game_end(name, start, moves)
    print(f"  nMoveRule = {n:<3} -> mx-cnt-001 {'DETECTS' if ended else 'is blind'}")
