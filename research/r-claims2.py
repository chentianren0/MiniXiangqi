#!/usr/bin/env python3
"""Second verification pass: parity asymmetry, cleaner P1, per-ply check states."""
import sys, os
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from r_harness import *  # noqa
import pyffish  # noqa

setup()


def checks_per_ply(fen, moves, variant=MX):
    out = []
    for i in range(len(moves) + 1):
        out.append("T" if pyffish.gives_check(variant, fen, list(moves[:i])) else "f")
    return "".join(out)


print("\n############ P2 parity: SAME position + SAME non-chasing lead move, other parity ############")
fen21 = "4k2/7/c6/7/7/7/R1C4 w - - 0 1"
fen21 = "4k2/7/c6/7/7/7/R1K4 w - - 0 1"
w = ["a5b5", "a3b3", "b5a5", "b3a3"]
probe("021 (chaser NOT to move at detection): 9 plies",
      fen21, ["a1a3"] + w * 2, prefixes=[5, 9])
probe("021-mirror (chaser IS to move at detection): 10 plies",
      fen21, ["a1a3"] + w * 2 + ["a5b5"], prefixes=[2, 6, 10],
      note="occurrences of 'Ra3/cb5, white to move' at plies 2/6/10; chaseUs window is correct")

print("\n############ P1 cleaner repro: blocking piece does NOT defend the rook ############")
probe("P1-clean: white soldier c2 blocks the c-file; both rooks undefended",
      "2k4/7/R6/2r4/7/2P4/2K4 w - - 0 1", M8("a5a4", "c4c5", "a4a5", "c5c4"),
      note="symmetric rook-vs-rook; black rook is NOT pinned (Pc2 blocks the file)")
probe("P1-clean control: white king off the c-file (d1)",
      "2k4/7/R6/2r4/7/2P4/3K3 w - - 0 1", M8("a5a4", "c4c5", "a4a5", "c5c4"))
print("   black rook legal moves after a5a4 (clean):",
      sorted(m for m in pyffish.legal_moves(MX, "2k4/7/R6/2r4/7/2P4/2K4 w - - 0 1", ["a5a4"]) if m.startswith("c4")))
print("   white rook defended? white legal moves incl. nothing recapturing a4/a5 is the point")

print("\n############ per-ply check states for the mutual/mixed constructions ############")
for name, fen, mv in [
    ("mx-mix-001 mutual perpetual check", "3c3/7/2k3C/3n3/4N2/7/3K3 w - - 0 1", M8("e3d5","d4f5","d5e3","f5d4")),
    ("chk-003 white alone", "7/7/2k3C/3n3/4N2/7/3K3 w - - 0 1", M8("e3d5","d4f5","d5e3","f5d4")),
    ("chk-004 black alone", "3c3/7/2k4/3n3/4N2/7/3K3 w - - 0 1", M8("e3d5","d4f5","d5e3","f5d4")),
    ("mx-mix-004 check over chase", "3k3/7/1r3N1/7/7/2K4/3C3 w - - 0 1", M8("f5d6","b5d5","d6f5","d5b5")),
    ("mx-chs-024 chase alone", "3k3/7/1r3N1/7/7/2K4/7 w - - 0 1", M8("f5d6","b5d5","d6f5","d5b5")),
    ("A mx-chs-020 mutual chase", "2k2r1/7/1cN1R2/7/2r1nC1/7/1R2K2 w - - 0 1", M8("c5b3","e3f5","b3c5","f5e3")),
    ("B mx-mix-002 mutual chase", "3k3/7/1NR4/3r3/1N2rn1/2KR3/5n1 w - - 0 1", M8("c5c3","e3e1","c3c5","e1e3")),
]:
    print("  %-38s checks(ply0..8) = %s" % (name, checks_per_ply(fen, mv)))

print("\n############ reason reporting: neutral threefold vs mutual violation ############")
for name, fen, mv in [
    ("neutral threefold (mx-rep-001-like)", "4k2/7/c6/7/1R5/7/2K4 w - - 0 1", M8("c1c2","e7e6","c2c1","e6e7")),
    ("mutual perpetual chase (mix-002)", "3k3/7/1NR4/3r3/1N2rn1/2KR3/5n1 w - - 0 1", M8("c5c3","e3e1","c3c5","e1e3")),
    ("mutual perpetual check (mix-001)", "3c3/7/2k3C/3n3/4N2/7/3K3 w - - 0 1", M8("e3d5","d4f5","d5e3","f5d4")),
]:
    print("  %-38s ogc=%s  checks=%s" % (name, ogc(fen, mv), checks_per_ply(fen, mv)))
