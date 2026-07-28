#!/usr/bin/env python3
"""PR #22 review, item 1: isolate the 'advance along an existing attacking line'
case that the accepted renewal wording must decide.

Under the engine (position.cpp:3037 discards a rook/cannon's along-the-line
attacks, and the exact before/after test at :3050-3052 does not re-admit them
when the line was already clear), advancing along the line does NOT renew.
Under a plain-English reading of the contract's new bullet ("attacks the target
from the square it now occupies and did not attack it from that square before
the move"), every move to a new square renews vacuously.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "r-scratch"))
import pyffish  # noqa: E402

MX = "minixiangqitarget"
BUILTIN = "minixiangqi"
INI = (
    "[minixiangqitarget:minixiangqi]\n"
    "chasingRule = axf\n"
    "nMoveRule = 0\n"
    "promotedSoldiersChaseable = false\n"
)


def run(name, fen, moves):
    print("\n=== %s ===" % name)
    print("  fen   : %s" % fen)
    print("  moves : %s (%d plies)" % (" ".join(moves), len(moves)))
    for i, m in enumerate(moves):
        if m not in pyffish.legal_moves(MX, fen, list(moves[:i])):
            print("  !! ILLEGAL at %d (%s)" % (i, m))
            return
    for n in (len(moves) - 4, len(moves)):
        f, v = pyffish.is_optional_game_end(MX, fen, list(moves[:n]))
        fb, vb = pyffish.is_optional_game_end(BUILTIN, fen, list(moves[:n]))
        tag = ""
        if f and v == 0:
            tag = "DRAW"
        elif f:
            stm = pyffish.get_fen(MX, fen, list(moves[:n])).split()[1]
            tag = "LOSER=" + (("Red" if stm == "w" else "Black") if v < 0
                              else ("Black" if stm == "w" else "Red"))
        print("  ply %-2d target=(%s,%s) builtin=(%s,%s)  %s"
              % (n, f, v if f else "-", fb, vb if fb else "-", tag))


pyffish.load_variant_config(INI)
print("pyffish", pyffish.version(), pyffish.info())

# White rook shuttles a1 <-> a3 on the a-file. The black cannon on a5 is under
# attack from BOTH squares and never moves; the black king shuttles e7 <-> e6.
# Every white move keeps the same undefended cannon attacked; no white move
# creates an attack that did not already stand.
run("ALONG the line: rook a1<->a3, cannon a5 attacked from both squares",
    "4k2/7/c6/7/7/7/R2K3 w - - 0 1",
    ["a1a3", "e7e6", "a3a1", "e6e7"] * 2)

# Differential: the same wheel, but the rook leaves and re-enters the file, so
# each entry creates an attack that did not stand from that square before.
run("ACROSS onto the line: rook b3<->a3, cannon a5",
    "4k2/7/c6/7/1R5/7/3K3 w - - 0 1",
    ["b3a3", "e7e6", "a3b3", "e6e7"] * 2)
