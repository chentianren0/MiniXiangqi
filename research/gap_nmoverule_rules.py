#!/usr/bin/env python3
"""Independent Mini Xiangqi move generator written from docs/xiangqi-rules.md.

Workspace-only research tooling. This exists so that the nMoveRule fixture's
move history and expected FEN are derived from the accepted rules contract
rather than read back out of Fairy-Stockfish. The engine is then compared
against this, not consulted to build it.

Contract clauses implemented (docs/xiangqi-rules.md, "Board and pieces",
"Starting position, coordinates, and notation", "Movement"):

  * 7x7 board, files a-g from Red's left, ranks 1-7; FEN lists rank 7 first.
  * King: one square orthogonally, confined to its 3x3 palace
    (Red c1-e3, Black c5-e7).
  * The two kings may not face each other on an otherwise empty file; they
    attack each other through that file.
  * Chariot: any number of unobstructed orthogonal squares.
  * Horse: Xiangqi horse move, blocked when its orthogonal first step is
    occupied.
  * Cannon: chariot move when not capturing; capture needs exactly one screen.
  * Soldier: one square forward or one square sideways, moving and capturing,
    from the start of the game.
  * A move is illegal if it leaves the mover's own king attacked.
  * FEN field 5 counts plies since the last capture; a soldier move does not
    reset it. Field 6 is the fullmove number, incremented after Black's move.
"""

FILES = "abcdefg"
RANKS = "1234567"
N = 7

START_FEN = "rcnkncr/p1ppp1p/7/7/7/P1PPP1P/RCNKNCR w - - 0 1"


def sq_name(f, r):
    return FILES[f] + RANKS[r]


def name_sq(s):
    return FILES.index(s[0]), RANKS.index(s[1])


def in_board(f, r):
    return 0 <= f < N and 0 <= r < N


def in_palace(f, r, red):
    if not (2 <= f <= 4):
        return False
    return (0 <= r <= 2) if red else (4 <= r <= 6)


class Position:
    __slots__ = ("board", "stm", "halfmove", "fullmove")

    def __init__(self, board, stm, halfmove, fullmove):
        self.board = board          # dict (f, r) -> piece char
        self.stm = stm              # 'w' (Red) or 'b' (Black)
        self.halfmove = halfmove
        self.fullmove = fullmove

    # ---------- FEN ----------
    @staticmethod
    def from_fen(fen):
        placement, stm, _c, _e, hm, fm = fen.split()
        board = {}
        for i, row in enumerate(placement.split("/")):
            r = 6 - i                      # first row of the FEN is rank 7
            f = 0
            for ch in row:
                if ch.isdigit():
                    f += int(ch)
                else:
                    board[(f, r)] = ch
                    f += 1
            assert f == N, f"bad FEN rank {row!r}"
        return Position(board, stm, int(hm), int(fm))

    def fen(self):
        rows = []
        for r in range(6, -1, -1):
            row, empty = "", 0
            for f in range(N):
                pc = self.board.get((f, r))
                if pc is None:
                    empty += 1
                else:
                    if empty:
                        row += str(empty)
                        empty = 0
                    row += pc
            if empty:
                row += str(empty)
            rows.append(row)
        return f"{'/'.join(rows)} {self.stm} - - {self.halfmove} {self.fullmove}"

    def copy(self):
        return Position(dict(self.board), self.stm, self.halfmove, self.fullmove)

    def key(self):
        """Position identity per the contract: placement and side to move only."""
        return (tuple(sorted(self.board.items())), self.stm)

    # ---------- helpers ----------
    def is_red(self, pc):
        return pc.isupper()

    def own(self, pc):
        return pc.isupper() == (self.stm == "w")

    def king_sq(self, red):
        want = "K" if red else "k"
        for s, pc in self.board.items():
            if pc == want:
                return s
        return None

    # ---------- pseudo-legal move generation for one piece ----------
    def piece_moves(self, frm, quiet_and_captures=True):
        """Squares this piece may move to, ignoring king safety."""
        f, r = frm
        pc = self.board[frm]
        red = pc.isupper()
        kind = pc.upper()
        out = []

        def enemy(sq):
            t = self.board.get(sq)
            return t is not None and t.isupper() != red

        def free(sq):
            return sq not in self.board

        if kind == "K":
            for df, dr in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nf, nr = f + df, r + dr
                if in_board(nf, nr) and in_palace(nf, nr, red):
                    if free((nf, nr)) or enemy((nf, nr)):
                        out.append((nf, nr))
            # flying generals: the kings attack each other through an empty file
            ok = self.king_sq(not red)
            if ok and ok[0] == f:
                lo, hi = sorted((r, ok[1]))
                if all((f, rr) not in self.board for rr in range(lo + 1, hi)):
                    out.append(ok)

        elif kind == "R":
            for df, dr in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nf, nr = f + df, r + dr
                while in_board(nf, nr):
                    if free((nf, nr)):
                        out.append((nf, nr))
                    else:
                        if enemy((nf, nr)):
                            out.append((nf, nr))
                        break
                    nf, nr = nf + df, nr + dr

        elif kind == "N":
            # first step is the orthogonal step; it must be empty
            for sf, sr in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                lf, lr = f + sf, r + sr
                if not in_board(lf, lr) or (lf, lr) in self.board:
                    continue
                # the two destinations reached by stepping diagonally outward
                if sf:  # horizontal first step -> then diagonal up/down
                    cand = [(lf + sf, lr + 1), (lf + sf, lr - 1)]
                else:   # vertical first step -> then diagonal left/right
                    cand = [(lf + 1, lr + sr), (lf - 1, lr + sr)]
                for nf, nr in cand:
                    if in_board(nf, nr) and (free((nf, nr)) or enemy((nf, nr))):
                        out.append((nf, nr))

        elif kind == "C":
            for df, dr in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nf, nr = f + df, r + dr
                # quiet slides
                while in_board(nf, nr) and free((nf, nr)):
                    out.append((nf, nr))
                    nf, nr = nf + df, nr + dr
                # screen found; the first piece beyond it may be captured
                if in_board(nf, nr):
                    nf, nr = nf + df, nr + dr
                    while in_board(nf, nr) and free((nf, nr)):
                        nf, nr = nf + df, nr + dr
                    if in_board(nf, nr) and enemy((nf, nr)):
                        out.append((nf, nr))

        elif kind == "P":
            fwd = 1 if red else -1
            for df, dr in ((0, fwd), (1, 0), (-1, 0)):
                nf, nr = f + df, r + dr
                if in_board(nf, nr) and (free((nf, nr)) or enemy((nf, nr))):
                    out.append((nf, nr))

        else:
            raise ValueError(f"unknown piece {pc!r}")

        return out

    def attacked_by(self, sq, by_red):
        """Is `sq` attacked by a piece of the given colour?"""
        for frm, pc in list(self.board.items()):
            if pc.isupper() != by_red:
                continue
            if sq in self.piece_moves(frm):
                return True
        return False

    def in_check(self, red=None):
        if red is None:
            red = self.stm == "w"
        ks = self.king_sq(red)
        return ks is not None and self.attacked_by(ks, not red)

    def legal_moves(self):
        out = []
        for frm, pc in list(self.board.items()):
            if not self.own(pc):
                continue
            for to in self.piece_moves(frm):
                nxt = self.apply(frm, to)
                nxt.stm = self.stm          # test the mover's own king
                if not nxt.in_check(self.stm == "w"):
                    out.append(sq_name(*frm) + sq_name(*to))
        return sorted(out)

    def apply(self, frm, to):
        nxt = self.copy()
        captured = nxt.board.pop(to, None)
        nxt.board[to] = nxt.board.pop(frm)
        # FEN field 5: plies since the last capture; a soldier move does not reset it
        nxt.halfmove = 0 if captured else self.halfmove + 1
        if self.stm == "b":
            nxt.fullmove = self.fullmove + 1
        nxt.stm = "b" if self.stm == "w" else "w"
        return nxt

    def push(self, uci):
        frm, to = name_sq(uci[:2]), name_sq(uci[2:])
        assert uci in self.legal_moves(), f"illegal move {uci} in {self.fen()}"
        return self.apply(frm, to)

    def is_capture(self, uci):
        return name_sq(uci[2:]) in self.board


def replay(start_fen, moves):
    p = Position.from_fen(start_fen)
    for m in moves:
        p = p.push(m)
    return p
