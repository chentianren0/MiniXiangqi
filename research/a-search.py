"""Agent-A scratch search: 4-ply cycles with prescribed check patterns."""
import random, sys, time

FILES = "abcdefg"
WP = [f+r for f in "cde" for r in "123"]
BP = [f+r for f in "cde" for r in "567"]
ALL = [f+r for f in FILES for r in "1234567"]

def to_fen(pieces, stm="w"):
    rows = []
    for r in range(7, 0, -1):
        row, gap = "", 0
        for f in FILES:
            p = pieces.get(f+str(r))
            if p is None:
                gap += 1
            else:
                if gap: row += str(gap); gap = 0
                row += p
        if gap: row += str(gap)
        rows.append(row)
    return "/".join(rows) + f" {stm} - - 0 1"

def key(variant, fen, moves):
    f = get_fen(variant, fen, list(moves)).split()
    return f[0] + " " + f[1]

def gen(nw, nb, wset, bset):
    pieces = {}
    wk = random.choice(WP); bk = random.choice(BP)
    pieces[wk] = "K"; pieces[bk] = "k"
    free = [s for s in ALL if s not in pieces]
    random.shuffle(free)
    i = 0
    for _ in range(nw):
        pieces[free[i]] = random.choice(wset); i += 1
    for _ in range(nb):
        pieces[free[i]] = random.choice(bset); i += 1
    return pieces

def cycles(variant, fen, want, depth=4):
    """want[i] = True/False/None: required gives_check after ply i+1."""
    k0 = key(variant, fen, [])
    out = []
    def rec(moves):
        d = len(moves)
        if d == depth:
            if key(variant, fen, moves) == k0:
                out.append(list(moves))
            return
        for m in legal_moves(variant, fen, list(moves)):
            nm = moves + [m]
            w = want[d]
            if w is not None and gives_check(variant, fen, nm) != w:
                continue
            rec(nm)
    rec([])
    return out
