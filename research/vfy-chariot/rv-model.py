#!/usr/bin/env python3
"""Independent verifier model of Mini Xiangqi legal moves.

Written from MiniXiangqi/docs/xiangqi-rules.md "Movement", "Board and pieces",
"Starting position, coordinates, and notation" and "Ordinary game results" only.
No engine, and deliberately not derived from any other model in this workspace.

Mutation knobs on the chariot let the caller ask whether a fixture discriminates.
"""
import sys

FILES = "abcdefg"          # a..g, index 0..6
RANKS = "1234567"          # 1..7, index 0..6
N = 7

# palace(colour) -> set of squares.  Red c1-e3, Black c5-e7 per the contract.
PALACE = {
    "w": {(f, r) for f in (2, 3, 4) for r in (0, 1, 2)},
    "b": {(f, r) for f in (2, 3, 4) for r in (4, 5, 6)},
}

ORTHO = ((1, 0), (-1, 0), (0, 1), (0, -1))


def sq(f, r):
    return FILES[f] + RANKS[r]


def unsq(s):
    return FILES.index(s[0]), RANKS.index(s[1])


def parse_fen(fen):
    parts = fen.split(" ")
    assert len(parts) == 6, f"FEN must have 6 fields: {fen!r}"
    placement, stm, f3, f4, half, full = parts
    assert f3 == "-" and f4 == "-", f"fields 3 and 4 must be '-': {fen!r}"
    rows = placement.split("/")
    assert len(rows) == N, f"FEN must have 7 ranks: {fen!r}"
    board = {}
    for i, row in enumerate(rows):
        r = N - 1 - i               # first row is rank 7
        f = 0
        for ch in row:
            if ch.isdigit():
                f += int(ch)
            else:
                board[(f, r)] = ch
                f += 1
        assert f == N, f"rank {r+1} does not sum to 7 in {fen!r}"
    return board, stm, int(half), int(full)


def to_fen(board, stm, half, full):
    rows = []
    for r in range(N - 1, -1, -1):
        row, gap = "", 0
        for f in range(N):
            p = board.get((f, r))
            if p is None:
                gap += 1
            else:
                if gap:
                    row += str(gap)
                    gap = 0
                row += p
        if gap:
            row += str(gap)
        rows.append(row)
    return f"{'/'.join(rows)} {stm} - - {half} {full}"


def colour(p):
    return "w" if p.isupper() else "b"


def pseudo_moves(board, stm, mut=()):
    """Pseudo-legal moves (king safety not yet applied)."""
    out = []
    for (f, r), p in list(board.items()):
        if colour(p) != stm:
            continue
        k = p.upper()
        if k == "R":
            out += chariot(board, f, r, stm, mut)
        elif k == "C":
            out += cannon(board, f, r, stm)
        elif k == "N":
            out += horse(board, f, r, stm)
        elif k == "P":
            out += soldier(board, f, r, stm)
        elif k == "K":
            out += king(board, f, r, stm)
        else:
            raise AssertionError(f"unknown piece {p!r}")
    return out


MUT = ()   # global chariot mutation, set by the mutation runner


def chariot(board, f, r, stm, mut=()):
    """A chariot moves any number of unobstructed squares orthogonally."""
    res = []
    mut = tuple(mut) + tuple(MUT)
    dirs = list(ORTHO)
    if "diagonal" in mut:
        dirs += [(1, 1), (1, -1), (-1, 1), (-1, -1)]
    for df, dr in dirs:
        steps = 0
        past = 0
        nf, nr = f + df, r + dr
        while 0 <= nf < N and 0 <= nr < N:
            steps += 1
            if "range3" in mut and steps > 2:
                break
            if "no_edge" in mut and (nf in (0, N - 1) or nr in (0, N - 1)):
                nf, nr = nf + df, nr + dr
                continue
            t = board.get((nf, nr))
            if "late1" in mut and past == 1:
                # buggy chariot: stops one square past the blocker
                if t is None:
                    res.append((sq(f, r), sq(nf, nr)))
                break
            if "cannon_like" in mut:
                if t is None:
                    if past == 0:
                        res.append((sq(f, r), sq(nf, nr)))
                else:
                    if past == 1 and colour(t) != stm:
                        res.append((sq(f, r), sq(nf, nr)))
                    past += 1
                    if past > 1:
                        break
                nf, nr = nf + df, nr + dr
                continue
            if "late1" in mut and t is not None:
                if colour(t) != stm:
                    res.append((sq(f, r), sq(nf, nr)))
                past = 1
                nf, nr = nf + df, nr + dr
                continue
            if t is None:
                res.append((sq(f, r), sq(nf, nr)))
            else:
                enemy = colour(t) != stm
                if "capture_own" in mut:
                    res.append((sq(f, r), sq(nf, nr)))
                elif enemy and "no_capture" not in mut:
                    res.append((sq(f, r), sq(nf, nr)))
                jump = ("jump" in mut
                        or ("jump_own" in mut and not enemy)
                        or ("jump_enemy" in mut and enemy))
                if jump:
                    # buggy chariot: slides straight through this piece
                    nf, nr = nf + df, nr + dr
                    continue
                break
            nf, nr = nf + df, nr + dr
    return res


def cannon(board, f, r, stm):
    """Moves like a chariot when not capturing; a capture needs exactly one screen."""
    res = []
    for df, dr in ORTHO:
        nf, nr = f + df, r + dr
        screens = 0
        while 0 <= nf < N and 0 <= nr < N:
            t = board.get((nf, nr))
            if t is None:
                if screens == 0:
                    res.append((sq(f, r), sq(nf, nr)))
            else:
                if screens == 1 and colour(t) != stm:
                    res.append((sq(f, r), sq(nf, nr)))
                screens += 1
                if screens > 1:
                    break
            nf, nr = nf + df, nr + dr
    return res


def horse(board, f, r, stm):
    """Xiangqi horse: one orthogonal leg, then one diagonal step continuing that
    direction; blocked when the orthogonal first step is occupied."""
    res = []
    for df, dr in ORTHO:
        lf, lr = f + df, r + dr
        if not (0 <= lf < N and 0 <= lr < N):
            continue
        if (lf, lr) in board:
            continue                       # leg blocked
        if df:                             # horizontal leg -> fan out in rank
            dests = ((lf + df, lr + 1), (lf + df, lr - 1))
        else:                              # vertical leg -> fan out in file
            dests = ((lf + 1, lr + dr), (lf - 1, lr + dr))
        for nf, nr in dests:
            if not (0 <= nf < N and 0 <= nr < N):
                continue
            t = board.get((nf, nr))
            if t is None or colour(t) != stm:
                res.append((sq(f, r), sq(nf, nr)))
    return res


def soldier(board, f, r, stm):
    """Moves and captures one square forward or one square sideways, from move one."""
    fwd = 1 if stm == "w" else -1
    res = []
    for df, dr in ((0, fwd), (1, 0), (-1, 0)):
        nf, nr = f + df, r + dr
        if not (0 <= nf < N and 0 <= nr < N):
            continue
        t = board.get((nf, nr))
        if t is None or colour(t) != stm:
            res.append((sq(f, r), sq(nf, nr)))
    return res


def king(board, f, r, stm):
    """One square orthogonally, inside its own palace."""
    res = []
    for df, dr in ORTHO:
        nf, nr = f + df, r + dr
        if (nf, nr) not in PALACE[stm]:
            continue
        t = board.get((nf, nr))
        if t is None or colour(t) != stm:
            res.append((sq(f, r), sq(nf, nr)))
    return res


def find_king(board, side):
    want = "K" if side == "w" else "k"
    for pos, p in board.items():
        if p == want:
            return pos
    raise AssertionError(f"no {side} king on the board")


def attacked(board, target, by):
    """Is `target` attacked by side `by`?  Includes the facing-kings attack."""
    tf, tr = target
    for (f, r), p in board.items():
        if colour(p) != by:
            continue
        k = p.upper()
        if k == "K":
            # kings attack each other through an otherwise empty file
            if f == tf and board.get(target) is not None and board[target].upper() == "K":
                lo, hi = sorted((r, tr))
                if all((f, rr) not in board for rr in range(lo + 1, hi)):
                    return True
            # and a general captures one orthogonal step inside its own palace
            if (sq(f, r), sq(tf, tr)) in king(board, f, r, by):
                return True
            continue
        if k == "R":
            moves = chariot(board, f, r, by)
        elif k == "C":
            moves = cannon(board, f, r, by)
        elif k == "N":
            moves = horse(board, f, r, by)
        elif k == "P":
            moves = soldier(board, f, r, by)
        if (sq(f, r), sq(tf, tr)) in moves:
            return True
    return False


def apply_move(board, stm, half, full, mv):
    src, dst = unsq(mv[:2]), unsq(mv[2:])
    nb = dict(board)
    captured = dst in nb
    nb[dst] = nb.pop(src)
    nhalf = 0 if captured else half + 1
    nfull = full + 1 if stm == "b" else full
    return nb, ("b" if stm == "w" else "w"), nhalf, nfull


def in_check(board, side):
    return attacked(board, find_king(board, side), "b" if side == "w" else "w")


def legal_moves(fen, mut=()):
    board, stm, half, full = parse_fen(fen)
    out = []
    for src, dst in pseudo_moves(board, stm, mut):
        nb, _, _, _ = apply_move(board, stm, half, full, src + dst)
        if not in_check(nb, stm):
            out.append(src + dst)
    return sorted(out)


def apply_fen(fen, mv):
    board, stm, half, full = parse_fen(fen)
    nb, nstm, nhalf, nfull = apply_move(board, stm, half, full, mv)
    return to_fen(nb, nstm, nhalf, nfull), in_check(nb, nstm)
