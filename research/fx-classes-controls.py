#!/usr/bin/env python3
"""Controls for slate 5.2: prove each asserted negative is produced by the
class rule under test and not by the absence of an attack.

Usage: python3 fx-classes-controls.py <dir-containing-pyffish.so>
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

# name, start_fen, 4-ply cycle, expected state
CONTROLS = [
    # 015 minus the g5 defender: the same horse-vs-cannon wheel becomes a chase,
    # proving g5's protection is what draws mx-chs-015.
    ("015-minus-defender  horse chases an UNprotected cannon",
     "3k3/7/3c3/N6/7/7/4K2 w - - 0 1", ["a4c3", "d5c5", "c3a4", "c5d5"], "black-wins"),
    # 014 minus the g5 defender: unprotected chariot, still a chase (sanity).
    ("014-minus-defender  horse chases an UNprotected chariot",
     "3k3/7/3r3/N6/7/7/4K2 w - - 0 1", ["a4c3", "d5c5", "c3a4", "c5d5"], "black-wins"),
    # 016 with the target's type changed: chariot vs cannon on the identical
    # wheel is a chase, proving the same-type exclusion is what draws mx-chs-016.
    ("016-type-flip       chariot chases an unprotected CANNON",
     "3k3/7/3c3/R6/7/7/2K4 w - - 0 1", ["a4a5", "d5d4", "a5a4", "d4d5"], "black-wins"),
    # 018 with the mover's type changed: chariot instead of soldier on the
    # identical wheel is a chase, proving the attacker class is what draws 018.
    ("018-mover-flip      chariot instead of soldier, same wheel",
     "4k2/7/7/c6/1R5/7/2K4 w - - 0 1", ["b3a3", "a4b4", "a3b3", "b4a4"], "black-wins"),
    # 019 with the mover's type changed: chariot instead of king, same c2/d2
    # shuttle against the same c3/d3 cannon. Kings moved off the shuttle files
    # and a blocker added so the position is legal for a long-range mover.
    ("019-mover-flip      chariot instead of king, same shuttle",
     "4k2/7/4P2/7/3c3/2R1K2/7 w - - 0 1", ["c2d2", "d3c3", "d2c2", "c3d3"], "black-wins"),
]

# name, fen, move that must be a legal capture
ATTACK_PROBES = [
    ("018 soldier a3 genuinely attacks the cannon on a4",
     "4k2/7/7/c6/P6/7/2K4 w - - 0 1", "a3a4"),
    ("018 soldier b3 genuinely attacks the cannon on b4",
     "4k2/7/7/1c5/1P5/7/2K4 w - - 0 1", "b3b4"),
    ("019 king d2 genuinely attacks the cannon on d3",
     "4k2/7/7/7/3c3/3K3/7 w - - 0 1", "d2d3"),
    ("019 king c2 genuinely attacks the cannon on c3",
     "4k2/7/7/7/2c4/2K4/7 w - - 0 1", "c2c3"),
    ("019-SLATE white king NEVER attacks the cannon after its own move (ply 1)",
     "4k2/7/7/7/2c4/3K3/7 w - - 0 1", "d2c3"),
]


def state_of(sf, start, moves, fen):
    ended, value = sf.is_optional_game_end(TARGET, start, moves)
    if not ended:
        return "ongoing"
    if value == 0:
        return "claimable-draw"
    stm_red = fen.split()[1] == "w"
    return "red-wins" if (value == MATE) == stm_red else "black-wins"


def main():
    sys.path.insert(0, sys.argv[1])
    import pyffish as sf
    sf.load_variant_config(INI)
    bad = 0

    print("== attack probes (is the attack real?)")
    for name, fen, mv in ATTACK_PROBES:
        legal = sf.legal_moves(TARGET, fen, [])
        ok = mv in legal
        cap = sf.is_capture(TARGET, fen, [], mv) if ok else False
        print(f"  {name}\n     {fen}  {mv}: legal={ok} capture={cap}")

    print("\n== differential controls")
    for name, start, cycle, want in CONTROLS:
        moves = cycle * 2
        for i in range(len(moves)):
            if moves[i] not in sf.legal_moves(TARGET, start, moves[:i]):
                print(f"  {name}: ILLEGAL ply {i} {moves[i]}")
                bad += 1
                break
        else:
            fen = sf.get_fen(TARGET, start, moves)
            st = state_of(sf, start, moves, fen)
            b = state_of(sf, start, moves[:4], sf.get_fen(TARGET, start, moves[:4]))
            mark = "OK " if st == want else "MISMATCH"
            print(f"  [{mark}] {name}\n     {start} -> {st} (want {want}); boundary@4 {b}")
            if st != want:
                bad += 1
    print(f"\n{bad} mismatching control(s)")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
