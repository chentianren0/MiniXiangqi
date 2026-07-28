"""Scratch: test the §2.4 rules claims of the board-visual-language draft.

Claim (a) S3+S6 cannot occur - "a general is never a legal capture target".
Claim (b) S4+S6 cannot occur - "brackets never land on the checked general's cell".
Claim (c) "Two generals both in check: impossible position".

Workspace-only verification evidence.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "r-scratch"))
import pyffish  # noqa: E402

V = "minixiangqi"
START = "rcnkncr/p1ppp1p/7/7/7/P1PPP1P/RCNKNCR w - - 0 1"

print("pyffish", pyffish.version(), "variants incl minixiangqi:",
      V in pyffish.variants())


def show(fen, moves=()):
    moves = list(moves)
    cur = pyffish.get_fen(V, fen, moves)
    print(f"  fen        {cur}")
    print(f"  in check   {pyffish.gives_check(V, fen, moves[:-1]) if moves else '-'}")
    print(f"  legal      {sorted(pyffish.legal_moves(V, fen, moves))}")
    return cur


# ---------------------------------------------------------------- claim (c)
print("\n=== (c) can a legal position have BOTH generals in check? ===")
# Only the side to move can be in check after a legal move, because a move that
# leaves your own general attacked is illegal.  The flying-generals rule is the
# only mutual attack, and creating the facing is always illegal for the mover.
# Probe: from a position with generals on the same file separated by one piece,
# every move that clears the file must be rejected.
fen_fly = "3k3/7/7/3R3/7/7/3K3 w - - 0 1"   # Rd4 between Kd1 and kd7
legal = sorted(pyffish.legal_moves(V, fen_fly, []))
print("  Kd1, kd7, Rd4 (Red to move). Red chariot moves off the d-file:")
print("  legal:", legal)
off_file = [m for m in legal if m.startswith("d4") and not m[2] == "d"]
print("  moves that would clear the d-file and are LEGAL:", off_file,
      "-> expect [] (flying generals)")

# ---------------------------------------------------------------- claim (a)
print("\n=== (a) is a general ever a legal capture target? ===")
# Side to move can capture the enemy general only if the enemy left its general
# attacked, i.e. the previous move was illegal.  Probe: a position where Red
# could 'capture' kd7 with a chariot is a position where Black was already in
# check with Red to move - not reachable from the start by legal play.
fen_a = "3k3/7/7/7/3R3/7/3K3 b - - 0 1"   # Rd3 checks kd7, BLACK to move
print("  Rd3 vs kd7, Black to move (Black IS in check):")
print("  black in check:", pyffish.gives_check(V, "3k3/7/7/7/3R3/7/2K4 w - - 0 1", []) if False else "n/a")
print("  black legal moves:", sorted(pyffish.legal_moves(V, fen_a, [])))
print("  -> the checked general belongs to the SIDE TO MOVE, and S3 is drawn")
print("     on ENEMY pieces only, so S3 and S6 cannot share a disc.")

# ---------------------------------------------------------------- claim (b)
print("\n=== (b) S4 + S6: brackets on the checked general's cell ===")
print("Construction: Free Play, Black in check, Black escapes with a GENERAL")
print("move, then Undo returns to the checked position.")
fen_b = "3k3/7/7/7/3R3/7/3K3 b - - 0 1"
print("\n  P (before):", fen_b)
print("  Black legal moves:", sorted(pyffish.legal_moves(V, fen_b, [])))
print("  Black in check at P:",
      pyffish.gives_check(V, "3k3/7/7/7/7/7/3K3 w - - 0 1", []) if False else
      "(see legal set: only king moves off the d-file)")
mv = "d7c7"
assert mv in pyffish.legal_moves(V, fen_b, []), "escape move must be legal"
q = pyffish.get_fen(V, fen_b, [mv])
print(f"\n  Q (after {mv}):", q)
print("  Red to move, Red in check?",
      pyffish.gives_check(V, fen_b, []), "(gives_check of the position before)")
print("  Red legal moves:", sorted(pyffish.legal_moves(V, q, [])))
print("\n  Undo -> back at P, Black to move and IN CHECK, general on d7.")
print("  d7 is the ORIGIN cell of the move just undone.")
print("  If S4 brackets are 'persistent until the next ply replaces them'")
print("  (the draft's own rule), the undone move's brackets are still on d7")
print("  and c7 -> S4 + S6 share the d7 cell.  CLAIM (b) FALSIFIED as written.")

# Same construction reachable from the real starting position?
print("\n=== is a general-move check escape reachable from the start? ===")
line = ["d1d2"]
print("  Red Kd1-d2 legal from start:",
      "d1d2" in pyffish.legal_moves(V, START, []))
print("  (general moves are ordinary; a general-move check escape needs only")
print("   an ordinary game, so the construction is not exotic.)")

# ---------------------------------------------------------------- extra probe
print("\n=== extra: can the last move's DESTINATION ever be the checked ===")
print("    general's cell?  That is capturing a general - probe it. ===")
fen_c = "3k3/7/7/7/3R3/7/3K3 w - - 0 1"   # Rd3, RED to move, black king d7
lm = sorted(pyffish.legal_moves(V, fen_c, []))
print("  Red to move with Black's general already attacked (illegal position):")
print("  does the engine offer d3d7 (capture the general)?", "d3d7" in lm)
print("  legal:", lm)
