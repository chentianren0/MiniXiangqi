#!/usr/bin/env python3
"""PR #22 round-two review. Two questions:

A. Does the restored renewal wording predict the engine's verdicts?
   The new sentence is a dichotomy: "A piece that merely advances along a line on
   which its attack already stood does not renew the chase; a piece that arrives on
   the attacking line from off it does."  Test it against three wheels.

B. Is the new accepted parity line's direction right?  It says a mutual perpetual
   chase "resolves the required draw as a unilateral loss against whichever side
   made the entering move."  Enter the same wheel by a quiet White move and by a
   quiet Black move and read off who loses.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "r-scratch"))
import pyffish  # noqa: E402

MX = "minixiangqitarget"
BUILTIN = "minixiangqi"
pyffish.load_variant_config(
    "[minixiangqitarget:minixiangqi]\nchasingRule = axf\nnMoveRule = 0\n"
    "promotedSoldiersChaseable = false\n"
)


def verdict(fen, moves, n):
    f, v = pyffish.is_optional_game_end(MX, fen, list(moves[:n]))
    if not f:
        return "(False,-)  ongoing"
    if v == 0:
        return "(True,0)   DRAW"
    stm = pyffish.get_fen(MX, fen, list(moves[:n])).split()[1]
    who = ("Red" if stm == "w" else "Black") if v < 0 else ("Black" if stm == "w" else "Red")
    return "(True,%-6d) LOSER=%s" % (v, who)


def run(name, fen, moves, note="", prefixes=()):
    print("\n=== %s ===" % name)
    if note:
        print("  note : " + note)
    print("  fen  : %s" % fen)
    print("  moves: %s (%d plies)" % (" ".join(moves), len(moves)))
    for i, m in enumerate(moves):
        if m not in pyffish.legal_moves(MX, fen, list(moves[:i])):
            print("  !! ILLEGAL at %d (%s); legal: %s"
                  % (i, m, sorted(pyffish.legal_moves(MX, fen, list(moves[:i])))))
            return
    for n in list(prefixes) + [len(moves)]:
        print("  ply %-3d %s" % (n, verdict(fen, moves, n)))


print("pyffish", pyffish.version(), pyffish.info())
print("\n" + "#" * 78)
print("# A. THE RENEWAL DICHOTOMY")
print("#" * 78)

run("A1  every move must renew — one chasing move + one idle move per cycle (mx-chs-020)",
    "3k3/7/c6/7/1R5/7/2K4 w - - 0 1",
    ["b3a3", "a5a6", "a3b3", "a6a5"] * 2,
    note="White's b3a3 chases the cannon; a3b3 does not. Engine draws, so a chase "
         "requires EVERY move of the chasing side to renew.")

run("A2  ALONG the line: rook a1<->a3, cannon fixed on a5",
    "4k2/7/c6/7/7/7/R2K3 w - - 0 1",
    ["a1a3", "e7e6", "a3a1", "e6e7"] * 2,
    note="Every White move keeps the same undefended cannon attacked, moving ALONG "
         "the a-file toward and away from it.")

run("A3  ACROSS onto the line: rook b3<->a3, cannon a5<->b5",
    "4k2/7/c6/7/1R5/7/2K4 w - - 0 1",
    ["b3a3", "a5b5", "a3b3", "b5a5"] * 2,
    note="Every White move arrives on the attacking line from off it.")

run("A4  mx-chs-027 — Black's two moves are ONE across-onto-the-line and ONE "
    "step-away-ALONG-the-line",
    "3k3/7/1r3N1/7/7/2K4/7 w - - 0 1",
    ["f5d6", "b5d5", "d6f5", "d5b5"] * 2,
    note="b5d5 arrives on the d-file (off it before). d5b5 moves ALONG rank 5, on "
         "which the attack on f5 already stood, and steps AWAY from the target. "
         "By A1, a chase verdict here means the engine counts BOTH as renewals.")

print("\n" + "#" * 78)
print("# B. THE PARITY LINE'S DIRECTION")
print("#" * 78)

W1 = ["c5b3", "e3f5", "b3c5", "f5e3"]           # wheel with White to move
W2 = ["e3f5", "b3c5", "f5e3", "c5b3"]           # same wheel re-phased, Black to move
P = "2k2r1/7/1cN1R2/7/2r1nC1/7/1R2K2 w - - 0 1"  # mx-mix-002, White to move
X = "2k2r1/7/1c2R2/7/1Nr1nC1/7/1R2K2 b - - 0 1"  # same wheel, Black to move

run("B0a  mx-mix-002 as published — history begins at the first occurrence", P, W1 * 2)
run("B0b  the same wheel re-phased, bare", X, W2 * 2)

# Entered by a quiet WHITE move: white king d1-e1.
run("B1  entered by a quiet WHITE move (white king d1-e1)",
    "2k2r1/7/1c2R2/7/1Nr1nC1/7/1R1K3 w - - 0 1", ["d1e1"] + W2 * 2,
    note="occurrences at plies 1/5/9; last mover at ply 9 is White",
    prefixes=(5,))
run("B1' the same, one ply later (parity control)",
    "2k2r1/7/1c2R2/7/1Nr1nC1/7/1R1K3 w - - 0 1", ["d1e1"] + W2 * 2 + ["e3f5"])

# Entered by a quiet BLACK move: black king d7-c7.
run("B2  entered by a quiet BLACK move (black king d7-c7)",
    "3k1r1/7/1cN1R2/7/2r1nC1/7/1R2K2 b - - 0 1", ["d7c7"] + W1 * 2,
    note="occurrences at plies 1/5/9; last mover at ply 9 is Black",
    prefixes=(5,))
run("B2' the same, one ply later (parity control)",
    "3k1r1/7/1cN1R2/7/2r1nC1/7/1R2K2 b - - 0 1", ["d7c7"] + W1 * 2 + ["c5b3"])
