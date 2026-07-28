#!/usr/bin/env python3
"""Evaluate the P3 differential corpus against one build.

Usage: python3 p3-eval.py <dir-with-pyffish.so> <corpus.json>
Prints one line per entry: "<idx>\t<variant>\t<flag>\t<value>\t<fen>\t<moves>"
"""
import json
import sys

sys.path.insert(0, sys.argv[1])
import pyffish as sf  # noqa: E402

sf.load_variant_config("""
[mxq:minixiangqi]
chasingRule = axf
nMoveRule = 0
promotedSoldiersChaseable = false
""")

corpus = json.load(open(sys.argv[2]))
for i, (variant, fen, moves) in enumerate(corpus):
    try:
        flag, val = sf.is_optional_game_end(variant, fen, moves)
    except Exception as exc:
        print(f"{i}\t{variant}\tERR\t{exc}\t{fen}\t{' '.join(moves)}")
        continue
    v = val if flag else 0
    print(f"{i}\t{variant}\t{flag}\t{v}\t{fen}\t{' '.join(moves)}")
