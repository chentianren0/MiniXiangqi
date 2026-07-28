#!/usr/bin/env python3
"""Replay the sixteen APPROVED fixtures against the current fork HEAD engine."""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from r_harness import MX, setup, ogc, play, loser  # noqa: E402
import pyffish  # noqa: E402

FIX = "/Users/tianren/coding/minixiangqi/MiniXiangqi/fixtures/rules"

STATE_FROM_VALUE = {}


def expected_engine(gs, stm_is_red):
    """Translate a fixture game_state into (flag, side-to-move-relative value)."""
    st = gs["state"]
    if st == "ongoing":
        return (False, None)
    if st in ("claimable-draw", "draw"):
        return (True, 0)
    if st == "red-wins":
        return (True, 32000 if stm_is_red else -32000)
    if st == "black-wins":
        return (True, -32000 if stm_is_red else 32000)
    return (None, None)


def main():
    setup()
    ids = sorted(os.listdir(FIX))
    bad = []
    for fn in ids:
        if not fn.endswith(".json"):
            continue
        d = json.load(open(os.path.join(FIX, fn)))
        fen = d["start_fen"]
        moves = d["moves"]
        ok, i = play(fen, moves, MX)
        note = []
        if not ok:
            note.append("ILLEGAL@%d(%s)" % (i, moves[i]))
        rf = pyffish.get_fen(MX, fen, list(moves))
        a = d["assertions"]
        if rf != a["result_fen"]:
            note.append("FEN got=%s want=%s" % (rf, a["result_fen"]))
        ic = pyffish.gives_check(MX, fen, list(moves))
        if bool(ic) != bool(a["in_check"]):
            note.append("in_check got=%s want=%s" % (ic, a["in_check"]))
        gs = a["game_state"]
        stm_is_red = rf.split()[1] == "w"
        want = expected_engine(gs, stm_is_red)
        got = ogc(fen, moves, MX)
        if gs["state"] == "checkmate" or gs["reason"] in ("checkmate", "stalemate"):
            gr = pyffish.game_result(MX, fen, list(moves))
            note.append("immediate game_result=%s (state=%s/%s)" % (gr, gs["state"], gs["reason"]))
        elif got != want:
            note.append("OGC got=%s want=%s (state=%s/%s)" % (got, want, gs["state"], gs["reason"]))
        b = d.get("boundary")
        if b:
            pf = b["prefix_len"]
            gb = ogc(fen, moves[:pf], MX)
            if gb[0]:
                note.append("BOUNDARY ply%d already ended: %s" % (pf, gb))
        status = "OK  " if not note else "FAIL"
        if note:
            bad.append(d["id"])
        print("%s %-12s %s" % (status, d["id"], "; ".join(note)))
    print("\nfailures:", bad)


if __name__ == "__main__":
    main()
