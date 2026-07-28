#!/usr/bin/env python3
"""Verifier's own controls for mx-chs-031: isolate the chase component.

Same nine-ply wheel, three targets:
  A  unprotected black cannon      -> contract says perpetual chase, Red loses
  B  black soldier (exempt target) -> contract line 66 excludes soldiers -> neutral repetition
  C  cannon defended by a black chariot on g5 -> protected target -> neutral repetition

Also checks the renewal geometry that separates mx-chs-031 from mx-chs-030.
"""
import sys

INI = """
[mxq_target:minixiangqi]
chasingRule = axf
nMoveRule = 0
promotedSoldiersChaseable = false
"""
V = "mxq_target"

WHEEL = ["c3a3", "a5b5", "a3b3", "b5a5", "b3a3", "a5b5", "a3b3", "b5a5", "b3a3"]

CASES = [
    ("A  unprotected cannon (the fixture)", "4k2/7/c6/7/2R4/7/2K4 w - - 0 1", WHEEL),
    ("B  soldier target (exempt)",          "4k2/7/p6/7/2R4/7/2K4 w - - 0 1", WHEEL),
    ("C  cannon defended by chariot g5",    "4k2/7/c5r/7/2R4/7/2K4 w - - 0 1", WHEEL),
]


def main():
    build = sys.argv[1]
    sys.path.insert(0, build)
    import pyffish as sf
    sf.load_variant_config(INI)
    print(f"build {build}: {sf.info()}\n")

    for name, start, moves in CASES:
        bad = None
        for i in range(len(moves)):
            if moves[i] not in sf.legal_moves(V, start, moves[:i]):
                bad = f"ILLEGAL ply {i+1} {moves[i]}"
                break
        if bad:
            print(f"  {name:38s} {bad}")
            continue
        ended, value = sf.is_optional_game_end(V, start, moves)
        fen = sf.get_fen(V, start, moves)
        print(f"  {name:38s} ply9 end={ended} val={value if ended else None}   {fen}")

    print("\nrenewal geometry: does the chariot's attack on the cannon already stand at ply 0?")
    for label, start, cap in [
        ("mx-chs-031 chariot c3, entry c3a3", "4k2/7/c6/7/2R4/7/2K4 w - - 0 1", "c3a5"),
        ("mx-chs-030 chariot a1, entry a1a3", "4k2/7/c6/7/7/7/R1K4 w - - 0 1", "a1a5"),
    ]:
        legal = sf.legal_moves(V, start, [])
        caps = [m for m in legal if m.endswith("a5")]
        print(f"  {label}: can capture cannon on a5 at ply 0? {cap in legal}  (moves onto a5: {caps})")

    print("\nrenewal of each judged White move (does it attack the cannon from its NEW square,")
    print("having not attacked it from that square before the move?)")
    start = "4k2/7/c6/7/2R4/7/2K4 w - - 0 1"
    for n in (0, 2, 4, 6, 8):          # White to move at these plies; the move played is n+1
        before = sf.legal_moves(V, start, WHEEL[:n])
        tgt_before = sorted(m for m in before if m.endswith(("a5", "b5")))
        after_pre = WHEEL[: n + 1]
        after = sf.legal_moves(V, start, after_pre + [])   # Black to move; look from White's side next ply
        # attack existence after the move: can White capture the cannon on its next turn
        # without moving the chariot again?
        nxt = sf.legal_moves(V, start, after_pre + [WHEEL[n + 1]]) if n + 1 < len(WHEEL) else None
        print(f"  ply {n+1}: {WHEEL[n]:6s} White captures available BEFORE = {tgt_before}")


if __name__ == "__main__":
    main()
