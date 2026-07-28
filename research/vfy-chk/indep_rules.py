"""Independent Mini Xiangqi rules model, written from docs/xiangqi-rules.md only.
7x7, files a-g (0-6), ranks 1-7 (0-6). No river, no advisors/elephants.
"""

FILES = "abcdefg"

def sq(s):  # 'd5' -> (file,rank) 0-based
    return (FILES.index(s[0]), int(s[1]) - 1)

def name(f, r):
    return FILES[f] + str(r + 1)

def parse_fen(fen):
    parts = fen.split()
    assert len(parts) == 6, parts
    rows = parts[0].split("/")
    assert len(rows) == 7, rows
    board = {}
    for i, row in enumerate(rows):
        rank = 6 - i          # rank 7 first
        f = 0
        for ch in row:
            if ch.isdigit():
                f += int(ch)
            else:
                board[(f, rank)] = ch
                f += 1
        assert f == 7, (row, f)
    return board, parts[1], int(parts[4]), int(parts[5])

def make_fen(board, stm, half, full):
    rows = []
    for rank in range(6, -1, -1):
        row, empty = "", 0
        for f in range(7):
            p = board.get((f, rank))
            if p is None:
                empty += 1
            else:
                if empty: row += str(empty); empty = 0
                row += p
        if empty: row += str(empty)
        rows.append(row)
    return "/".join(rows) + f" {stm} - - {half} {full}"

def is_red(p): return p.isupper()
def side_of(p): return "w" if p.isupper() else "b"

PALACE = {"w": {(f, r) for f in (2,3,4) for r in (0,1,2)},
          "b": {(f, r) for f in (2,3,4) for r in (4,5,6)}}

def in_board(f, r): return 0 <= f < 7 and 0 <= r < 7

def pseudo_moves(board, side):
    """All pseudo-legal moves (ignoring king safety) for `side`."""
    out = []
    for (f, r), p in list(board.items()):
        if side_of(p) != side: continue
        k = p.lower()
        if k == "k":
            for df, dr in ((1,0),(-1,0),(0,1),(0,-1)):
                t = (f+df, r+dr)
                if in_board(*t) and t in PALACE[side]:
                    q = board.get(t)
                    if q is None or side_of(q) != side:
                        out.append(((f,r), t))
        elif k == "r":
            for df, dr in ((1,0),(-1,0),(0,1),(0,-1)):
                nf, nr = f+df, r+dr
                while in_board(nf, nr):
                    q = board.get((nf, nr))
                    if q is None:
                        out.append(((f,r),(nf,nr)))
                    else:
                        if side_of(q) != side: out.append(((f,r),(nf,nr)))
                        break
                    nf, nr = nf+df, nr+dr
        elif k == "n":
            # xiangqi horse: (1,2)/(2,1); leg is the orthogonal FIRST step and must be empty
            for df, dr in ((1,2),(1,-2),(-1,2),(-1,-2),(2,1),(2,-1),(-2,1),(-2,-1)):
                t = (f+df, r+dr)
                if not in_board(*t): continue
                leg = (f + (df//2 if abs(df) == 2 else 0), r + (dr//2 if abs(dr) == 2 else 0))
                if board.get(leg) is not None: continue
                q = board.get(t)
                if q is None or side_of(q) != side:
                    out.append(((f,r), t))
        elif k == "c":
            for df, dr in ((1,0),(-1,0),(0,1),(0,-1)):
                nf, nr = f+df, r+dr
                screens = 0
                while in_board(nf, nr):
                    q = board.get((nf, nr))
                    if q is None:
                        if screens == 0: out.append(((f,r),(nf,nr)))
                    else:
                        screens += 1
                        if screens == 2:
                            if side_of(q) != side: out.append(((f,r),(nf,nr)))
                            break
                    nf, nr = nf+df, nr+dr
        elif k == "p":
            dr = 1 if side == "w" else -1
            for df, drr in ((0, dr), (1, 0), (-1, 0)):
                t = (f+df, r+drr)
                if in_board(*t):
                    q = board.get(t)
                    if q is None or side_of(q) != side:
                        out.append(((f,r), t))
    return out

def king_sq(board, side):
    want = "K" if side == "w" else "k"
    for s, p in board.items():
        if p == want: return s
    return None

def kings_face(board):
    a, b = king_sq(board, "w"), king_sq(board, "b")
    if a is None or b is None or a[0] != b[0]: return False
    lo, hi = sorted((a[1], b[1]))
    return all(board.get((a[0], r)) is None for r in range(lo+1, hi))

def in_check(board, side):
    if kings_face(board): return True
    ks = king_sq(board, side)
    opp = "b" if side == "w" else "w"
    return any(t == ks for _, t in pseudo_moves(board, opp))

def apply_move(board, mv):
    b = dict(board)
    src, dst = mv
    b[dst] = b.pop(src)
    return b

def legal_moves(board, side):
    out = []
    for mv in pseudo_moves(board, side):
        if not in_check(apply_move(board, mv), side):
            out.append(name(*mv[0]) + name(*mv[1]))
    return sorted(out)

def attacks(board, side):
    """squares attacked by `side` (pseudo, i.e. ignoring self-check)."""
    return {t for _, t in pseudo_moves(board, side)}

def step(state, mvstr):
    board, stm, half, full = state
    src, dst = sq(mvstr[:2]), sq(mvstr[2:])
    assert board.get(src) is not None and side_of(board[src]) == stm, (mvstr, stm)
    cap = dst in board
    nb = apply_move(board, (src, dst))
    nstm = "b" if stm == "w" else "w"
    nhalf = 0 if cap else half + 1
    nfull = full + (1 if stm == "b" else 0)
    return (nb, nstm, nhalf, nfull)
