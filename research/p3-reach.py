#!/usr/bin/env python3
"""How reachable is the P3 defect with Mini Xiangqi-legal material?

Usage: python3 p3-reach.py <dir-with-pyffish.so> [samples]

Samples random 7x7 positions whose material is a subset of the Mini Xiangqi
starting inventory (<=2 chariots, <=2 horses, <=2 cannons, <=5 soldiers, 1 king
inside its own palace), plays one legal "entry" move, looks for 4-ply cycles
from the resulting position, and classifies the 9-ply vs 10-ply verdicts:

  UNDER  : 9 plies = draw, 10 plies = decisive     (missed violation)
  WRONG  : 9 plies = decisive, 10 plies = draw     (mutual chase reported as a
                                                    unilateral loss - wrong winner)
"""
import random
import sys

sys.path.insert(0, sys.argv[1])
import pyffish as sf  # noqa: E402

N = int(sys.argv[2]) if len(sys.argv) > 2 else 4000
MX = "mxq"
sf.load_variant_config(f"""
[{MX}:minixiangqi]
chasingRule = axf
nMoveRule = 0
promotedSoldiersChaseable = false
""")

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
        return sf.gives_check(MX, " ".join(p), [])
    except Exception:
        return True


def absolute(fen, moves, flag, val):
    if not flag:
        return "ongoing"
    if val == 0:
        return "draw"
    stm_red = sf.get_fen(MX, fen, list(moves)).split()[1] == "w"
    return "red-loses" if ((val < 0) == stm_red) else "black-loses"


def cycles_from(fen, budget=260, need=3):
    out, n = [], 0
    base = fen.split()[0]
    try:
        l1 = sf.legal_moves(MX, fen, [])
    except Exception:
        return out
    for m1 in l1:
        for m2 in sf.legal_moves(MX, fen, [m1]):
            for m3 in sf.legal_moves(MX, fen, [m1, m2]):
                for m4 in sf.legal_moves(MX, fen, [m1, m2, m3]):
                    n += 1
                    if n > budget or len(out) >= need:
                        return out
                    seq = [m1, m2, m3, m4]
                    if sf.get_fen(MX, fen, seq).split()[0] == base:
                        out.append(seq)
    return out


rng = random.Random(4242)
# material choices per side, drawn from the Mini Xiangqi inventory
CHOICES = [["R", "N"], ["R", "C"], ["N", "C"], ["R", "R"], ["C", "C"], ["N", "N"],
           ["R", "N", "C"], ["R", "C", "P"], ["R", "N", "P"], ["R", "R", "C"],
           ["R", "N", "C", "P"], ["R", "C"], ["R", "N"]]

under = wrong = 0
positions = cyclesfound = 0
wrong_examples = []
under_examples = []
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
        if sf.validate_fen(fen, MX) != sf.FEN_OK:
            continue
        if opponent_in_check(fen):
            continue
        entries = sf.legal_moves(MX, fen, [])
    except Exception:
        continue
    if not entries:
        continue
    positions += 1
    rng.shuffle(entries)
    for e in entries[:2]:
        f2 = sf.get_fen(MX, fen, [e])
        for cyc in cycles_from(f2, need=2):
            cyclesfound += 1
            h9 = [e] + cyc * 2
            h10 = h9 + cyc[:1]
            try:
                f9, v9 = sf.is_optional_game_end(MX, fen, h9)
                fa, va = sf.is_optional_game_end(MX, fen, h10)
            except Exception:
                continue
            a9 = absolute(fen, h9, f9, v9)
            aa = absolute(fen, h10, fa, va)
            if a9 == "draw" and aa in ("red-loses", "black-loses"):
                under += 1
                if len(under_examples) < 3:
                    under_examples.append((fen, h9, a9, aa))
            elif a9 in ("red-loses", "black-loses") and aa == "draw":
                wrong += 1
                if len(wrong_examples) < 6:
                    wrong_examples.append((fen, h9, a9, aa))

print(f"build={sys.argv[1]} samples={N} legal-positions={positions} cycles={cyclesfound}")
print(f"  UNDER (9=draw, 10=decisive)   : {under}")
print(f"  WRONG (9=decisive, 10=draw)   : {wrong}")
for tag, ex in (("UNDER", under_examples), ("WRONG", wrong_examples)):
    for fen, h, a9, aa in ex:
        print(f"  {tag}  {fen}  {' '.join(h)}   9ply={a9} 10ply={aa}")
