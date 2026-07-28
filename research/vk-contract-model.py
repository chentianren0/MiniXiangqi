#!/usr/bin/env python3
"""INDEPENDENT VERIFIER scratch: a from-the-contract Mini Xiangqi model for
king+chariot positions, written only from docs/xiangqi-rules.md, plus a
cross-check against a pyffish build.

Implements, straight from the contract prose:
  - 7x7 board, files a..g, ranks 1..7, FEN lists rank 7 first.
  - King: one square orthogonally, inside its palace (Red c1-e3, Black c5-e7).
  - The two kings may not face on an otherwise empty file; they attack each
    other through that file.
  - Chariot: any number of unobstructed orthogonal squares.
  - A move is legal iff the mover's king is not attacked afterwards.
  - Position identity = piece placement + side to move (counters ignored).
  - Halfmove field counts plies since last capture; fullmove increments after
    each Black move.

Workspace-only research scratch; part of no repository.
"""
import sys

FILES = "abcdefg"


def parse(fen):
    placement, stm, _, _, half, full = fen.split()
    board = {}
    rows = placement.split("/")
    assert len(rows) == 7, rows
    for i, row in enumerate(rows):
        rank = 7 - i
        f = 0
        for ch in row:
            if ch.isdigit():
                f += int(ch)
            else:
                board[(f, rank)] = ch
                f += 1
        assert f == 7, (row, f)
    return board, stm, int(half), int(full)


def to_fen(board, stm, half, full):
    rows = []
    for rank in range(7, 0, -1):
        row, empty = "", 0
        for f in range(7):
            p = board.get((f, rank))
            if p is None:
                empty += 1
            else:
                if empty:
                    row += str(empty)
                    empty = 0
                row += p
        if empty:
            row += str(empty)
        rows.append(row)
    return f"{'/'.join(rows)} {stm} - - {half} {full}"


def sq(name):
    return (FILES.index(name[0]), int(name[1]))


def name(s):
    return FILES[s[0]] + str(s[1])


def is_red(p):
    return p.isupper()


def in_palace(s, red):
    f, r = s
    if not (2 <= f <= 4):
        return False
    return (1 <= r <= 3) if red else (5 <= r <= 7)


def pseudo_moves(board, stm):
    """Pseudo-legal moves (king step in palace, chariot slide). No king-safety."""
    red = stm == "w"
    out = []
    for s, p in list(board.items()):
        if is_red(p) != red:
            continue
        u = p.upper()
        if u == "K":
            for df, dr in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                t = (s[0] + df, s[1] + dr)
                if not (0 <= t[0] <= 6 and 1 <= t[1] <= 7):
                    continue
                if not in_palace(t, red):
                    continue
                q = board.get(t)
                if q is not None and is_red(q) == red:
                    continue
                out.append((s, t))
        elif u == "R":
            for df, dr in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                t = (s[0] + df, s[1] + dr)
                while 0 <= t[0] <= 6 and 1 <= t[1] <= 7:
                    q = board.get(t)
                    if q is None:
                        out.append((s, t))
                    else:
                        if is_red(q) != red:
                            out.append((s, t))
                        break
                    t = (t[0] + df, t[1] + dr)
        else:
            raise NotImplementedError(f"piece {p} not modelled")
    return out


def attacked(board, target, by_red):
    """Is `target` attacked by side `by_red`? Chariot lines plus the
    flying-general condition (kings attack each other on an empty file)."""
    for s, p in board.items():
        if is_red(p) != by_red:
            continue
        u = p.upper()
        if u == "R":
            if s[0] == target[0] or s[1] == target[1]:
                if clear_between(board, s, target):
                    return True
        elif u == "K":
            # flying general: a king attacks the other king down an empty file
            if s[0] == target[0] and clear_between(board, s, target):
                tp = board.get(target)
                if tp is not None and tp.upper() == "K":
                    return True
            # ordinary adjacency (a king also guards an adjacent square)
            if abs(s[0] - target[0]) + abs(s[1] - target[1]) == 1:
                return True
    return False


def clear_between(board, a, b):
    if a == b:
        return False
    if a[0] == b[0]:
        lo, hi = sorted((a[1], b[1]))
        return all((a[0], r) not in board for r in range(lo + 1, hi))
    if a[1] == b[1]:
        lo, hi = sorted((a[0], b[0]))
        return all((f, a[1]) not in board for f in range(lo + 1, hi))
    return False


def king_sq(board, red):
    for s, p in board.items():
        if p == ("K" if red else "k"):
            return s
    raise ValueError("no king")


def apply_move(board, stm, half, full, mv):
    s, t = mv
    nb = dict(board)
    captured = t in nb
    nb[t] = nb.pop(s)
    nstm = "b" if stm == "w" else "w"
    nhalf = 0 if captured else half + 1
    nfull = full + (1 if stm == "b" else 0)
    return nb, nstm, nhalf, nfull


def legal_moves(board, stm):
    red = stm == "w"
    out = []
    for mv in pseudo_moves(board, stm):
        nb, _, _, _ = apply_move(board, stm, 0, 1, mv)
        if not attacked(nb, king_sq(nb, red), not red):
            out.append(name(mv[0]) + name(mv[1]))
    return sorted(out)


def in_check(board, stm):
    red = stm == "w"
    return attacked(board, king_sq(board, red), not red)


def replay(start_fen, moves):
    board, stm, half, full = parse(start_fen)
    trace = []
    for i, m in enumerate(moves):
        legal = legal_moves(board, stm)
        ok = m in legal
        trace.append({
            "ply": i,
            "fen": to_fen(board, stm, half, full),
            "stm": stm,
            "in_check": in_check(board, stm),
            "legal": legal,
            "move": m,
            "move_legal": ok,
        })
        if not ok:
            return trace, None
        board, stm, half, full = apply_move(board, stm, half, full, (sq(m[:2]), sq(m[2:])))
    trace.append({
        "ply": len(moves),
        "fen": to_fen(board, stm, half, full),
        "stm": stm,
        "in_check": in_check(board, stm),
        "legal": legal_moves(board, stm),
        "move": None,
        "move_legal": None,
    })
    return trace, to_fen(board, stm, half, full)


def key(fen):
    """Position identity: placement + side to move only."""
    p = fen.split()
    return (p[0], p[1])


def main():
    import json
    import pathlib
    paths = sys.argv[1:]
    for path in paths:
        fx = json.loads(pathlib.Path(path).read_text())
        print("=" * 78)
        print(f"{fx['id']}  {fx['title']}")
        trace, final = replay(fx["start_fen"], fx["moves"])
        counts = {}
        for st in trace:
            k = key(st["fen"])
            counts[k] = counts.get(k, 0) + 1
            st["occurrence"] = counts[k]
        for st in trace:
            print(f"  ply {st['ply']}: {st['fen']:<38} occ={st['occurrence']} "
                  f"check={'T' if st['in_check'] else 'f'} "
                  f"legal={st['legal']} move={st['move']} ok={st['move_legal']}")
        a = fx["assertions"]
        print(f"  MODEL final fen : {final}")
        print(f"  ASSERT result_fen: {a['result_fen']}   MATCH={final == a['result_fen']}")
        print(f"  ASSERT in_check  : {a['in_check']}   MATCH={trace[-1]['in_check'] == a['in_check']}")
        if a["legal_moves"] is not None:
            print(f"  ASSERT legal     : {a['legal_moves']}   MATCH={sorted(a['legal_moves']) == trace[-1]['legal']}")
        occ_final = trace[-1]["occurrence"]
        print(f"  MODEL occurrence of final position: {occ_final}  "
              f"(asserted at_occurrence={a['game_state'].get('at_occurrence')})")
        b = fx.get("boundary")
        if b:
            occ_b = trace[b["prefix_len"]]["occurrence"]
            print(f"  MODEL occurrence at boundary prefix {b['prefix_len']}: {occ_b}")
        # first ply at which any position reaches its third occurrence
        first3 = next((st["ply"] for st in trace if st["occurrence"] == 3), None)
        print(f"  MODEL first ply where ANY position hits occurrence 3: {first3}")
        forced = [st["ply"] for st in trace[:-1] if len(st["legal"]) == 1]
        print(f"  MODEL plies with exactly one legal move: {forced}")
        print(f"  MODEL plies where the side to move is in check: "
              f"{[st['ply'] for st in trace if st['in_check']]}")


if __name__ == "__main__":
    main()
