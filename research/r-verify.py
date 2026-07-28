#!/usr/bin/env python3
"""Reconciliation agent: verify the contested factual claims of designs A and B.

Read-only. Loads only the prebuilt pyffish from evidence/pyffish-build and an
in-memory AXF child config (same text as fixtures-draft/minixiangqiaxf-validation.ini,
which is not read or written here).
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "evidence", "pyffish-build"))
import pyffish  # noqa: E402

BUILTIN = "minixiangqi"
AXF = "minixiangqiaxf"
INI = "[minixiangqiaxf:minixiangqi]\nchasingRule = axf\nnMoveRule = 0\n"
NOCHK = "minixiangqiaxfnochk"
INI2 = ("[minixiangqiaxfnochk:minixiangqi]\nchasingRule = axf\nnMoveRule = 0\n"
        "perpetualCheckIllegal = false\n")
MATE = 32000

pyffish.load_variant_config(INI + "\n" + INI2)
assert AXF in pyffish.variants() and NOCHK in pyffish.variants()


def playable(fen, moves, variant=AXF):
    for i, m in enumerate(moves):
        if m not in pyffish.legal_moves(variant, fen, list(moves[:i])):
            return i
    return None


def v(val):
    if val is None:
        return "-"
    if val == 0:
        return "DRAW"
    if val >= MATE - 100:
        return "STM_WINS"
    if val <= -MATE + 100:
        return "STM_LOSES"
    return str(val)


def side_after(fen, moves):
    return pyffish.get_fen(AXF, fen, list(moves)).split()[1]


def outcome(fen, moves, variant=AXF):
    """Return a human 'who loses' label, independent of side-to-move parity."""
    f, val = pyffish.is_optional_game_end(variant, fen, list(moves))
    if not f:
        return "ongoing", None
    stm = side_after(fen, moves)
    if val == 0:
        return "draw/neutral", val
    loser = stm if val <= -MATE + 100 else ("b" if stm == "w" else "w")
    return ("RED_LOSES" if loser == "w" else "BLACK_LOSES"), val


def check_flags(fen, moves):
    return "".join("T" if pyffish.gives_check(AXF, fen, list(moves[:i])) else "."
                   for i in range(len(moves) + 1))


def P(tag, fen, moves, expect="", boundary=None, variants=(AXF,)):
    bad = playable(fen, moves)
    print("\n--- %s" % tag)
    print("    fen  %s" % fen)
    print("    mvs  %s" % " ".join(moves))
    if bad is not None:
        print("    !! ILLEGAL at index %d (%s)" % (bad, moves[bad]))
        return
    for var in variants:
        lab, val = outcome(fen, moves, var)
        print("    %-22s -> %-12s (%s) %s" % (var, lab, v(val), "" if not expect else "expect=" + expect))
    if boundary is not None:
        lab, val = outcome(fen, moves[:boundary], AXF)
        print("    boundary(prefix=%d)     -> %-12s (%s)" % (boundary, lab, v(val)))
    print("    final_fen  %s   in_check=%s   checks=%s"
          % (pyffish.get_fen(AXF, fen, list(moves)),
             pyffish.gives_check(AXF, fen, list(moves)), check_flags(fen, moves)))


def M8(a, b, c, d, lead=()):
    return list(lead) + [a, b, c, d] * 2


print("=" * 78)
print("1. CONTESTED: mutual perpetual CHECK  (A: ~non-constructible; B: constructible)")
print("=" * 78)
P("B mx-mix-001 mutual perpetual check", "3c3/7/2k3C/3n3/4N2/7/3K3 w - - 0 1",
  M8("e3d5", "d4f5", "d5e3", "f5d4"), "draw", 4, (AXF, BUILTIN, NOCHK))
P("B mx-chk-003 white cannon only (control)", "7/7/2k3C/3n3/4N2/7/3K3 w - - 0 1",
  M8("e3d5", "d4f5", "d5e3", "f5d4"), "RED_LOSES", 4, (AXF, BUILTIN))
P("B mx-chk-004 black cannon only (control)", "3c3/7/2k4/3n3/4N2/7/3K3 w - - 0 1",
  M8("e3d5", "d4f5", "d5e3", "f5d4"), "BLACK_LOSES", 4, (AXF, BUILTIN))

print()
print("=" * 78)
print("2. CONTESTED: check-over-chase precedence (A: not built; B: constructible)")
print("=" * 78)
P("B mx-mix-004 check outranks chase", "3k3/7/1r3N1/7/7/2K4/3C3 w - - 0 1",
  M8("f5d6", "b5d5", "d6f5", "d5b5"), "RED_LOSES", 4, (AXF, BUILTIN, NOCHK))
P("B mx-chs-024 chase-only control", "3k3/7/1r3N1/7/7/2K4/7 w - - 0 1",
  M8("f5d6", "b5d5", "d6f5", "d5b5"), "BLACK_LOSES", 4, (AXF, BUILTIN))

print()
print("=" * 78)
print("3. CONTESTED: flying-general FALSE PIN (A: flagged unprobed; B: PATCH-REQUIRED)")
print("=" * 78)
P("B mx-chs-020 false pin", "2k4/7/R6/2r4/2N4/7/2K4 w - - 0 1",
  M8("a5a4", "c4c5", "a4a5", "c5c4"), "should be DRAW", 4, (AXF, BUILTIN))
P("B S2 control, white king off c-file", "2k4/7/R6/2r4/2N4/7/3K3 w - - 0 1",
  M8("a5a4", "c4c5", "a4a5", "c5c4"), "DRAW", 4, (AXF,))

print()
print("=" * 78)
print("4. CONTESTED: chaseThem window one move too wide (B P2; A did not find)")
print("=" * 78)
P("B mx-chs-021 lead a1a3 (on-line, no chase)", "4k2/7/c6/7/7/7/R1K4 w - - 0 1",
  M8("a5b5", "a3b3", "b5a5", "b3a3", lead=["a1a3"]), "should be RED_LOSES", 5, (AXF,))
P("B mx-chs-022 lead b3a3 (off-line, chases)", "4k2/7/c6/7/1R5/7/2K4 w - - 0 1",
  M8("a5b5", "a3b3", "b5a5", "b3a3", lead=["b3a3"]), "RED_LOSES", 5, (AXF,))

print()
print("=" * 78)
print("5. AGREED: pinned attacker (both PATCH-REQUIRED) - both constructions")
print("=" * 78)
P("A mx-chs-019", "3rk2/7/7/3R3/1c5/7/3K3 w - - 0 1",
  M8("d4d3", "b3b4", "d3d4", "b4b3"), "should be DRAW", 4, (AXF,))
P("B mx-chs-019", "2r1k2/7/7/2R4/4c2/7/2K4 w - - 0 1",
  M8("c4c3", "e3e4", "c3c4", "e4e3"), "should be DRAW", 4, (AXF,))

print()
print("=" * 78)
print("6. Mutual perpetual CHASE: A's and B's constructions + reporting gap")
print("=" * 78)
P("A mx-chs-020 mutual chase", "2k2r1/7/1cN1R2/7/2r1nC1/7/1R2K2 w - - 0 1",
  M8("c5b3", "e3f5", "b3c5", "f5e3"), "draw", 4, (AXF, BUILTIN))
P("A mx-chs-021 white half", "2k4/7/1cN1R2/7/4n2/7/1R2K2 w - - 0 1",
  M8("c5b3", "e3f5", "b3c5", "f5e3"), "RED_LOSES", 4, (AXF,))
P("A mx-chs-022 black half", "2k2r1/7/2N4/7/2r1nC1/7/4K2 w - - 0 1",
  M8("c5b3", "e3f5", "b3c5", "f5e3"), "BLACK_LOSES", 4, (AXF,))
P("B mx-mix-002 mutual chase", "3k3/7/1NR4/3r3/1N2rn1/2KR3/5n1 w - - 0 1",
  M8("c5c3", "e3e1", "c3c5", "e1e3"), "draw", 4, (AXF, BUILTIN))
print("\n    NEUTRAL threefold for comparison (mx-rep-001 style):")
P("neutral repetition", "4k2/7/c6/7/1R5/7/2K4 w - - 0 1",
  M8("c1c2", "e7d7", "c2c1", "d7e7"), "draw/neutral", 4, (AXF, BUILTIN))
