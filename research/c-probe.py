#!/usr/bin/env python3
"""Chase-correction probe: adjudicate (variant, fen, moves) triples against a built pyffish.

Usage: python3 c-probe.py <dir-with-the-.so> [case ...]
Workspace scratch file for the fs-chase worktree; part of no repository.
"""
import sys
import pathlib

sys.path.insert(0, str(pathlib.Path(sys.argv[1]).resolve()))
import pyffish as sf  # noqa: E402

INI = """
[mxqaxf:minixiangqi]
chasingRule = axf
nMoveRule = 0

[mxqtarget:minixiangqi]
chasingRule = axf
nMoveRule = 0
promotedSoldiersChaseable = false
"""
sf.load_variant_config(INI)

MATE = 32000


def label(flag, value):
    if not flag:
        return "ongoing"
    if value == 0:
        return "draw/claimable"
    return "stm WINS" if value == MATE else ("stm LOSES" if value == -MATE else "value=%d" % value)


def probe(name, variant, fen, moves):
    flag, value = sf.is_optional_game_end(variant, fen, moves)
    stm = sf.get_fen(variant, fen, moves).split()[1]
    print("%-34s %-11s plies=%-3d stm=%s  -> (%s, %s)  %s"
          % (name, variant, len(moves), stm, flag, value if flag else "-", label(flag, value)))
    return flag, value


CASES = {}


def case(fn):
    CASES[fn.__name__] = fn
    return fn


@case
def p1():
    """mx-chs-028: an absolutely pinned chariot's threat is not a chase."""
    fen = "3rk2/7/7/3R3/1c5/7/3K3 w - - 0 1"
    wheel = ["d4d3", "b3b4", "d3d4", "b4b3"]
    for n in (4, 8, 12):
        probe("mx-chs-028 pinned chariot", "mxqaxf", fen, (wheel * 4)[:n])
    # control: same wheel, white king off the d-file, so the chariot is free
    ctl = "3rk2/7/7/3R3/1c5/7/2K4 w - - 0 1"
    for n in (4, 8, 12):
        probe("  control: chariot not pinned", "mxqaxf", ctl, (wheel * 4)[:n])


@case
def p2():
    """mx-chs-029: no flying-general pin when a piece of either colour blocks."""
    fen = "2k4/7/R6/2r4/7/2P4/2K4 w - - 0 1"
    wheel = ["a5a4", "c4c5", "a4a5", "c5c4"]
    for n in (4, 8, 12):
        probe("mx-chs-029 blocked file", "mxqaxf", fen, (wheel * 4)[:n])
    # reconciliation's control: white king off the c-file -> already a draw today
    ctl = "2k4/7/R6/2r4/7/2P4/3K3 w - - 0 1"
    for n in (4, 8):
        probe("  control: kings off one file", "mxqaxf", ctl, (wheel * 4)[:n])
    # control: nothing between the kings -> the black chariot really is pinned
    ctl2 = "2k4/7/R6/2r4/7/7/2K4 w - - 0 1"
    for n in (4, 8):
        probe("  control: real flying-gen pin", "mxqaxf", ctl2, (wheel * 4)[:n])


@case
def p3():
    """mx-chs-030/031/032 and the mutual-chase wrong-winner corner."""
    wheel = ["a5b5", "a3b3", "b5a5", "b3a3"]
    probe("mx-chs-030 quiet entry  (9)", "mxqaxf",
          "4k2/7/c6/7/7/7/R1K4 w - - 0 1", ["a1a3"] + wheel * 2)
    probe("mx-chs-030 boundary     (5)", "mxqaxf",
          "4k2/7/c6/7/7/7/R1K4 w - - 0 1", ["a1a3"] + wheel[:4])
    probe("mx-chs-031 chasing entry(9)", "mxqaxf",
          "4k2/7/c6/7/1R5/7/2K4 w - - 0 1", ["b3a3"] + wheel * 2)
    probe("mx-chs-032 one ply later(10)", "mxqaxf",
          "4k2/7/c6/7/7/7/R1K4 w - - 0 1", ["a1a3"] + wheel * 2 + ["a5b5"])
    # mutual perpetual chase, mx-mix-002 re-phased by one ply (investigate-chase-window-parity §3)
    X = "2k2r1/7/1c2R2/7/1Nr1nC1/7/1R2K2 b - - 0 1"
    mw = ["e3f5", "b3c5", "f5e3", "c5b3"]
    probe("mutual wheel, no entry  (8)", "mxqaxf", X, mw * 2)
    for entry in ("d1e1", "f5e5", "a1b1"):
        Y = {"d1e1": "2k2r1/7/1c2R2/7/1Nr1nC1/7/1R1K3 w - - 0 1",
             "f5e5": "2k2r1/7/1c2R2/7/1Nr1n1C/7/1R2K2 w - - 0 1",
             "a1b1": "2k2r1/7/1c2R2/7/1Nr1nC1/7/R3K2 w - - 0 1"}[entry]
        probe("mutual, entry %-6s   (9)" % entry, "mxqaxf", Y, [entry] + mw * 2)
        probe("mutual, entry %-6s  (10)" % entry, "mxqaxf", Y, [entry] + mw * 2 + ["e3f5"])


@case
def xq():
    """The 33 built-in xiangqi chase/check adjudications from test.py, as a regression grid."""
    import re
    src = (pathlib.Path(__file__).resolve().parent.parent / "fs-chase" / "test.py").read_text()
    block = src[src.index("def test_is_optional_game_end"):src.index("def test_has_insufficient_material")]
    n = 0
    for line in block.splitlines():
        if "_check_optional_game_end(" not in line or line.strip().startswith("#"):
            continue
        n += 1
        print("%3d %s" % (n, line.strip()[:150]))
    print("cases:", n)


if __name__ == "__main__":
    wanted = sys.argv[2:] or list(CASES)
    for w in wanted:
        print("=== %s: %s" % (w, CASES[w].__doc__))
        CASES[w]()
        print()
