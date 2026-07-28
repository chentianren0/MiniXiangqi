#!/usr/bin/env python3
"""Audit every fixture on the section-5 slate against the CURRENT unpatched engine.

Uses discussion-drafts/r-scratch (source byte-identical to fork HEAD 77d602e0).
Reports, per fixture: move legality, final FEN, in_check, the engine's
optional-end verdict at the final ply and at the boundary prefix, and whether
that verdict matches the contract's expected outcome from the reconciliation.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "r-scratch"))
import pyffish as sf  # noqa: E402

MX = "mxq_target"
MATE = 32000
INI = f"""
[{MX}:minixiangqi]
chasingRule = axf
nMoveRule = 0
promotedSoldiersChaseable = false
"""


def M8(a, b, c, d, lead=()):
    return list(lead) + [a, b, c, d] * 2


# id, start_fen, moves, expected state, expected reason, at_occurrence, boundary prefix_len
SLATE = [
    # 5.1 protection
    ("mx-chs-005", "4k2/7/c3r2/7/1R5/7/2K1R2 w - - 0 1", M8("b3a3", "a5b5", "a3b3", "b5a5"), "black-wins", "perpetual-chase", 3, 4),
    ("mx-chs-006", "3k3/4R2/2c4/7/7/7/2K4 w - - 0 1", M8("e6e5", "c5c6", "e5e6", "c6c5"), "black-wins", "perpetual-chase", 3, 4),
    ("mx-chs-007", "3k3/4R2/2c3r/7/7/7/2K4 w - - 0 1", M8("e6e5", "c5c6", "e5e6", "c6c5"), "claimable-draw", "threefold-repetition", 3, 4),
    ("mx-chs-008", "3k3/1p2R2/2c4/7/7/7/2K4 w - - 0 1", M8("e6e5", "c5c6", "e5e6", "c6c5"), "claimable-draw", "threefold-repetition", 3, 4),
    ("mx-chs-009", "2k4/4R2/2c4/7/7/7/2K4 w - - 0 1", M8("e6e5", "c5c6", "e5e6", "c6c5"), "black-wins", "perpetual-chase", 3, 4),
    ("mx-chs-010", "2k4/4R2/2c4/7/7/7/3K3 w - - 0 1", M8("e6e5", "c5c6", "e5e6", "c6c5"), "claimable-draw", "threefold-repetition", 3, 4),
    ("mx-chs-011", "2k4/4R2/2c4/1N5/7/7/3K3 w - - 0 1", M8("e6e5", "c5c6", "e5e6", "c6c5"), "claimable-draw", "threefold-repetition", 3, 4),
    ("mx-chs-012", "7/7/1ck4/7/7/7/R3K2 w - - 0 1", M8("a1b1", "b5a5", "b1a1", "a5b5"), "black-wins", "perpetual-chase", 3, 4),
    ("mx-chs-013", "4k2/7/c3c2/7/1R5/7/2K4 w - - 0 1", M8("b3a3", "a5b5", "a3b3", "b5a5"), "black-wins", "perpetual-chase", 3, 4),
    # 5.2 classes
    ("mx-chs-014", "3k3/7/3r2r/N6/7/7/4K2 w - - 0 1", M8("a4c3", "d5c5", "c3a4", "c5d5"), "black-wins", "perpetual-chase", 3, 4),
    ("mx-chs-015", "3k3/7/3c2r/N6/7/7/4K2 w - - 0 1", M8("a4c3", "d5c5", "c3a4", "c5d5"), "claimable-draw", "threefold-repetition", 3, 4),
    ("mx-chs-016", "3k3/7/3r3/R6/7/7/2K4 w - - 0 1", M8("a4a5", "d5d4", "a5a4", "d4d5"), "claimable-draw", "threefold-repetition", 3, 4),
    ("mx-chs-017", "3k3/7/3r3/R6/7/7/2KR3 w - - 0 1", M8("a4a5", "d5d4", "a5a4", "d4d5"), "black-wins", "perpetual-chase", 3, 4),
    ("mx-chs-018", "4k2/7/7/c6/1P5/7/2K4 w - - 0 1", M8("b3a3", "a4b4", "a3b3", "b4a4"), "claimable-draw", "threefold-repetition", 3, 4),
    ("mx-chs-019", "4k2/7/7/7/2c4/2K4/7 w - - 0 1", M8("c2d2", "c3d3", "d2c2", "d3c3"), "claimable-draw", "threefold-repetition", 3, 4),
    # 5.3 persistence / boundary
    ("mx-chs-020", "3k3/7/c6/7/1R5/7/2K4 w - - 0 1", M8("b3a3", "a5a6", "a3b3", "a6a5"), "claimable-draw", "threefold-repetition", 3, 4),
    ("mx-chs-021", "4k2/7/c6/7/1R5/7/2K4 w - - 0 1", ["c1c2", "e7e6", "c2c1", "e6e7", "b3a3", "a5b5", "a3b3", "b5a5"], "claimable-draw", "threefold-repetition", 3, 4),
    ("mx-chs-022", "4k2/7/c6/7/1R5/7/2K4 w - - 0 1", ["c1c2", "e7e6", "c2c1", "e6e7"] + ["b3a3", "a5b5", "a3b3", "b5a5"] * 2, "black-wins", "perpetual-chase", 4, 8),
    ("mx-chs-023", "3k3/7/c6/7/2R4/7/4K2 w - - 0 1", ["c3a3", "a5b5", "a3b3", "b5c5", "b3c3", "c5a5"] * 2, "black-wins", "perpetual-chase", 3, 6),
    ("mx-chs-024", "3k3/7/c5c/7/R6/7/2K4 w - - 0 1", M8("a3g3", "d7d6", "g3a3", "d6d7"), "claimable-draw", "threefold-repetition", 3, 4),
    ("mx-chs-025", "R6/7/c3k2/7/1R5/7/3K3 w - - 0 1", ["b3a3", "a5b5", "a7b7", "b5a5", "b7a7", "a5b5", "a3b3", "b5a5"] * 2, "black-wins", "perpetual-chase", 3, 8),
    # 5.4 discovery / renewal
    ("mx-chs-026", "4k2/7/R1Nc3/7/7/7/2KR3 w - - 0 1", M8("c5d3", "e7e6", "d3c5", "e6e7"), "black-wins", "perpetual-chase", 3, 4),
    ("mx-chs-027", "3k3/7/1r3N1/7/7/2K4/7 w - - 0 1", M8("f5d6", "b5d5", "d6f5", "d5b5"), "red-wins", "perpetual-chase", 3, 4),
    # 5.5 patch-gating
    ("mx-chs-028", "3rk2/7/7/3R3/1c5/7/3K3 w - - 0 1", M8("d4d3", "b3b4", "d3d4", "b4b3"), "claimable-draw", "threefold-repetition", 3, 4),
    ("mx-chs-029", "2k4/7/R6/2r4/7/2P4/2K4 w - - 0 1", M8("a5a4", "c4c5", "a4a5", "c5c4"), "claimable-draw", "threefold-repetition", 3, 4),
    ("mx-chs-030", "4k2/7/c6/7/7/7/R1K4 w - - 0 1", ["a1a3"] + ["a5b5", "a3b3", "b5a5", "b3a3"] * 2, "black-wins", "perpetual-chase", 3, 5),
    ("mx-chs-031", "4k2/7/c6/7/1R5/7/2K4 w - - 0 1", ["b3a3"] + ["a5b5", "a3b3", "b5a5", "b3a3"] * 2, "black-wins", "perpetual-chase", 3, 5),
    ("mx-chs-032", "4k2/7/c6/7/7/7/R1K4 w - - 0 1", ["a1a3"] + ["a5b5", "a3b3", "b5a5", "b3a3"] * 2 + ["a5b5"], "black-wins", "perpetual-chase", 3, 6),
    # 5.6 mutual-chase halves
    ("mx-chs-033", "2k4/7/1cN1R2/7/4n2/7/1R2K2 w - - 0 1", M8("c5b3", "e3f5", "b3c5", "f5e3"), "black-wins", "perpetual-chase", 3, 4),
    ("mx-chs-034", "2k2r1/7/2N4/7/2r1nC1/7/4K2 w - - 0 1", M8("c5b3", "e3f5", "b3c5", "f5e3"), "red-wins", "perpetual-chase", 3, 4),
    # 5.7 perpetual check
    ("mx-chk-003", "7/7/2k3C/3n3/4N2/7/3K3 w - - 0 1", M8("e3d5", "d4f5", "d5e3", "f5d4"), "black-wins", "perpetual-check", 3, 4),
    ("mx-chk-004", "3c3/7/2k4/3n3/4N2/7/3K3 w - - 0 1", M8("e3d5", "d4f5", "d5e3", "f5d4"), "red-wins", "perpetual-check", 3, 4),
    # 5.8 cross-class
    ("mx-mix-001", "3c3/7/2k3C/3n3/4N2/7/3K3 w - - 0 1", M8("e3d5", "d4f5", "d5e3", "f5d4"), "draw", "mutual-perpetual-check", 3, 4),
    ("mx-mix-002", "2k2r1/7/1cN1R2/7/2r1nC1/7/1R2K2 w - - 0 1", M8("c5b3", "e3f5", "b3c5", "f5e3"), "draw", "mutual-perpetual-chase", 3, 4),
    ("mx-mix-003", "3k3/7/c6/R6/7/7/4K2 w - - 0 1", M8("a4d4", "d7c7", "d4a4", "c7d7"), "claimable-draw", "threefold-repetition", 3, 4),
    ("mx-mix-004", "3k3/7/1r3N1/7/7/2K4/3C3 w - - 0 1", M8("f5d6", "b5d5", "d6f5", "d5b5"), "black-wins", "perpetual-check", 3, 4),
]


def want_value(state, fen):
    if state in ("claimable-draw", "draw"):
        return 0
    stm_red = fen.split()[1] == "w"
    return MATE if ((state == "red-wins") == stm_red) else -MATE


def main():
    sf.load_variant_config(INI)
    print(f"engine: {sf.info()}   build: r-scratch (== fork HEAD 77d602e0)\n")
    agree, diverge, broken = [], [], []
    for fid, fen, moves, state, reason, occ, bpref in SLATE:
        # legality of every move
        bad = None
        for i in range(len(moves)):
            if moves[i] not in sf.legal_moves(MX, fen, moves[:i]):
                bad = (i, moves[i])
                break
        if bad:
            print(f"[BROKEN] {fid}  move {bad[0]} {bad[1]!r} illegal")
            broken.append(fid)
            continue
        final = sf.get_fen(MX, fen, moves)
        chk = sf.gives_check(MX, fen, moves)
        ended, val = sf.is_optional_game_end(MX, fen, moves)
        val = val if ended else None
        e_pre, _ = sf.is_optional_game_end(MX, fen, moves[:bpref])
        w = want_value(state, final)
        ok_final = ended and val == w
        ok_bound = not e_pre
        # mx-chs-022's boundary is a claimable draw by design, not "not yet ended"
        note = ""
        if fid == "mx-chs-022":
            ok_bound = e_pre and sf.is_optional_game_end(MX, fen, moves[:bpref])[1] == 0
            note = " (boundary is itself a claimable draw, by design)"
        tag = "AGREES " if (ok_final and ok_bound) else "DIVERGE"
        (agree if (ok_final and ok_bound) else diverge).append(fid)
        print(f"[{tag}] {fid}  plies={len(moves):2d}  in_check={str(chk):5s} "
              f"engine=({ended},{val})  want={w} [{state}/{reason}@{occ}]  "
              f"boundary({bpref})={'ok' if ok_bound else 'ALREADY-ENDED'}{note}")
        print(f"          final_fen: {final}")
    print(f"\nagree: {len(agree)}   diverge: {len(diverge)}   broken: {len(broken)}")
    print("diverging:", " ".join(diverge))
    if broken:
        print("broken:", " ".join(broken))


if __name__ == "__main__":
    main()
