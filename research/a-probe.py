#!/usr/bin/env python3
"""Agent-A scratch probe for Mini Xiangqi perpetual edge cases.

Read-only research tool. Loads the prebuilt workspace pyffish and the scratch
AXF child, then reports is_optional_game_end / check state along a scripted
line. Nothing here is normative; it records engine behaviour only.

Usage:  python3 a-probe.py            (runs the built-in case list)
        import a-probe as a module is not supported; edit CASES below.
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "evidence", "pyffish-build"))
import pyffish  # noqa: E402

INI = os.path.join(HERE, "fixtures-draft", "minixiangqiaxf-validation.ini")
AXF = "minixiangqiaxf"
BUILTIN = "minixiangqi"


def load():
    with open(INI) as fh:
        pyffish.load_variant_config(fh.read())
    assert AXF in pyffish.variants()


def legal(variant, fen, moves):
    return pyffish.legal_moves(variant, fen, list(moves))


def probe(label, fen, moves, variant=AXF, verbose=True, expect=None):
    """Replay `moves` from `fen`, print per-ply optional-game-end state."""
    print(f"\n=== {label} ===")
    print(f"    start {fen}")
    ok = True
    for i in range(len(moves) + 1):
        pre = list(moves[:i])
        if i > 0:
            lm = legal(variant, fen, moves[: i - 1])
            if moves[i - 1] not in lm:
                print(f"    ply {i}: ILLEGAL MOVE {moves[i-1]!r}; legal={sorted(lm)}")
                return False
        cur = pyffish.get_fen(variant, fen, pre)
        chk = pyffish.gives_check(variant, fen, pre)
        oge = pyffish.is_optional_game_end(variant, fen, pre)
        flag = oge[0]
        val = oge[1] if flag else None
        if verbose or flag:
            print(
                f"    ply {i:2d} {'|'.join(pre[-1:]) or '-':>5}  fen={cur}"
                f"  incheck={chk}  optend={flag} val={val}"
            )
        if flag and expect is not None and i == len(moves):
            ok = val == expect
    return ok


def verdict(fen, moves, variant=AXF):
    """Return (flag, value) at the end of the line, or an error string."""
    for i in range(len(moves)):
        lm = legal(variant, fen, list(moves[:i]))
        if moves[i] not in lm:
            return f"ILLEGAL ply {i+1} {moves[i]}: legal={sorted(lm)}"
    f, v = pyffish.is_optional_game_end(variant, fen, list(moves))
    return (f, v if f else None)


def label_value(v):
    if v is None:
        return "-"
    if v == 32000:
        return "SIDE-TO-MOVE WINS (mover-just-moved loses)"
    if v == -32000:
        return "SIDE-TO-MOVE LOSES"
    if v == 0:
        return "DRAW"
    return str(v)


if __name__ == "__main__":
    load()
    print("pyffish", pyffish.info(), "variants ok")
    print("start_fen:", pyffish.start_fen(AXF))
