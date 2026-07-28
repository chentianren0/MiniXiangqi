#!/usr/bin/env python3
"""P3 (chase-window parity) investigation probe.

Usage: python3 p3-probe.py <dir-containing-pyffish.so>

Deterministic; prints one line per probe so two builds can be diffed.
"""
import sys

sys.path.insert(0, sys.argv[1])
import pyffish as sf  # noqa: E402

MATE = 32000
MX = "mxq"
INI = f"""
[{MX}:minixiangqi]
chasingRule = axf
nMoveRule = 0
promotedSoldiersChaseable = false
"""
sf.load_variant_config(INI)


def legalcheck(variant, fen, moves):
    for i, m in enumerate(moves):
        if m not in sf.legal_moves(variant, fen, list(moves[:i])):
            return i, m
    return None, None


def loser(variant, fen, moves, val):
    if val is None or val == 0:
        return "-"
    stm_red = sf.get_fen(variant, fen, list(moves)).split()[1] == "w"
    if val < 0:
        return "Red" if stm_red else "Black"
    return "Black" if stm_red else "Red"


def verdict(flag, val):
    if not flag:
        return "ongoing"
    if val == 0:
        return "DRAW"
    if val >= MATE - 200:
        return "STM-WINS"
    if val <= -MATE + 200:
        return "STM-LOSES"
    return f"val={val}"


def probe(name, fen, moves, variant=MX, note=""):
    bad, m = legalcheck(variant, fen, moves)
    if bad is not None:
        print(f"{name:<34} ILLEGAL at index {bad} ({m})")
        return None
    flag, val = sf.is_optional_game_end(variant, fen, list(moves))
    v = val if flag else None
    print(f"{name:<34} plies={len(moves):<3} ({flag},{v}) {verdict(flag, v):<10} "
          f"loser={loser(variant, fen, moves, v):<6} {note}")
    return (flag, v)


print(f"# engine: {sf.info()}  build-dir={sys.argv[1]}")
print()

# ---------------------------------------------------------------- section 1
print("## 1. Reconciliation fixtures mx-chs-030 / 031 / 032 (Mini Xiangqi target variant)")
WHEEL = ["a5b5", "a3b3", "b5a5", "b3a3"]
F030 = "4k2/7/c6/7/7/7/R1K4 w - - 0 1"
F031 = "4k2/7/c6/7/1R5/7/2K4 w - - 0 1"
probe("mx-chs-030 (quiet entry a1a3, 9)", F030, ["a1a3"] + WHEEL * 2,
      note="expected by contract: Red loses")
probe("mx-chs-030 boundary (5 plies)", F030, ["a1a3"] + WHEEL)
probe("mx-chs-031 (chasing entry b3a3, 9)", F031, ["b3a3"] + WHEEL * 2,
      note="control: entry move is itself a chase")
probe("mx-chs-032 (030 + one more, 10)", F030, ["a1a3"] + WHEEL * 2 + ["a5b5"],
      note="same four judged White moves, other parity")
probe("mx-chs-001 (no entry move, 8)", F031, ["b3a3", "a5b5", "a3b3", "b5a5"] * 2,
      note="approved fixture; history starts at 1st occurrence")
print()

# quiet-entry variants at even lengths, to show the parity flip is systematic
print("## 1b. The same quiet-entry wheel measured at every ply from 9 to 13")
for n in range(9, 14):
    seq = (["a1a3"] + WHEEL * 3)[:n]
    probe(f"quiet entry, {n} plies", F030, seq)
print()

# ---------------------------------------------------------------- section 2
print("## 2. Perpetual CHECK with an entry move (does the same parity split exist?)")
# mx-chk-001 wheel run from a position entered by a White move.
# Any move that CREATES a position in which the opponent is in check is itself a
# check, so the analogue of a 'quiet entry' cannot exist for perpetual check.
FCHK_Y = "3k3/7/7/2R4/7/7/4K2 w - - 0 1"     # Black king d7 NOT in check here
CW = ["d7c7", "d4c4", "c7d7", "c4d4"]
probe("mx-chk-001 (no entry, 8)", "3k3/7/7/3R3/7/7/4K2 b - - 0 1", CW * 2)
probe("check wheel + entry c4d4 (9)", FCHK_Y, ["c4d4"] + CW * 2, note="entry is necessarily a check")
probe("check wheel + entry c4d4 (10)", FCHK_Y, ["c4d4"] + CW * 2 + ["d7c7"], note="other parity")
# Attempt an entry that is NOT a check: it requires a predecessor in which the
# opponent is already in check with the chaser to move, i.e. an illegal position.
probe("illegal 'quiet entry' attempt", "3k3/7/7/3R3/7/7/3K3 w - - 0 1", ["d1e1"] + CW * 2,
      note="expected: rejected, the predecessor leaves Black in check")
print()

# ---------------------------------------------------------------- section 3
print("## 3. Mutual perpetual chase (mx-mix-002) and the wrong-winner corner")
MIX = "2k2r1/7/1cN1R2/7/2r1nC1/7/1R2K2 w - - 0 1"
MIXW = ["c5b3", "e3f5", "b3c5", "f5e3"]
probe("mx-mix-002 (no entry, 8)", MIX, MIXW * 2, note="expected: mutual chase -> DRAW")
probe("mx-chs-033 White half alone", "2k4/7/1cN1R2/7/4n2/7/1R2K2 w - - 0 1", MIXW * 2)
probe("mx-chs-034 Black half alone", "2k2r1/7/2N4/7/2r1nC1/7/4K2 w - - 0 1", MIXW * 2)

# X = position after mx-mix-002's first move, Black to move; the same wheel runs from X.
X = "2k2r1/7/1c2R2/7/1Nr1nC1/7/1R2K2 b - - 0 1"
XW = ["e3f5", "b3c5", "f5e3", "c5b3"]
probe("mutual wheel from X (no entry, 8)", X, XW * 2, note="control: same mutual chase, Black first")
print()

print("### enumerate quiet White entry moves E with E: Y -> X, then run [E] + wheel x2")


def board_stm(fen):
    p = fen.split()
    return p[0] + " " + p[1]


target = board_stm(X)
rows = X.split()[0].split("/")
occupied = {}
for i, r in enumerate(rows):
    f = 0
    for ch in r:
        if ch.isdigit():
            f += int(ch)
        else:
            occupied[chr(ord("a") + f) + str(7 - i)] = ch
            f += 1
empties = [chr(ord("a") + f) + str(rk) for rk in range(1, 8) for f in range(7)
           if chr(ord("a") + f) + str(rk) not in occupied]
whites = [s for s, ch in occupied.items() if ch.isupper()]

found = []
for s in whites:
    for t in empties:
        # Y: the same position with the white piece on t instead of s, White to move
        occ2 = dict(occupied)
        del occ2[s]
        occ2[t] = occupied[s]
        rowstr = []
        for rk in range(7, 0, -1):
            line, gap = "", 0
            for fi in range(7):
                sq = chr(ord("a") + fi) + str(rk)
                if sq in occ2:
                    if gap:
                        line += str(gap)
                        gap = 0
                    line += occ2[sq]
                else:
                    gap += 1
            if gap:
                line += str(gap)
            rowstr.append(line)
        Y = "/".join(rowstr) + " w - - 0 1"
        mv = t + s
        try:
            if mv not in sf.legal_moves(MX, Y, []):
                continue
            if board_stm(sf.get_fen(MX, Y, [mv])) != target:
                continue
        except Exception:
            continue
        found.append((Y, mv))

print(f"    {len(found)} predecessor/entry-move pairs reach X")
for Y, mv in found:
    r9 = probe(f"  E={mv:<5} 9 plies", Y, [mv] + XW * 2)
    r10 = probe(f"  E={mv:<5} 10 plies", Y, [mv] + XW * 2 + ["e3f5"])
    if r9 and r10 and r9[1] != r10[1]:
        print(f"    ^^^ PARITY SPLIT on a mutual chase: 9-ply {r9[1]} vs 10-ply {r10[1]}")
print()

# ---------------------------------------------------------------- section 4
print("## 4. Built-in xiangqi: the chase cases already in the fork's test.py")
XQ = "xiangqi"
cases = [
    ("direct chase, chasing entry (9)", "2bakabnr/9/r1n1c4/2p1p1p1p/PP7/9/4P1P1P/2C3NC1/9/1NBAKAB1R w - - 0 1",
     ["c3a3", "a8b8", "a3b3", "b8a8", "b3a3", "a8b8", "a3b3", "b8a8", "b3a3"], MATE),
    ("direct chase, other parity (12)", "2bakabnr/9/r1n1c4/2p1p1p1p/PP7/9/4P1P1P/2C3NC1/9/1NBAKAB1R w - - 0 1",
     ["c3a3", "a8b8", "a3b3", "b8a8", "b3a3", "a8b8", "a3b3", "b8a8", "b3a3", "a8b8", "a3b3", "b8a8"], -MATE),
    ("discovered chase by cannon (9)", "2bakabr1/9/9/r1p1p1p2/p7R/P8/9/9/9/CC1AKA3 w - - 0 1",
     ["a5a6", "a7b7", "a6b6", "b7a7", "b6a6", "a7b7", "a6b6", "b7a7", "b6a6"], MATE),
    ("chase by soldier -> draw (9)", "2bakabr1/9/9/r1p1p1p2/p7R/P8/9/9/9/1C1AKA3 w - - 0 1",
     ["a5a6", "a7b7", "a6b6", "b7a7", "b6a6", "a7b7", "a6b6", "b7a7", "b6a6"], 0),
    ("mutual chase -> draw (17, entry f7h7)", "4k4/7n1/9/4pR3/9/9/4P4/9/9/4K4 w - - 0 1",
     ["f7h7"] + 2 * ["h9f8", "h7h8", "f8g6", "h8g8", "g6i7", "g8g7", "i7h9", "g7h7"], 0),
    ("D39 pinned chariot (17, entry b7b9)", "2baka1r1/C4rN2/9/1Rp1p4/9/9/4P4/9/4A4/4KA3 w - - 0 1",
     ["b7b9"] + 2 * ["f10e9", "b9b10", "e9f10", "b10b9"], MATE),
    ("mutual perp check (17, entry b2a2)", "4k4/9/r1r6/9/PPPP5/9/9/9/1C7/5K3 w - - 0 1",
     ["b2a2"] + 2 * ["a8b8", "a2c2", "c8d8", "c2b2", "b8a8", "b2d2", "d8c8", "d2a2"], 0),
]
for name, fen, moves, want in cases:
    r = probe(name, fen, moves, variant=XQ, note=f"test.py expects {want}")
    if r and r[1] != want:
        print(f"    ^^^ DIFFERS FROM test.py EXPECTATION ({r[1]} != {want})")
