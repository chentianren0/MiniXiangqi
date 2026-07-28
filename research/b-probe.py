#!/usr/bin/env python3
"""Agent-B scratch probe harness for Mini Xiangqi AXF chase/check semantics.

Read-only with respect to every checkout: it only loads the prebuilt pyffish
extension from discussion-drafts/evidence/pyffish-build and an in-memory AXF
child variant config (identical text to fixtures-draft/minixiangqiaxf-validation.ini,
which is NOT read or modified here).

Usage:  python3 b-probe.py            # runs the built-in probe battery
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "evidence", "pyffish-build"))
import pyffish  # noqa: E402

BUILTIN = "minixiangqi"
AXF = "minixiangqiaxf"
INI = "[minixiangqiaxf:minixiangqi]\nchasingRule = axf\nnMoveRule = 0\n"
MATE = 32000


def setup():
    pyffish.load_variant_config(INI)
    assert AXF in pyffish.variants()


def board(fen):
    """Pretty 7x7 board from a Mini Xiangqi FEN."""
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


def legal(fen, moves, variant=AXF):
    return pyffish.legal_moves(variant, fen, list(moves))


def play(fen, moves, variant=AXF):
    """Return (ok, first_illegal_index_or_None)."""
    for i, m in enumerate(moves):
        if m not in pyffish.legal_moves(variant, fen, list(moves[:i])):
            return False, i
    return True, None


def ogc(fen, moves, variant=AXF):
    """is_optional_game_end, with the value blanked when the flag is False."""
    flag, val = pyffish.is_optional_game_end(variant, fen, list(moves))
    return (flag, val if flag else None)


def verdict(val):
    if val is None:
        return "none"
    if val == 0:
        return "DRAW"
    if val >= MATE - 100:
        return "STM-WINS(violator=opponent)"
    if val <= -MATE + 100:
        return "STM-LOSES(violator=stm)"
    return "val=%d" % val


def probe(name, fen, moves, note="", show=False, prefixes=(4, 6, 8)):
    ok, bad = play(fen, moves)
    print("\n=== %s ===" % name)
    if note:
        print("    " + note)
    print("    fen : %s" % fen)
    print("    mvs : %s" % " ".join(moves))
    if not ok:
        print("    !! ILLEGAL move at index %d (%s); legal there: %s"
              % (bad, moves[bad], sorted(legal(fen, moves[:bad]))))
        return None
    if show:
        print(board(pyffish.get_fen(AXF, fen, list(moves))))
    res = {}
    for n in list(prefixes) + [len(moves)]:
        if n > len(moves):
            continue
        f_a, v_a = ogc(fen, moves[:n], AXF)
        f_b, v_b = ogc(fen, moves[:n], BUILTIN)
        res[n] = (f_a, v_a, f_b, v_b)
        print("    ply %-2d  AXF=(%s,%s)->%-28s builtin=(%s,%s)"
              % (n, f_a, v_a, verdict(v_a), f_b, v_b))
    print("    final fen: %s  in_check=%s"
          % (pyffish.get_fen(AXF, fen, list(moves)), pyffish.gives_check(AXF, fen, list(moves))))
    return res


def shuttle(fen, cycle, times=2, lead=()):
    """lead + cycle repeated `times` times (a 4-ply cycle twice = 3 occurrences)."""
    return list(lead) + list(cycle) * times


if __name__ == "__main__":
    setup()
    print("pyffish", pyffish.version(), pyffish.info())
