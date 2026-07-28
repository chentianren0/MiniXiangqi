#!/usr/bin/env python3
"""Reconciliation pass 2: replay every fixture proposed by A and by B."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "evidence", "pyffish-build"))
import pyffish  # noqa: E402

BUILTIN, AXF = "minixiangqi", "minixiangqiaxf"
pyffish.load_variant_config("[minixiangqiaxf:minixiangqi]\nchasingRule = axf\nnMoveRule = 0\n")
MATE = 32000


def label(fen, moves, variant=AXF):
    for i, m in enumerate(moves):
        if m not in pyffish.legal_moves(variant, fen, list(moves[:i])):
            return "ILLEGAL@%d(%s)" % (i, m)
    f, val = pyffish.is_optional_game_end(variant, fen, list(moves))
    if not f:
        return "ongoing"
    stm = pyffish.get_fen(AXF, fen, list(moves)).split()[1]
    if val == 0:
        return "draw/neutral"
    loser = stm if val <= -MATE + 100 else ("b" if stm == "w" else "w")
    return "RED_LOSES" if loser == "w" else "BLACK_LOSES"


def row(tag, fen, moves, expect, bnd):
    got = label(fen, moves)
    b = label(fen, moves[:bnd]) if bnd else "-"
    ok = "OK " if got == expect else "!! "
    print("%s%-46s %-13s exp=%-13s bnd@%-2s=%-13s %s"
          % (ok, tag, got, expect, bnd, b,
             pyffish.get_fen(AXF, fen, list(moves))))


def M8(a, b, c, d, lead=()):
    return list(lead) + [a, b, c, d] * 2


print("=== AGENT A's proposed tranche ===")
A = [
 ("A005 pinned defender",      "4k2/7/c3r2/7/1R5/7/2K1R2 w - - 0 1", M8("b3a3","a5b5","a3b3","b5a5"), "BLACK_LOSES", 4),
 ("A006 screenless cannon def","4k2/7/c3c2/7/1R5/7/2K4 w - - 0 1",   M8("b3a3","a5b5","a3b3","b5a5"), "BLACK_LOSES", 4),
 ("A007 king def outside pal", "7/7/1ck4/7/7/7/R3K2 w - - 0 1",      M8("a1b1","b5a5","b1a1","a5b5"), "BLACK_LOSES", 4),
 ("A008 king def inside pal",  "7/3k3/3c3/6R/7/7/2K4 w - - 0 1",     M8("g4g5","d5d4","g5g4","d4d5"), "draw/neutral", 4),
 ("A009 king def flying gen",  "4R2/7/2kc3/7/7/7/3K3 w - - 0 1",     M8("e7d7","d5e5","d7e7","e5d5"), "BLACK_LOSES", 4),
 ("A010 control king off file","4R2/7/2kc3/7/7/7/4K2 w - - 0 1",     M8("e7d7","d5e5","d7e7","e5d5"), "draw/neutral", 4),
 ("A011 horse v protected rook","4k2/3N3/r3r2/7/7/7/3K3 w - - 0 1",  M8("d6c4","a5b5","c4d6","b5a5"), "BLACK_LOSES", 4),
 ("A012 horse v protected cann","4k2/3N3/c3r2/7/7/7/3K3 w - - 0 1",  M8("d6c4","a5b5","c4d6","b5a5"), "draw/neutral", 4),
 ("A013 rook v rook exchange", "4k2/7/r6/7/1R5/7/2K4 w - - 0 1",     M8("b3a3","a5b5","a3b3","b5a5"), "draw/neutral", 4),
 ("A014 one chase one idle",   "3k3/7/c6/7/1R5/7/2K4 w - - 0 1",     M8("b3a3","a5a6","a3b3","a6a5"), "draw/neutral", 4),
 ("A015 six-ply all chase",    "3k3/7/c6/7/2R4/7/4K2 w - - 0 1",     ["c3a3","a5b5","a3b3","b5c5","b3c3","c5a5"]*2, "BLACK_LOSES", 6),
 ("A016 idle inside span",     "4k2/7/c6/7/1R5/7/2K4 w - - 0 1",     ["c1c2","e7e6","c2c1","e6e7","b3a3","a5b5","a3b3","b5a5"], "draw/neutral", 4),
 ("A017 idle then two cycles", "4k2/7/c6/7/1R5/7/2K4 w - - 0 1",     ["c1c2","e7e6","c2c1","e6e7"]+M8("b3a3","a5b5","a3b3","b5a5"), "BLACK_LOSES", 4),
 ("A018 pure discovered chase","4k2/7/R1Nc3/7/7/7/2KR3 w - - 0 1",   M8("c5d3","e7e6","d3c5","e6e7"), "BLACK_LOSES", 4),
 ("A019 pinned attacker",      "3rk2/7/7/3R3/1c5/7/3K3 w - - 0 1",   M8("d4d3","b3b4","d3d4","b4b3"), "draw/neutral", 4),
 ("A020 mutual chase",         "2k2r1/7/1cN1R2/7/2r1nC1/7/1R2K2 w - - 0 1", M8("c5b3","e3f5","b3c5","f5e3"), "draw/neutral", 4),
 ("A021 white half",           "2k4/7/1cN1R2/7/4n2/7/1R2K2 w - - 0 1", M8("c5b3","e3f5","b3c5","f5e3"), "RED_LOSES", 4),
 ("A022 black half",           "2k2r1/7/2N4/7/2r1nC1/7/4K2 w - - 0 1", M8("c5b3","e3f5","b3c5","f5e3"), "BLACK_LOSES", 4),
 ("A023 alternating targets",  "3k3/7/c5c/7/R6/7/2K4 w - - 0 1",     M8("a3g3","d7d6","g3a3","d6d7"), "draw/neutral", 4),
 ("A024 alternating attackers","R6/7/c3k2/7/1R5/7/3K3 w - - 0 1",    ["b3a3","a5b5","a7b7","b5a5","b7a7","a5b5","a3b3","b5a5"]*2, "BLACK_LOSES", 8),
 ("A025 soldier as chaser",    "4k2/7/1c5/2P4/7/7/3K3 w - - 0 1",    M8("c4b4","b5c5","b4c4","c5b5"), "draw/neutral", 4),
 ("A026 king as chaser",       "4k2/7/7/7/2c4/3K3/7 w - - 0 1",      M8("d2c2","c3d3","c2d2","d3c3"), "draw/neutral", 4),
 ("Achk003 check/chase altern","3k3/7/c6/R6/7/7/4K2 w - - 0 1",      M8("a4d4","d7c7","d4a4","c7d7"), "draw/neutral", 4),
]
for t in A:
    row(*t)

print("\n=== AGENT B's proposed tranche ===")
B = [
 ("B005 pinned defender",      "4k2/7/c3r2/7/1R5/7/2K1R2 w - - 0 1", M8("b3a3","a5b5","a3b3","b5a5"), "BLACK_LOSES", 4),
 ("B006 c-file chase base",    "3k3/4R2/2c4/7/7/7/2K4 w - - 0 1",    M8("e6e5","c5c6","e5e6","c6c5"), "BLACK_LOSES", 4),
 ("B007 X-ray defender",       "3k3/4R2/2c3r/7/7/7/2K4 w - - 0 1",   M8("e6e5","c5c6","e5e6","c6c5"), "draw/neutral", 4),
 ("B008 king def + flying gen","2k4/4R2/2c4/7/7/7/2K4 w - - 0 1",    M8("e6e5","c5c6","e5e6","c6c5"), "BLACK_LOSES", 4),
 ("B009 king def legal recap", "2k4/4R2/2c4/7/7/7/3K3 w - - 0 1",    M8("e6e5","c5c6","e5e6","c6c5"), "draw/neutral", 4),
 ("B010 soldier defender",     "3k3/1p2R2/2c4/7/7/7/2K4 w - - 0 1",  M8("e6e5","c5c6","e5e6","c6c5"), "draw/neutral", 4),
 ("B023 king recap illegal-oth","2k4/4R2/2c4/1N5/7/7/3K3 w - - 0 1", M8("e6e5","c5c6","e5e6","c6c5"), "draw/neutral", 4),
 ("B011 horse v protected rook","3k3/7/3r2r/N6/7/7/4K2 w - - 0 1",   M8("a4c3","d5c5","c3a4","c5d5"), "BLACK_LOSES", 4),
 ("B012 horse v protected cann","3k3/7/3c2r/N6/7/7/4K2 w - - 0 1",   M8("a4c3","d5c5","c3a4","c5d5"), "draw/neutral", 4),
 ("B013 rook v rook",          "3k3/7/3r3/R6/7/7/2K4 w - - 0 1",     M8("a4a5","d5d4","a5a4","d4d5"), "draw/neutral", 4),
 ("B014 same-type but pinned", "3k3/7/3r3/R6/7/7/2KR3 w - - 0 1",    M8("a4a5","d5d4","a5a4","d4d5"), "BLACK_LOSES", 4),
 ("B015 soldier mover",        "4k2/7/7/c6/1P5/7/2K4 w - - 0 1",     M8("b3a3","a4b4","a3b3","b4a4"), "draw/neutral", 4),
 ("B016 king mover",           "4k2/7/7/7/2c4/2K4/7 w - - 0 1",      M8("c2d2","c3d3","d2c2","d3c3"), "draw/neutral", 4),
 ("B017 pure discovered chase","4k2/7/R2n3/7/3N3/7/2KR3 w - - 0 1",  M8("d3c5","e7e6","c5d3","e6e7"), "BLACK_LOSES", 4),
 ("B018 alternating targets",  "4k2/3n3/2c4/2R4/7/7/3K3 w - - 0 1",  M8("c4d4","e7e6","d4c4","e6e7"), "draw/neutral", 4),
 ("B022 chaser not to move",   "4k2/7/c6/7/1R5/7/2K4 w - - 0 1",     ["b3a3"]+M8("a5b5","a3b3","b5a5","b3a3"), "RED_LOSES", 5),
 ("Bmix003 check/chase altern","3k3/7/2c4/2R4/7/7/4K2 w - - 0 1",    M8("c4d4","d7c7","d4c4","c7d7"), "draw/neutral", 4),
]
for t in B:
    row(*t)

print("\n=== extra adjudications ===")
row("A king-root 2nd-attacker under-detection", "7/3k3/3c3/6R/4N2/7/2K4 w - - 0 1",
    M8("g4g5","d5d4","g5g4","d4d5"), "draw/neutral", 4)
print("   (A claims this SHOULD be a violation; engine says draw = under-detection)")
row("A015b six-ply, one move blocked", "3k3/7/c6/2P4/2R4/7/4K2 w - - 0 1",
    ["c3a3","a5b5","a3b3","b5c5","b3c3","c5a5"]*2, "draw/neutral", 6)

# is the black rook in the false-pin position really free?
print("\n=== false-pin position: black rook legality ===")
fen = "2k4/7/R6/2r4/2N4/7/2K4 w - - 0 1"
print("  black legal moves after a5a4:", sorted(pyffish.legal_moves(AXF, fen, ["a5a4"])))
