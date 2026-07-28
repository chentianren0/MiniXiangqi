#!/usr/bin/env python3
"""Does the P3 patch change adjudication for BUILT-IN xiangqi?

Usage: python3 p3-xq.py <dir-with-pyffish.so> [max-entries-per-case]

Takes chase wheels from the fork's own test.py, re-phases each so that the
VIOLATING side is the one that makes the entry move (which is the only shape in
which the defect can bite), enumerates every predecessor position from which a
single legal move of the violating side reaches the wheel start, and adjudicates
the 9-ply and 10-ply histories in an absolute (Red/Black) frame.
"""
import sys

sys.path.insert(0, sys.argv[1])
import pyffish as sf  # noqa: E402

CAP = int(sys.argv[2]) if len(sys.argv) > 2 else 10**9
MATE = 32000
FILES = "abcdefghi"


def parse(fen):
    board, stm = fen.split()[0], fen.split()[1]
    occ = {}
    for i, row in enumerate(board.split("/")):
        rank = 10 - i
        f = 0
        for ch in row:
            if ch.isdigit():
                f += int(ch)
            else:
                occ[FILES[f] + str(rank)] = ch
                f += 1
    return occ, stm


def unparse(occ, stm):
    rows = []
    for rank in range(10, 0, -1):
        line, gap = "", 0
        for f in FILES:
            sq = f + str(rank)
            if sq in occ:
                if gap:
                    line += str(gap)
                    gap = 0
                line += occ[sq]
            else:
                gap += 1
        if gap:
            line += str(gap)
        rows.append(line)
    return "/".join(rows) + f" {stm} - - 0 1"


def board_stm(fen):
    p = fen.split()
    return p[0] + " " + p[1]


def absolute(fen, moves, flag, val):
    """Return 'draw' / 'red-loses' / 'black-loses' / 'ongoing'."""
    if not flag:
        return "ongoing"
    if val == 0:
        return "draw"
    stm_red = sf.get_fen("xiangqi", fen, list(moves)).split()[1] == "w"
    loser_red = (val < 0) == stm_red
    return "red-loses" if loser_red else "black-loses"


def legal_seq(fen, moves):
    for i, m in enumerate(moves):
        if m not in sf.legal_moves("xiangqi", fen, moves[:i]):
            return i
    return None


# (label, start FEN, 4-ply wheel applied from that FEN)
CASES = [
    ("fake protection by cannon", "5k3/9/9/9/9/1C7/1r7/9/1C7/4K4 w - - 0 1",
     ["b5c5", "b4c4", "c5b5", "c4b4"]),
    ("overprotection by king", "3k5/9/9/9/9/9/3r5/9/9/3NK4 w - - 0 1",
     ["d1c3", "d4c4", "c3d1", "c4d4"]),
    ("no overprotection by king (draw)", "3k5/9/9/3n5/9/9/3r5/9/9/3NK4 w - - 0 1",
     ["d1c3", "d4c4", "c3d1", "c4d4"]),
    ("direct chase by cannon (test.py)",
     "2bakabnr/9/r1n1c4/2p1p1p1p/PP7/9/4P1P1P/2C3NC1/9/1NBAKAB1R w - - 0 1",
     ["c3a3", "a8b8", "a3b3", "b8a8"]),
    ("X-ray protected discovered check", "5k3/9/9/9/9/9/9/9/9/3NK1cr1 w - - 0 1",
     ["d1c3", "h1h3", "c3d1", "h3h1"]),
    ("discovered+anti-discovered cannon", "5k3/9/9/5C3/5c3/5C3/9/9/5p3/4K4 w - - 0 1",
     ["f5d5", "f6d6", "d5f5", "d6f6"]),
    ("creating pins to undermine root", "4k4/4c4/9/4p4/9/9/3rn4/3NR4/4K4/9 b - - 0 1",
     ["e4g5", "e2f2", "g5e4", "f2e2"]),
]

print(f"# engine: {sf.info()}  build-dir={sys.argv[1]}")
for label, START, WHEEL in CASES:
    print(f"\n## {label}")
    bad = legal_seq(START, WHEEL * 2)
    if bad is not None:
        print(f"    bare wheel illegal at {bad}")
        continue
    f8, v8 = sf.is_optional_game_end("xiangqi", START, WHEEL * 2)
    verd8 = absolute(START, WHEEL * 2, f8, v8)
    print(f"    bare wheel, 8 plies, history starts at the 1st occurrence: {verd8}")
    if verd8 not in ("red-loses", "black-loses"):
        print("    (no unilateral violator; skipping entry-move enumeration)")
        continue
    violator = "w" if verd8 == "red-loses" else "b"

    # phase the wheel so that stm(X) != violator, i.e. the entry move is the
    # violator's move.
    for p in range(4):
        X = sf.get_fen("xiangqi", START, WHEEL[:p])
        if X.split()[1] != violator:
            wheel = WHEEL[p:] + WHEEL[:p]
            break
    else:
        print("    no suitable phase")
        continue
    if legal_seq(X, wheel * 2) is not None:
        print("    re-phased wheel illegal")
        continue
    print(f"    violator={'Red' if violator == 'w' else 'Black'}  X={X}  wheel={' '.join(wheel)}")

    occ, stm = parse(X)
    movers = [s for s, ch in occ.items()
              if (ch.isupper() if violator == "w" else ch.islower())]
    empties = [f + str(r) for r in range(1, 11) for f in FILES if f + str(r) not in occ]
    target = board_stm(X)
    tried = splits = 0
    shown = 0
    for s in sorted(movers):
        for t in empties:
            if tried >= CAP:
                break
            occ2 = dict(occ)
            del occ2[s]
            occ2[t] = occ[s]
            Y = unparse(occ2, violator)
            mv = t + s
            try:
                if mv not in sf.legal_moves("xiangqi", Y, []):
                    continue
                if board_stm(sf.get_fen("xiangqi", Y, [mv])) != target:
                    continue
            except Exception:
                continue
            tried += 1
            h9 = [mv] + wheel * 2
            h10 = h9 + wheel[:1]
            if legal_seq(Y, h10) is not None:
                continue
            f9, v9 = sf.is_optional_game_end("xiangqi", Y, h9)
            fa, va = sf.is_optional_game_end("xiangqi", Y, h10)
            a9 = absolute(Y, h9, f9, v9)
            aa = absolute(Y, h10, fa, va)
            if a9 != aa:
                splits += 1
                if shown < 8:
                    shown += 1
                    print(f"    SPLIT  Y={Y:<44} E={mv:<5} 9ply={a9:<12} 10ply={aa}")
            elif shown < 3:
                shown += 1
                print(f"    ok     Y={Y:<44} E={mv:<5} 9ply={a9:<12} 10ply={aa}")
    print(f"    -> {tried} entry moves tried, {splits} parity split(s)")
