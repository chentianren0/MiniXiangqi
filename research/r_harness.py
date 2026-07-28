#!/usr/bin/env python3
"""Reconciliation harness: drives the CURRENT fork HEAD engine (77d602e0).

Loads the freshly built pyffish from discussion-drafts/r-scratch (built from a
copy of the fork; the checkout itself is untouched), and registers the target
Mini Xiangqi variant WITH promotedSoldiersChaseable = false.
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "r-scratch"))
import pyffish  # noqa: E402

BUILTIN = "minixiangqi"
# Target app variant per the fork patch: soldiers exempt as chase targets.
MX = "minixiangqitarget"
# Old (pre-patch-equivalent) AXF child: soldiers chaseable, as both agents probed.
AXF = "minixiangqiaxf"

INI = (
    "[minixiangqiaxf:minixiangqi]\n"
    "chasingRule = axf\n"
    "nMoveRule = 0\n"
    "\n"
    "[minixiangqitarget:minixiangqi]\n"
    "chasingRule = axf\n"
    "nMoveRule = 0\n"
    "promotedSoldiersChaseable = false\n"
    "\n"
    "[minixiangqinochk:minixiangqi]\n"
    "chasingRule = axf\n"
    "nMoveRule = 0\n"
    "promotedSoldiersChaseable = false\n"
    "perpetualCheckIllegal = false\n"
)
NOCHK = "minixiangqinochk"
MATE = 32000


def setup():
    pyffish.load_variant_config(INI)
    for v in (MX, AXF, NOCHK):
        assert v in pyffish.variants(), v


def board(fen):
    rows = fen.split()[0].split("/")
    out = []
    for i, r in enumerate(rows):
        rank = 7 - i
        line = []
        for ch in r:
            if ch.isdigit():
                line += ["."] * int(ch)
            else:
                line.append(ch)
        out.append("%d  %s" % (rank, " ".join(line)))
    out.append("   " + " ".join("abcdefg"))
    return "\n".join(out)


def play(fen, moves, variant=MX):
    for i, m in enumerate(moves):
        if m not in pyffish.legal_moves(variant, fen, list(moves[:i])):
            return False, i
    return True, None


def ogc(fen, moves, variant=MX):
    flag, val = pyffish.is_optional_game_end(variant, fen, list(moves))
    return (flag, val if flag else None)


def verdict(val):
    if val is None:
        return "ongoing"
    if val == 0:
        return "DRAW"
    if val >= MATE - 200:
        return "STM-WINS (violator = opponent, i.e. the side that just moved)"
    if val <= -MATE + 200:
        return "STM-LOSES (violator = side to move)"
    return "val=%d" % val


def loser(fen, moves, val, variant=MX):
    """Map a side-to-move-relative value to Red/Black."""
    if val is None or val == 0:
        return None
    stm = pyffish.get_fen(variant, fen, list(moves)).split()[1]
    stm_is_red = (stm == "w")
    if val < 0:
        return "Red" if stm_is_red else "Black"
    return "Black" if stm_is_red else "Red"


def probe(name, fen, moves, note="", variants=(MX,), prefixes=None, show=False):
    ok, bad = play(fen, moves, variants[0])
    print("\n=== %s ===" % name)
    if note:
        print("    " + note)
    print("    fen : %s" % fen)
    print("    mvs : %s" % " ".join(moves))
    if not ok:
        print("    !! ILLEGAL at index %d (%s); legal there: %s"
              % (bad, moves[bad], sorted(pyffish.legal_moves(variants[0], fen, list(moves[:bad])))))
        return None
    if show:
        print(board(pyffish.get_fen(variants[0], fen, list(moves))))
    if prefixes is None:
        prefixes = []
        n = len(moves)
        if n >= 8:
            prefixes = [n - 4]
    out = {}
    for n in list(prefixes) + [len(moves)]:
        line = "    ply %-2d " % n
        for v in variants:
            f, val = ogc(fen, moves[:n], v)
            out[(n, v)] = (f, val)
            line += " %s=(%s,%s)" % (v.replace("minixiangqi", ""), f, val)
        f, val = out[(n, variants[0])]
        line += "  -> %s" % verdict(val)
        lo = loser(fen, moves[:n], val, variants[0])
        if lo:
            line += "  [LOSER=%s]" % lo
        print(line)
    ff = pyffish.get_fen(variants[0], fen, list(moves))
    print("    final fen: %s  in_check(final)=%s" % (ff, pyffish.gives_check(variants[0], fen, list(moves))))
    return out


def M8(a, b, c, d, times=2, lead=()):
    return list(lead) + [a, b, c, d] * times


if __name__ == "__main__":
    setup()
    print("pyffish", pyffish.version(), pyffish.info())
    print("variants ok:", MX in pyffish.variants())
