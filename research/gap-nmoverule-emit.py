#!/usr/bin/env python3
"""Emit the nMoveRule fixtures from the independent contract implementation.

Every value written into the fixture files below is computed by
gap_nmoverule_rules.py (the contract implementation), never read back from
Fairy-Stockfish.
"""
import json
import pathlib
import sys

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from gap_nmoverule_rules import Position, START_FEN, name_sq, sq_name

OUT = pathlib.Path("/Users/tianren/coding/minixiangqi/gap-nmoverule/fixtures/rules")

LONG_MOVES = ["f1f2", "f7f6", "f2f3", "f6f5", "f3a3", "f5a5", "a3g3", "a5g5",
              "b1b2", "b7b6", "e2e3", "e6e5", "c2c3", "c6c5", "a1b1", "a7b7",
              "b2b3", "b6b5", "e3f3", "e5f5", "c3d3", "c5d5", "f3e3", "f5e5",
              "d2c2", "d6c6", "b1b2", "b7b6", "c2d2", "c6d6", "b3a3", "b5a5",
              "g2f2", "g6f6", "a3c3", "a5c5", "c1b3", "c7b5", "e1f3", "e7f5",
              "f2e2", "f6e6", "a2a3", "a6a5", "b2b1", "b6b7", "g1f1", "g7f7",
              "c3c1", "c5c7", "d2c2", "d6c6", "g3g2", "g5g6", "e2d2", "e6d6",
              "f1f2", "f7f6", "g2g3", "g6g5", "b1a1", "b7a7", "c2c3", "c6c5",
              "f2f1", "f6f7", "f3e1", "f5e7", "g3f3", "g5f5", "f1f2", "f7f6",
              "a1a2", "a7a6", "d2c2", "d6c6", "f3g3", "f5g5", "b3a1", "b5a7",
              "g3f3", "g5f5", "c2b2", "c6b6", "c1c2", "c7c6", "f2g2", "f6g6",
              "c2d2", "c6d6", "g2f2", "g6f6", "f2e2", "f6e6", "a1c2", "a7c6",
              "e2g2", "e6g6", "a2a1", "a6a7", "b2a2", "b6a6", "a1b1", "a7b7"]

PROBE = "a3a4"

SHORT_START = "4k2/7/7/3P3/7/7/2K4 w - - 99 60"
SHORT_MOVES = ["d4d5"]


def mirror(uci):
    (f1, r1), (f2, r2) = name_sq(uci[:2]), name_sq(uci[2:])
    return sq_name(f1, 6 - r1) + sq_name(f2, 6 - r2)


def verify_long():
    p = Position.from_fen(START_FEN)
    counts = {p.key(): 1}
    for i, m in enumerate(LONG_MOVES):
        assert m in p.legal_moves(), (i, m, p.fen())
        assert not p.is_capture(m), ("capture", i, m)
        if i % 2 == 1:
            assert m == mirror(LONG_MOVES[i - 1]), ("not a mirror", i, m)
        p = p.push(m)
        assert not p.in_check(), ("check given", i, m)
        counts[p.key()] = counts.get(p.key(), 0) + 1
    assert max(counts.values()) == 1, "a position repeats"
    assert p.halfmove == len(LONG_MOVES)
    return p


def main():
    final = verify_long()
    print("long final:", final.fen(), "halfmove", final.halfmove,
          "in_check", final.in_check(), "legal", len(final.legal_moves()))
    assert PROBE in final.legal_moves()
    probed = final.push(PROBE)
    print("probe", PROBE, "->", probed.fen(), "in_check", probed.in_check())

    cnt1 = {
        "id": "mx-cnt-001",
        "title": "A 104-ply capture-free game with no repeated position is still ongoing",
        "area": "cnt",
        "variant": "minixiangqi",
        "start_fen": START_FEN,
        "moves": LONG_MOVES,
        "assertions": {
            "in_check": False,
            "result_fen": final.fen(),
            "legal_moves": None,
            "rejected_moves": None,
            "applied": [
                {"move": PROBE, "result_fen": probed.fen(), "in_check": probed.in_check()}
            ],
            "game_state": {"state": "ongoing", "reason": None},
        },
        "boundary": None,
        "rationale": (
            "Mini Xiangqi has no automatic move-count draw, so a capture-free game of any length "
            "is still being played. Black answers every Red move with its reflection through the "
            "horizontal axis, the symmetry of the starting position, so the history is verified by "
            "reading Red's 52 moves. No move is a capture, so FEN field 5 counts every ply and "
            "reaches 104; no position occurs twice anywhere in the history, so no repetition claim "
            "exists at any point; and no move gives check, so neither perpetual class is in "
            "question. The position is ongoing, and the probe applies a further soldier move that "
            "carries field 5 to 105. A variant that omits nMoveRule = 0 and so keeps the inherited "
            "value of 50 instead rules a draw the moment field 5 reaches 100, four plies before "
            "this history ends, and fails here. No other fixture in this directory can see that "
            "mistake: the longest history among them is twelve plies."
        ),
    }

    sp = Position.from_fen(SHORT_START)
    assert not sp.in_check()
    assert SHORT_MOVES[0] in sp.legal_moves()
    assert not sp.is_capture(SHORT_MOVES[0])
    sq = sp.push(SHORT_MOVES[0])
    print("short final:", sq.fen(), "in_check", sq.in_check(), "legal", len(sq.legal_moves()))

    cnt2 = {
        "id": "mx-cnt-002",
        "title": "A soldier move does not reset FEN field 5 and does not end the game at 100 plies",
        "area": "cnt",
        "variant": "minixiangqi",
        "start_fen": SHORT_START,
        "moves": SHORT_MOVES,
        "assertions": {
            "in_check": False,
            "result_fen": sq.fen(),
            "legal_moves": None,
            "rejected_moves": None,
            "applied": None,
            "game_state": {"state": "ongoing", "reason": None},
        },
        "boundary": None,
        "rationale": (
            "FEN field 5 counts plies since the last capture and drives no rule, and a soldier move "
            "does not reset it. The record enters with 99 plies since the last capture; the soldier "
            "advance carries the count to 100 rather than clearing it, and the game is still "
            "ongoing. This pins the same absent move-count draw as mx-cnt-001 at the exact ply the "
            "inherited nMoveRule = 50 would fire, on a record loaded with its counter already set "
            "rather than replayed from the opening."
        ),
    }

    for fx in (cnt1, cnt2):
        path = OUT / f"{fx['id']}.json"
        path.write_text(json.dumps(fx, indent=2) + "\n")
        print("wrote", path)


if __name__ == "__main__":
    main()
