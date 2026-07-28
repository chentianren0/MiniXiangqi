#!/usr/bin/env python3
"""Verifier-owned Mini Xiangqi rules implementation.

Written from MiniXiangqi/docs/xiangqi-rules.md alone, without reading the
builder's gap_nmoverule_rules.py and without consulting pyffish. Used to check
the mx-cnt-* fixtures against the contract rather than against the engine.
"""

FILES = "abcdefg"
NF = 7
NR = 7

# palace: red files c-e ranks 1-3; black files c-e ranks 5-7   (0-indexed)
RED_PALACE = {(f, r) for f in (2, 3, 4) for r in (0, 1, 2)}
BLACK_PALACE = {(f, r) for f in (2, 3, 4) for r in (4, 5, 6)}


def sq(name):
    return (FILES.index(name[0]), int(name[1]) - 1)


def name(s):
    return FILES[s[0]] + str(s[1] + 1)


class Pos:
    __slots__ = ("bd", "stm", "half", "full")

    def __init__(self, bd, stm, half, full):
        self.bd = bd            # dict (file, rank) -> char
        self.stm = stm          # 'w' or 'b'
        self.half = half        # FEN field 5
        self.full = full        # FEN field 6

    @staticmethod
    def from_fen(fen):
        parts = fen.split()
        placement, stm, third, fourth, half, full = parts
        assert third == "-" and fourth == "-", "fields 3 and 4 are always '-'"
        rows = placement.split("/")
        assert len(rows) == NR
        bd = {}
        for i, row in enumerate(rows):
            r = NR - 1 - i          # first row is rank 7
            f = 0
            for ch in row:
                if ch.isdigit():
                    f += int(ch)
                else:
                    bd[(f, r)] = ch
                    f += 1
            assert f == NF, f"row {row!r} does not fill {NF} files"
        return Pos(bd, stm, int(half), int(full))

    def fen(self):
        rows = []
        for r in range(NR - 1, -1, -1):
            row, empty = "", 0
            for f in range(NF):
                p = self.bd.get((f, r))
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
        return f"{'/'.join(rows)} {self.stm} - - {self.half} {self.full}"

    def key(self):
        """Position identity: placement and side to move only (contract)."""
        return (self.fen().split()[0], self.stm)

    def copy(self):
        return Pos(dict(self.bd), self.stm, self.half, self.full)


def color_of(piece):
    return "w" if piece.isupper() else "b"


def on_board(f, r):
    return 0 <= f < NF and 0 <= r < NR


def _slide_targets(bd, s, color, cannon):
    """Chariot moves, or (for cannon=True) cannon quiet moves plus screen captures."""
    out = []
    for df, dr in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        f, r = s
        screens = 0
        while True:
            f += df
            r += dr
            if not on_board(f, r):
                break
            occ = bd.get((f, r))
            if not cannon:
                if occ is None:
                    out.append((f, r))
                else:
                    if color_of(occ) != color:
                        out.append((f, r))
                    break
            else:
                if screens == 0:
                    if occ is None:
                        out.append((f, r))
                    else:
                        screens = 1
                else:
                    if occ is not None:
                        if color_of(occ) != color:
                            out.append((f, r))
                        break
    return out


def piece_targets(bd, s, piece):
    """Pseudo-legal destinations (no own-king-safety filter)."""
    color = color_of(piece)
    up = piece.upper()
    out = []
    if up == "R":
        out = _slide_targets(bd, s, color, cannon=False)
    elif up == "C":
        out = _slide_targets(bd, s, color, cannon=True)
    elif up == "N":
        f, r = s
        # one orthogonal step (the leg), then one diagonal step outward
        for df, dr in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            leg = (f + df, r + dr)
            if not on_board(*leg) or bd.get(leg) is not None:
                continue
            if df:
                cands = [(f + 2 * df, r + 1), (f + 2 * df, r - 1)]
            else:
                cands = [(f + 1, r + 2 * dr), (f - 1, r + 2 * dr)]
            for c in cands:
                if on_board(*c):
                    occ = bd.get(c)
                    if occ is None or color_of(occ) != color:
                        out.append(c)
    elif up == "K":
        f, r = s
        palace = RED_PALACE if color == "w" else BLACK_PALACE
        for df, dr in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            c = (f + df, r + dr)
            if on_board(*c) and c in palace:
                occ = bd.get(c)
                if occ is None or color_of(occ) != color:
                    out.append(c)
    elif up == "P":
        f, r = s
        fwd = 1 if color == "w" else -1
        for c in ((f, r + fwd), (f + 1, r), (f - 1, r)):
            if on_board(*c):
                occ = bd.get(c)
                if occ is None or color_of(occ) != color:
                    out.append(c)
    else:
        raise ValueError(piece)
    return out


def king_square(bd, color):
    for s, p in bd.items():
        if p.upper() == "K" and color_of(p) == color:
            return s
    return None


def kings_face(bd):
    wk, bk = king_square(bd, "w"), king_square(bd, "b")
    if wk is None or bk is None:
        return False
    if wk[0] != bk[0]:
        return False
    lo, hi = sorted((wk[1], bk[1]))
    return all(bd.get((wk[0], r)) is None for r in range(lo + 1, hi))


def is_attacked(bd, target, by_color):
    """Is `target` attacked by side `by_color`? Kings attack through an empty file."""
    for s, p in bd.items():
        if color_of(p) != by_color:
            continue
        if p.upper() == "K":
            continue  # king attacks handled by wazir steps below plus flying general
        if target in piece_targets(bd, s, p):
            return True
    ks = king_square(bd, by_color)
    if ks is not None:
        if target in piece_targets(bd, ks, bd[ks]):
            return True
    return False


def in_check(pos, color=None):
    color = color or pos.stm
    ks = king_square(pos.bd, color)
    if ks is None:
        return False
    if kings_face(pos.bd):
        return True
    return is_attacked(pos.bd, ks, "b" if color == "w" else "w")


def legal_moves(pos):
    out = []
    for s, p in list(pos.bd.items()):
        if color_of(p) != pos.stm:
            continue
        for t in piece_targets(pos.bd, s, p):
            nxt = apply_raw(pos, s, t)
            if in_check(nxt, pos.stm):
                continue
            out.append(name(s) + name(t))
    return sorted(out)


def apply_raw(pos, s, t):
    n = pos.copy()
    piece = n.bd.pop(s)
    captured = n.bd.get(t) is not None
    n.bd[t] = piece
    n.half = 0 if captured else pos.half + 1
    n.full = pos.full + (1 if pos.stm == "b" else 0)
    n.stm = "b" if pos.stm == "w" else "w"
    return n


def apply_move(pos, mv, check_legal=True):
    s, t = sq(mv[:2]), sq(mv[2:])
    if check_legal and mv not in legal_moves(pos):
        raise ValueError(f"illegal move {mv} in {pos.fen()}")
    captured = pos.bd.get(t) is not None
    return apply_raw(pos, s, t), captured
