"""Scratch: find a SHORT line from the frozen Mini Xiangqi starting position
reaching a position where the side to move is in check and can escape with a
GENERAL move -- i.e. the S4+S6 Undo construction is reachable in ordinary play
from the app's only legal start position."""
import os
import sys
from collections import deque

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "r-scratch"))
import pyffish  # noqa: E402

V = "minixiangqi"
START = "rcnkncr/p1ppp1p/7/7/7/P1PPP1P/RCNKNCR w - - 0 1"

KING_SQ = {"d1", "d7"}


def king_square(fen, side):
    board = fen.split()[0]
    rows = board.split("/")
    target = "K" if side == "w" else "k"
    for i, row in enumerate(rows):
        rank = 7 - i
        f = 0
        for ch in row:
            if ch.isdigit():
                f += int(ch)
            else:
                if ch == target:
                    return "abcdefg"[f] + str(rank)
                f += 1
    return None


seen = {START}
q = deque([(START, [])])
found = []
while q and len(found) < 3:
    fen, hist = q.popleft()
    if len(hist) > 5:
        continue
    for mv in pyffish.legal_moves(V, fen, []):
        nfen = pyffish.get_fen(V, fen, [mv])
        if nfen in seen:
            continue
        seen.add(nfen)
        nhist = hist + [mv]
        stm = nfen.split()[1]
        in_check = pyffish.gives_check(V, fen, [mv])
        if in_check:
            evasions = pyffish.legal_moves(V, nfen, [])
            ksq = king_square(nfen, stm)
            gen_evasions = [m for m in evasions if m.startswith(ksq)]
            if gen_evasions:
                found.append((nhist, nfen, stm, ksq, sorted(evasions),
                              sorted(gen_evasions)))
                if len(found) >= 3:
                    break
        if len(nhist) <= 4:
            q.append((nfen, nhist))

for hist, fen, stm, ksq, ev, gev in found:
    print("line from START:", " ".join(hist))
    print("  position P   :", fen)
    print("  side to move :", stm, " IN CHECK, general on", ksq)
    print("  all evasions :", ev)
    print("  GENERAL evasions:", gev)
    esc = gev[0]
    after = pyffish.get_fen(V, fen, [esc])
    print(f"  play {esc} -> Q:", after)
    print("  Undo -> back at P: general is on", ksq,
          "= ORIGIN cell of the undone move, and the side to move is in check.")
    print()
