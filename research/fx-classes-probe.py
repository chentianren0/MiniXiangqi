#!/usr/bin/env python3
"""Probe the slate 5.2 (target/attacker/value class) candidate fixtures.

Usage: python3 fx-classes-probe.py <dir-containing-pyffish.so>
"""
import sys

MATE = 32000
TARGET = "mxq_target"
INI = f"""
[{TARGET}:minixiangqi]
chasingRule = axf
nMoveRule = 0
promotedSoldiersChaseable = false
"""

# id, start_fen, cycle(4 plies), expected state, expected result_fen
CASES = [
    ("mx-chs-014", "3k3/7/3r2r/N6/7/7/4K2 w - - 0 1",
     ["a4c3", "d5c5", "c3a4", "c5d5"], "black-wins",
     "3k3/7/3r2r/N6/7/7/4K2 w - - 8 5"),
    ("mx-chs-015", "3k3/7/3c2r/N6/7/7/4K2 w - - 0 1",
     ["a4c3", "d5c5", "c3a4", "c5d5"], "claimable-draw",
     "3k3/7/3c2r/N6/7/7/4K2 w - - 8 5"),
    ("mx-chs-016", "3k3/7/3r3/R6/7/7/2K4 w - - 0 1",
     ["a4a5", "d5d4", "a5a4", "d4d5"], "claimable-draw",
     "3k3/7/3r3/R6/7/7/2K4 w - - 8 5"),
    ("mx-chs-017", "3k3/7/3r3/R6/7/7/2KR3 w - - 0 1",
     ["a4a5", "d5d4", "a5a4", "d4d5"], "black-wins",
     "3k3/7/3r3/R6/7/7/2KR3 w - - 8 5"),
    ("mx-chs-018", "4k2/7/7/c6/1P5/7/2K4 w - - 0 1",
     ["b3a3", "a4b4", "a3b3", "b4a4"], "claimable-draw",
     "4k2/7/7/c6/1P5/7/2K4 w - - 8 5"),
    ("mx-chs-019-slate", "4k2/7/7/7/2c4/2K4/7 w - - 0 1",
     ["c2d2", "c3d3", "d2c2", "d3c3"], "claimable-draw",
     "4k2/7/7/7/2c4/2K4/7 w - - 8 5"),
    ("mx-chs-019-fixed", "4k2/7/7/7/3c3/2K4/7 w - - 0 1",
     ["c2d2", "d3c3", "d2c2", "c3d3"], "claimable-draw",
     "4k2/7/7/7/3c3/2K4/7 w - - 8 5"),
    # control for 019-fixed: same wheel with a chariot mover instead of a king,
    # to show the geometry would be a chase if the attacker class allowed it.
    ("mx-chs-019-control", "4k2/7/7/7/3c3/2R4/2K4 w - - 0 1",
     ["c2d2", "d3c3", "d2c2", "c3d3"], "black-wins",
     "4k2/7/7/7/3c3/2R4/2K4 w - - 8 5"),
    # control for 018: same wheel with a chariot mover instead of a soldier.
    ("mx-chs-018-control", "4k2/7/7/c6/1R5/7/2K4 w - - 0 1",
     ["b3a3", "a4b4", "a3b3", "b4a4"], "black-wins",
     "4k2/7/7/c6/1R5/7/2K4 w - - 8 5"),
]


def state_of(sf, start, moves, fen):
    ended, value = sf.is_optional_game_end(TARGET, start, moves)
    if not ended:
        return "ongoing", None
    if value == 0:
        return "claimable-draw", 0
    stm_red = fen.split()[1] == "w"
    stm_wins = value == MATE
    return ("red-wins" if stm_wins == stm_red else "black-wins"), value


def main():
    sys.path.insert(0, sys.argv[1])
    import pyffish as sf
    print(f"engine: {sf.info()}")
    sf.load_variant_config(INI)

    bad = 0
    for fid, start, cycle, want_state, want_fen in CASES:
        moves = cycle * 2
        print(f"\n=== {fid}  {start}")
        ok = True
        for i in range(len(moves)):
            legal = sf.legal_moves(TARGET, start, moves[:i])
            if moves[i] not in legal:
                print(f"  ILLEGAL at ply {i}: {moves[i]} (legal: {sorted(legal)})")
                ok = False
                break
        if not ok:
            bad += 1
            continue
        fen = sf.get_fen(TARGET, start, moves)
        chk = sf.gives_check(TARGET, start, moves)
        st, val = state_of(sf, start, moves, fen)
        # boundary at one cycle earlier
        b_fen = sf.get_fen(TARGET, start, moves[:4])
        b_st, _ = state_of(sf, start, moves[:4], b_fen)
        # per-ply optional-end trace
        trace = []
        for i in range(len(moves) + 1):
            f = sf.get_fen(TARGET, start, moves[:i])
            s, v = state_of(sf, start, moves[:i], f)
            trace.append(f"{i}:{s}")
        print(f"  result_fen: {fen}  {'OK' if fen == want_fen else 'MISMATCH want ' + want_fen}")
        print(f"  in_check:   {chk}")
        print(f"  state@8:    {st} (value {val})  {'OK' if st == want_state else 'MISMATCH want ' + want_state}")
        print(f"  boundary@4: {b_st}  {'OK' if b_st == 'ongoing' else 'MISMATCH: already ended'}")
        print(f"  trace:      {' '.join(trace)}")
        if fen != want_fen or st != want_state or b_st != "ongoing":
            bad += 1
    print(f"\n{bad} mismatching case(s)")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
