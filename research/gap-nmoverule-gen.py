#!/usr/bin/env python3
"""Search for a 100-ply capture-free Mini Xiangqi game with no repeated position.

Workspace-only research tooling for the nMoveRule fixture gap. Uses the
independent contract implementation in gap_nmoverule_rules.py; the engine is
not consulted here.

The game is built as a mirror game: Black answers every Red move with its
reflection through the horizontal axis (rank r <-> rank 8-r, file unchanged),
which is the symmetry of the starting position. That makes the whole history
describable in one sentence and reviewable by checking Red's 50 moves only.

Constraints enforced at every ply:
  * no capture (so FEN field 5 never resets and reaches 100),
  * no check given (so no perpetual-check question can arise),
  * every position (placement + side to move) occurs at most once (so no
    repetition claim exists at any point in the history),
  * the side to move always has a legal move.
"""
import random
import sys

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from gap_nmoverule_rules import Position, START_FEN, name_sq, sq_name

PLIES = int(sys.argv[1]) if len(sys.argv) > 1 else 100
SEED = int(sys.argv[2]) if len(sys.argv) > 2 else 20260728


def mirror(uci):
    (f1, r1), (f2, r2) = name_sq(uci[:2]), name_sq(uci[2:])
    return sq_name(f1, 6 - r1) + sq_name(f2, 6 - r2)


def gives_check(pos_after):
    """pos_after.stm is the side that just received the move."""
    return pos_after.in_check()


def search(rng, budget):
    start = Position.from_fen(START_FEN)
    seen = {start.key()}
    moves = []

    def rec(p, depth):
        nonlocal budget
        if len(moves) >= PLIES:
            return p
        if budget <= 0:
            return None
        cands = [m for m in p.legal_moves() if not p.is_capture(m)]
        rng.shuffle(cands)
        for m in cands:
            budget -= 1
            if budget <= 0:
                return None
            p1 = p.push(m)
            if gives_check(p1) or p1.key() in seen:
                continue
            mm = mirror(m)
            if mm not in p1.legal_moves() or p1.is_capture(mm):
                continue
            p2 = p1.push(mm)
            if gives_check(p2) or p2.key() in seen:
                continue
            if not p2.legal_moves():
                continue
            seen.add(p1.key())
            seen.add(p2.key())
            moves.append(m)
            moves.append(mm)
            got = rec(p2, depth + 1)
            if got is not None:
                return got
            moves.pop()
            moves.pop()
            seen.discard(p1.key())
            seen.discard(p2.key())
        return None

    final = rec(start, 0)
    return moves, final


def main():
    rng = random.Random(SEED)
    moves, final = search(rng, 4_000_000)
    if final is None:
        print("no game found")
        return 1
    assert len(moves) == PLIES
    print("moves:", " ".join(moves))
    print("final:", final.fen())
    print("in_check:", final.in_check())
    print("legal moves at final:", len(final.legal_moves()))
    # independent re-verification from scratch
    p = Position.from_fen(START_FEN)
    seen = {}
    seen[p.key()] = 1
    for i, m in enumerate(moves):
        assert m in p.legal_moves(), (i, m)
        assert not p.is_capture(m), (i, m)
        p = p.push(m)
        assert not p.in_check(), (i, m)
        seen[p.key()] = seen.get(p.key(), 0) + 1
    assert p.fen() == final.fen()
    assert max(seen.values()) == 1, "a position repeats"
    print("verified: %d plies, no capture, no check, max position count %d"
          % (len(moves), max(seen.values())))
    print("halfmove clock:", p.halfmove)
    import json
    print(json.dumps(moves))
    return 0


if __name__ == "__main__":
    sys.exit(main())
