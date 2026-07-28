#!/usr/bin/env python3
"""Verifier's invariant sweep over mx-cnt-001 / mx-cnt-002 histories."""
import collections
import importlib.util
import json
import pathlib
import sys

here = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("vfyrules", here / "vfy-nmoverule-rules.py")
R = importlib.util.module_from_spec(spec)
spec.loader.exec_module(R)

FIX = pathlib.Path(sys.argv[1])


def mirror_sq(s):
    """Reflection through the horizontal axis: rank r -> 6-r, same file."""
    return (s[0], 6 - s[1])


def mirror_move(mv):
    a, b = R.sq(mv[:2]), R.sq(mv[2:])
    return R.name(mirror_sq(a)) + R.name(mirror_sq(b))


def analyse(fid):
    fx = json.loads((FIX / f"{fid}.json").read_text())
    pos = R.Pos.from_fen(fx["start_fen"])
    seen = collections.Counter([pos.key()])
    captures = 0
    checks = []
    terminal_prefixes = []
    threefold_first = None
    for i, mv in enumerate(fx["moves"]):
        lm = R.legal_moves(pos)
        assert mv in lm, f"{fid}: ply {i} {mv} illegal in {pos.fen()}"
        pos, cap = R.apply_move(pos, mv, check_legal=False)
        if cap:
            captures += 1
        if R.in_check(pos):
            checks.append((i, mv))
        seen[pos.key()] += 1
        if seen[pos.key()] >= 3 and threefold_first is None:
            threefold_first = i + 1
        if not R.legal_moves(pos):
            terminal_prefixes.append(i + 1)
    print(f"--- {fid} ---")
    print(f"  plies                                {len(fx['moves'])}")
    print(f"  captures                             {captures}")
    print(f"  plies where the mover gave check     {len(checks)} {checks[:5]}")
    print(f"  max occurrences of any position      {max(seen.values())}")
    print(f"  first ply with a 3rd occurrence      {threefold_first}")
    print(f"  prefixes with no legal move          {terminal_prefixes}")
    print(f"  final fen (mine)                     {pos.fen()}")
    print(f"  matches fixture result_fen           {pos.fen() == fx['assertions']['result_fen']}")
    print(f"  in_check (mine)                      {R.in_check(pos)}")
    print(f"  legal moves at final position        {len(R.legal_moves(pos))}")
    # mirror-symmetry claim: Black's reply is Red's move reflected
    mvs = fx["moves"]
    if len(mvs) % 2 == 0:
        bad = [i for i in range(0, len(mvs), 2) if mirror_move(mvs[i]) != mvs[i + 1]]
        print(f"  Black replies that are NOT the mirror of Red's move  {bad}")
    # field-5 monotonic and never reset
    pos2 = R.Pos.from_fen(fx["start_fen"])
    vals = [pos2.half]
    for mv in mvs:
        pos2, _ = R.apply_move(pos2, mv, check_legal=False)
        vals.append(pos2.half)
    print(f"  FEN field 5 strictly increasing      {all(b == a + 1 for a, b in zip(vals, vals[1:]))}")
    print(f"  field 5 range                        {vals[0]} .. {vals[-1]}")


for fid in sys.argv[2:]:
    analyse(fid)
