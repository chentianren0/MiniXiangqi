#!/usr/bin/env python3
"""Reconciliation pass 3: boundary prefixes, renewal-semantics discriminator."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "evidence", "pyffish-build"))
import pyffish  # noqa: E402

AXF, BUILTIN = "minixiangqiaxf", "minixiangqi"
pyffish.load_variant_config("[minixiangqiaxf:minixiangqi]\nchasingRule = axf\nnMoveRule = 0\n")
MATE = 32000


def lab(fen, moves):
    f, val = pyffish.is_optional_game_end(AXF, fen, list(moves))
    if not f:
        return "ongoing"
    stm = pyffish.get_fen(AXF, fen, list(moves)).split()[1]
    if val == 0:
        return "draw/neutral"
    loser = stm if val <= -MATE + 100 else ("b" if stm == "w" else "w")
    return "RED_LOSES" if loser == "w" else "BLACK_LOSES"


def scan(tag, fen, moves, marks):
    print("\n%s\n  %s | %s" % (tag, fen, " ".join(moves)))
    for n in marks:
        print("    ply %-2d -> %-13s %s" % (n, lab(fen, moves[:n]),
                                            pyffish.get_fen(AXF, fen, list(moves[:n]))))


M = lambda a, b, c, d: [a, b, c, d] * 2

scan("A017 idle interlude then two chase cycles (12 plies)",
     "4k2/7/c6/7/1R5/7/2K4 w - - 0 1",
     ["c1c2", "e7e6", "c2c1", "e6e7"] + M("b3a3", "a5b5", "a3b3", "b5a5"),
     [4, 8, 12])

scan("A024 alternating attackers (16 plies)",
     "R6/7/c3k2/7/1R5/7/3K3 w - - 0 1",
     ["b3a3", "a5b5", "a7b7", "b5a5", "b7a7", "a5b5", "a3b3", "b5a5"] * 2,
     [8, 16])

scan("A015 six-ply cycle (12 plies)",
     "3k3/7/c6/7/2R4/7/4K2 w - - 0 1",
     ["c3a3", "a5b5", "a3b3", "b5c5", "b3c3", "c5a5"] * 2,
     [6, 12])

print("\n" + "=" * 78)
print("RENEWAL SEMANTICS DISCRIMINATOR  (A: 'attack must not have existed before'")
print("                                  B: 'must be new from the square now occupied')")
print("=" * 78)
# Rook on d5 already attacks f5; d5->b5 keeps attacking f5 through the vacated d5.
# Under A's reading that move renews nothing; under B's / the engine's it does.
scan("mx-chs-024/033 chase-only control (B's construction)",
     "3k3/7/1r3N1/7/7/2K4/7 w - - 0 1",
     M("f5d6", "b5d5", "d6f5", "d5b5"), [4, 8])
print("  engine says BLACK_LOSES -> engine implements B's square-relative renewal test.")
print("  Under A's absolute test, ply-4/8 (d5b5) renews nothing and this is a neutral draw.")

# minimal isolation: does a slider moving AWAY along its own line 'renew'?
print("\n  isolation probe: white rook slides along rank 5 keeping the same cannon attacked")
scan("  rook d5<->b5 vs stationary black cannon on f5 (no other white piece)",
     "3k3/7/1R3c1/7/7/2K4/7 w - - 0 1",
     M("d5b5", "d7c7", "b5d5", "c7d7"), [4, 8])
