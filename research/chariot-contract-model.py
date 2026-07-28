#!/usr/bin/env python3
"""An independent Mini Xiangqi legal-move model written ONLY from the contract text
of MiniXiangqi/docs/xiangqi-rules.md (section "Movement" plus king safety).

It exists so that the chariot fixture's expectations are derived from the contract and
then compared against the engine, rather than read off the engine. It is workspace-only
research evidence and is not part of any repository deliverable.

Contract clauses implemented, verbatim in intent:
  - "A king moves one square orthogonally inside its palace."      (palace c1-e3 / c5-e7)
  - "The two kings may not face each other on an otherwise empty file; they attack each
     other through that file."
  - "A chariot moves any number of unobstructed squares orthogonally."
  - "A horse uses Xiangqi horse movement and is blocked when its orthogonal first step is
     occupied."
  - "A cannon moves like a chariot when not capturing. A cannon capture requires exactly
     one intervening screen."
  - "A soldier moves and captures one square forward or one square sideways from the start
     of the game."
  - "Check, legal check evasion, and checkmate must follow the movement and king-safety
     rules above."  -> a move is legal only if it does not leave one's own king attacked.
  - FEN: 7x7, rank 7 first; field 5 = plies since last capture (a soldier move does NOT
     reset it); field 6 = fullmove, incremented after each Black move.
"""

FILES = "abcdefg"
N = 7

def sq(f, r):            # f,r are 0-based
    return FILES[f] + str(r + 1)

def parse_sq(s):
    return FILES.index(s[0]), int(s[1]) - 1

def parse_fen(fen):
    parts = fen.split()
    rows = parts[0].split("/")
    assert len(rows) == N, rows
    board = {}
    for i, row in enumerate(rows):
        r = N - 1 - i          # rows[0] is rank 7
        f = 0
        for ch in row:
            if ch.isdigit():
                f += int(ch)
            else:
                board[(f, r)] = ch
                f += 1
        assert f == N, (row, f)
    return board, parts[1], int(parts[4]), int(parts[5])

def make_fen(board, stm, halfmove, fullmove):
    rows = []
    for r in range(N - 1, -1, -1):
        row, empty = "", 0
        for f in range(N):
            p = board.get((f, r))
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
    return f"{'/'.join(rows)} {stm} - - {halfmove} {fullmove}"

def is_red(p):
    return p.isupper()

def side_of(p):
    return "w" if p.isupper() else "b"

def in_palace(f, r, side):
    if side == "w":
        return 2 <= f <= 4 and 0 <= r <= 2      # c1-e3
    return 2 <= f <= 4 and 4 <= r <= 6          # c5-e7

def on_board(f, r):
    return 0 <= f < N and 0 <= r < N

ORTHO = [(1, 0), (-1, 0), (0, 1), (0, -1)]

def pseudo_moves(board, side):
    """Movement rules only; king safety applied by legal_moves()."""
    out = []
    for (f, r), p in list(board.items()):
        if side_of(p) != side:
            continue
        k = p.upper()
        if k == "K":
            for df, dr in ORTHO:
                nf, nr = f + df, r + dr
                if on_board(nf, nr) and in_palace(nf, nr, side):
                    t = board.get((nf, nr))
                    if t is None or side_of(t) != side:
                        out.append(((f, r), (nf, nr)))
        elif k == "R":
            # any number of unobstructed squares orthogonally
            for df, dr in ORTHO:
                nf, nr = f + df, r + dr
                while on_board(nf, nr):
                    t = board.get((nf, nr))
                    if t is None:
                        out.append(((f, r), (nf, nr)))
                    else:
                        if side_of(t) != side:
                            out.append(((f, r), (nf, nr)))
                        break                    # obstructed: never past a piece
                    nf, nr = nf + df, nr + dr
        elif k == "N":
            for df, dr in ORTHO:                 # the orthogonal first step (the leg)
                lf, lr = f + df, r + dr
                if not on_board(lf, lr) or (lf, lr) in board:
                    continue                     # blocked when the first step is occupied
                perps = [(df, 1), (df, -1)] if dr == 0 else [(1, dr), (-1, dr)]
                for sf_, sr in perps:           # one more step out, then one to the side
                    nf, nr = lf + sf_, lr + sr
                    if not on_board(nf, nr):
                        continue
                    t = board.get((nf, nr))
                    if t is None or side_of(t) != side:
                        out.append(((f, r), (nf, nr)))
        elif k == "C":
            for df, dr in ORTHO:
                nf, nr = f + df, r + dr
                screens = 0
                while on_board(nf, nr):
                    t = board.get((nf, nr))
                    if t is None:
                        if screens == 0:
                            out.append(((f, r), (nf, nr)))   # slides like a chariot
                    else:
                        screens += 1
                        if screens == 2:
                            if side_of(t) != side:
                                out.append(((f, r), (nf, nr)))  # exactly one screen
                            break
                    nf, nr = nf + df, nr + dr
        elif k == "P":
            fwd = 1 if side == "w" else -1
            for df, dr in ((0, fwd), (1, 0), (-1, 0)):
                nf, nr = f + df, r + dr
                if not on_board(nf, nr):
                    continue
                t = board.get((nf, nr))
                if t is None or side_of(t) != side:
                    out.append(((f, r), (nf, nr)))
        else:
            raise AssertionError(f"unknown piece {p}")
    return out

def kings_face(board):
    """The two kings face each other on an otherwise empty file."""
    ks = [(pos, p) for pos, p in board.items() if p.upper() == "K"]
    if len(ks) != 2:
        return False
    (f1, r1), p1 = ks[0]
    (f2, r2), p2 = ks[1]
    if f1 != f2:
        return False
    lo, hi = sorted((r1, r2))
    return all((f1, r) not in board for r in range(lo + 1, hi))

def king_attacked(board, side):
    kpos = next((pos for pos, p in board.items() if p.upper() == "K" and side_of(p) == side), None)
    if kpos is None:
        return False
    if kings_face(board):                 # "they attack each other through that file"
        return True
    other = "b" if side == "w" else "w"
    return any(dst == kpos for _, dst in pseudo_moves(board, other))

def apply_move(board, mv):
    src, dst = mv
    nb = dict(board)
    captured = nb.get(dst) is not None
    nb[dst] = nb.pop(src)
    return nb, captured

def legal_moves(fen):
    board, stm, _, _ = parse_fen(fen)
    out = []
    for mv in pseudo_moves(board, stm):
        nb, _ = apply_move(board, mv)
        if not king_attacked(nb, stm):
            out.append(sq(*mv[0]) + sq(*mv[1]))
    return sorted(out)

def in_check(fen):
    board, stm, _, _ = parse_fen(fen)
    return king_attacked(board, stm)

def push(fen, uci):
    board, stm, half, full = parse_fen(fen)
    mv = (parse_sq(uci[:2]), parse_sq(uci[2:]))
    nb, captured = apply_move(board, mv)
    half = 0 if captured else half + 1     # a soldier move does not reset it
    if stm == "b":
        full += 1
    return make_fen(nb, "b" if stm == "w" else "w", half, full)

def opponent_in_check(fen):
    """Legality guard: the side NOT to move must not be in check."""
    board, stm, _, _ = parse_fen(fen)
    return king_attacked(board, "b" if stm == "w" else "w")
