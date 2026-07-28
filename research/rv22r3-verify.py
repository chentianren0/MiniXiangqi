#!/usr/bin/env python3
"""PR #22 round three. Re-run the A1-A4 renewal differential and the B parity
pair against the third commit's wording.

For each wheel we print, per move of the chasing side:
  - whether the mover attacks the chase target from the square it lands on
    (probed by flipping the side to move and asking for the capture);
  - which clause of the accepted wording covers the move;
  - the wording's prediction, and the engine's verdict for the wheel.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "r-scratch"))
import pyffish  # noqa: E402

MX = "minixiangqitarget"
pyffish.load_variant_config(
    "[minixiangqitarget:minixiangqi]\nchasingRule = axf\nnMoveRule = 0\n"
    "promotedSoldiersChaseable = false\n"
)


def flip(fen):
    p = fen.split()
    p[1] = "b" if p[1] == "w" else "w"
    return " ".join(p)


def attacks(fen, moves, frm, to):
    """After `moves`, can the piece on `frm` capture on `to`? (side to move flipped)"""
    f = pyffish.get_fen(MX, fen, list(moves))
    try:
        lm = pyffish.legal_moves(MX, flip(f), [])
    except Exception as e:                       # pragma: no cover
        return "probe-error:%s" % e
    return (frm + to) in lm


def wheel(name, fen, moves, chaser, target_of_ply, clause_of_ply):
    print("\n=== %s ===" % name)
    print("  fen  : %s" % fen)
    print("  moves: %s (%d plies)" % (" ".join(moves), len(moves)))
    for i, m in enumerate(moves):
        if m not in pyffish.legal_moves(MX, fen, list(moves[:i])):
            print("  !! ILLEGAL at %d (%s)" % (i, m))
            return
    print("  %-4s %-6s %-5s %-8s  %s" % ("ply", "move", "att?", "clause", "wording predicts"))
    for i, m in enumerate(moves):
        if (i % 2) != (0 if chaser == "w" else 1):
            continue
        tgt = target_of_ply(i)
        if tgt is None:
            continue
        a = attacks(fen, moves[:i + 1], m[2:], tgt)
        clause, pred = clause_of_ply(i)
        print("  %-4d %-6s %-5s %-8s  %s" % (i + 1, m, a, clause, pred))
    f, v = pyffish.is_optional_game_end(MX, fen, list(moves))
    if not f:
        eng = "ongoing"
    elif v == 0:
        eng = "DRAW"
    else:
        stm = pyffish.get_fen(MX, fen, list(moves)).split()[1]
        eng = "LOSER=" + (("Red" if stm == "w" else "Black") if v < 0
                          else ("Black" if stm == "w" else "Red"))
    print("  ENGINE at ply %d: %s" % (len(moves), eng))


print("pyffish", pyffish.version(), pyffish.info())
print("\nAccepted wording under test:")
print('  headline: "attacks the target from the square it now occupies and did not')
print('             attack it from that square before the move"')
print('  clause A: "steps AWAY from its target and still attacks it from the new')
print('             square therefore renews"')
print('  clause B: "merely advances TOWARD the target along a line on which its')
print('             attack already stood does not"')

# ---- A1  mx-chs-020 : one chasing move, one idle move --------------------
wheel("A1  mx-chs-020 — b3a3 chases the a5 cannon, a3b3 does not attack it",
      "3k3/7/c6/7/1R5/7/2K4 w - - 0 1",
      ["b3a3", "a5a6", "a3b3", "a6a5"] * 2, "w",
      lambda i: "a5" if i % 4 == 0 else "a6",
      lambda i: ("headline", "renews" if i % 4 == 0 else "no attack -> no renewal"))

# ---- A2  ALONG the a-file, cannon fixed on a5 ----------------------------
wheel("A2  ALONG — rook a1<->a3, cannon fixed on a5",
      "4k2/7/c6/7/7/7/R2K3 w - - 0 1",
      ["a1a3", "e7e6", "a3a1", "e6e7"] * 2, "w",
      lambda i: "a5",
      lambda i: (("B", "advances TOWARD along the standing line -> NO renewal")
                 if i % 4 == 0 else ("A", "steps AWAY, still attacks -> renews")))

# ---- A3  ACROSS onto the line -------------------------------------------
wheel("A3  ACROSS — rook b3<->a3, cannon a5<->b5",
      "4k2/7/c6/7/1R5/7/2K4 w - - 0 1",
      ["b3a3", "a5b5", "a3b3", "b5a5"] * 2, "w",
      lambda i: "a5" if i % 4 == 0 else "b5",
      lambda i: ("headline", "no attack stood before -> renews (neither A nor B applies)"))

# ---- A4  mx-chs-027 : one across, one step-away-along --------------------
wheel("A4  mx-chs-027 — b5d5 arrives on the d-file; d5b5 steps AWAY along rank 5",
      "3k3/7/1r3N1/7/7/2K4/7 w - - 0 1",
      ["f5d6", "b5d5", "d6f5", "d5b5"] * 2, "b",
      lambda i: "d6" if i % 4 == 1 else "f5",
      lambda i: (("headline", "no attack stood before -> renews") if i % 4 == 1
                 else ("A", "steps AWAY, still attacks -> renews")))

# ---- B  parity direction -------------------------------------------------
print("\n\n=== B  parity direction, mutual-chase wheel mx-mix-002 ===")
W1 = ["c5b3", "e3f5", "b3c5", "f5e3"]
W2 = ["e3f5", "b3c5", "f5e3", "c5b3"]
cases = [
    ("bare, history begins at the first occurrence",
     "2k2r1/7/1cN1R2/7/2r1nC1/7/1R2K2 w - - 0 1", W1 * 2, "-"),
    ("quiet WHITE entry d1e1 (9 plies)",
     "2k2r1/7/1c2R2/7/1Nr1nC1/7/1R1K3 w - - 0 1", ["d1e1"] + W2 * 2, "White"),
    ("quiet WHITE entry d1e1 (10 plies)",
     "2k2r1/7/1c2R2/7/1Nr1nC1/7/1R1K3 w - - 0 1", ["d1e1"] + W2 * 2 + ["e3f5"], "White"),
    ("quiet BLACK entry d7c7 (9 plies)",
     "3k1r1/7/1cN1R2/7/2r1nC1/7/1R2K2 b - - 0 1", ["d7c7"] + W1 * 2, "Black"),
    ("quiet BLACK entry d7c7 (10 plies)",
     "3k1r1/7/1cN1R2/7/2r1nC1/7/1R2K2 b - - 0 1", ["d7c7"] + W1 * 2 + ["c5b3"], "Black"),
]
print("  %-44s %-8s %-8s %s" % ("case", "entered", "plies", "engine"))
for name, fen, mv, entered in cases:
    ok = all(m in pyffish.legal_moves(MX, fen, list(mv[:i])) for i, m in enumerate(mv))
    f, v = pyffish.is_optional_game_end(MX, fen, list(mv))
    if not f:
        eng = "ongoing"
    elif v == 0:
        eng = "DRAW"
    else:
        stm = pyffish.get_fen(MX, fen, list(mv)).split()[1]
        eng = "LOSER=" + (("Red" if stm == "w" else "Black") if v < 0
                          else ("Black" if stm == "w" else "Red"))
    print("  %-44s %-8s %-8d %s%s" % (name, entered, len(mv), eng, "" if ok else "  (ILLEGAL)"))
