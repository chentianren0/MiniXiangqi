#!/usr/bin/env python3
"""Does the same window asymmetry affect PERPETUAL CHECK?

Usage: python3 p3-chk.py <dir-with-pyffish.so> [samples]

Uses built-in `minixiangqi`, which has perpetualCheckIllegal = true and NO
chasing rule, so chaseThem/chaseUs are identically empty and only the
perpetualThem/perpetualUs pair can decide anything.  If the same one-move-too-wide
window mattered for check, entry-move histories would split by parity here too.
"""
import random
import sys

sys.path.insert(0, sys.argv[1])
import pyffish as sf  # noqa: E402

N = int(sys.argv[2]) if len(sys.argv) > 2 else 4000
V = "minixiangqi"
FILES = "abcdefg"
SQ = [f + str(r) for r in range(1, 8) for f in FILES]
WPAL = [f + str(r) for r in (1, 2, 3) for f in "cde"]
BPAL = [f + str(r) for r in (5, 6, 7) for f in "cde"]


def make_fen(pieces, stm="w"):
    rows = []
    for r in range(7, 0, -1):
        row, empty = "", 0
        for f in FILES:
            p = pieces.get(f + str(r))
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
    return "/".join(rows) + f" {stm} - - 0 1"


def opponent_in_check(fen):
    """A root in which the side NOT to move is in check is an illegal position;
    do_move only sets checkersBB when the move gives check, so such roots produce
    artefacts. Reject them."""
    p = fen.split()
    p[1] = "b" if p[1] == "w" else "w"
    try:
        return sf.gives_check(V, " ".join(p), [])
    except Exception:
        return True


def absolute(fen, moves, flag, val):
    if not flag:
        return "ongoing"
    if val == 0:
        return "draw"
    stm_red = sf.get_fen(V, fen, list(moves)).split()[1] == "w"
    return "red-loses" if ((val < 0) == stm_red) else "black-loses"


def cycles_from(fen, budget=260, need=2):
    out, n = [], 0
    base = fen.split()[0]
    try:
        l1 = sf.legal_moves(V, fen, [])
    except Exception:
        return out
    for m1 in l1:
        for m2 in sf.legal_moves(V, fen, [m1]):
            for m3 in sf.legal_moves(V, fen, [m1, m2]):
                for m4 in sf.legal_moves(V, fen, [m1, m2, m3]):
                    n += 1
                    if n > budget or len(out) >= need:
                        return out
                    seq = [m1, m2, m3, m4]
                    if sf.get_fen(V, fen, seq).split()[0] == base:
                        out.append(seq)
    return out


rng = random.Random(99)
CHOICES = [["R"], ["C"], ["N"], ["R", "N"], ["R", "C"], ["C", "N"], ["R", "R"], ["C", "C"]]
splits = decisive = cyc = 0
examples = []
for it in range(N):
    used = set()
    pieces = {}
    wk = rng.choice(WPAL); pieces[wk] = "K"; used.add(wk)
    bk = rng.choice(BPAL); pieces[bk] = "k"; used.add(bk)
    for t in rng.choice(CHOICES):
        free = [s for s in SQ if s not in used]
        s = rng.choice(free); pieces[s] = t; used.add(s)
    for t in rng.choice(CHOICES):
        free = [s for s in SQ if s not in used]
        s = rng.choice(free); pieces[s] = t.lower(); used.add(s)
    fen = make_fen(pieces)
    try:
        if sf.validate_fen(fen, V) != sf.FEN_OK:
            continue
        if opponent_in_check(fen):
            continue
        entries = sf.legal_moves(V, fen, [])
    except Exception:
        continue
    if not entries:
        continue
    rng.shuffle(entries)
    for e in entries[:2]:
        f2 = sf.get_fen(V, fen, [e])
        for c in cycles_from(f2):
            cyc += 1
            h9 = [e] + c * 2
            h10 = h9 + c[:1]
            try:
                f9, v9 = sf.is_optional_game_end(V, fen, h9)
                fa, va = sf.is_optional_game_end(V, fen, h10)
            except Exception:
                continue
            a9 = absolute(fen, h9, f9, v9)
            aa = absolute(fen, h10, fa, va)
            if a9 != "draw" or aa != "draw":
                decisive += 1
            if a9 != aa and "ongoing" not in (a9, aa):
                splits += 1
                if len(examples) < 5:
                    examples.append((fen, h9, a9, aa))

print(f"build={sys.argv[1]} variant={V} samples={N} cycles={cyc} "
      f"non-draw outcomes={decisive} PARITY SPLITS={splits}")
for fen, h, a9, aa in examples:
    print(f"  SPLIT {fen}  {' '.join(h)}  9ply={a9} 10ply={aa}")
