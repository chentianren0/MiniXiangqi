#!/usr/bin/env python3
"""Workspace-only evidence for mx-rep-002 / mx-rep-003.

Walks the mx-rep-002 history one ply at a time and reports, for each ply, the
full 6-field FEN, the position record under the contract's identity rule
(placement + side to move, counters dropped), and the placement alone.  Then it
tallies both, so the claim the fixtures rest on -- placement occurs five times,
the record only three -- is visible rather than asserted.

Also reports, at every prefix, whether the engine sees an optional game end, so
the exact ply at which the claim attaches is observed and not inferred.

Usage: python3 identity-trace.py <dir-containing-pyffish.so>
"""
import collections
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

fx = json.loads((pathlib.Path(__file__).resolve().parent.parent
                 / "MiniXiangqi" / "fixtures" / "rules" / "mx-rep-002.json").read_text()) \
    if len(sys.argv) < 3 else json.loads(pathlib.Path(sys.argv[2]).read_text())


def record(fen):
    """Position identity per docs/xiangqi-rules.md line 38: placement + side to move."""
    f = fen.split()
    return f"{f[0]} {f[1]}"


def placement(fen):
    return fen.split()[0]


def main():
    sys.path.insert(0, sys.argv[1])
    import pyffish as sf
    sf.load_variant_config(INI)

    start, moves = fx["start_fen"], fx["moves"]
    rec_seen = collections.Counter()
    plc_seen = collections.Counter()

    print(f"engine: {sf.info()}")
    print(f"fixture: {fx['id']}\n")
    print(f"{'ply':>3}  {'move':<6} {'fen':<40} {'rec#':>4} {'plc#':>4}  optional-end")
    for i in range(len(moves) + 1):
        fen = sf.get_fen(V, start, moves[:i])
        rec_seen[record(fen)] += 1
        plc_seen[placement(fen)] += 1
        ended, value = sf.is_optional_game_end(V, start, moves[:i])
        end = f"yes value={value}" if ended else "no"
        mv = moves[i - 1] if i else "-"
        print(f"{i:>3}  {mv:<6} {fen:<40} {rec_seen[record(fen)]:>4} "
              f"{plc_seen[placement(fen)]:>4}  {end}")

    print("\nrecord tallies (placement + side to move):")
    for k, n in rec_seen.most_common():
        print(f"  {n} x  {k}")
    print("\nplacement tallies (placement alone):")
    for k, n in plc_seen.most_common():
        print(f"  {n} x  {k}")


if __name__ == "__main__":
    main()
