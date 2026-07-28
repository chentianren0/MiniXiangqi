#!/usr/bin/env python3
"""King-as-chase-target differential.

    python3 kt-diff.py dump <build-dir> <seed> <positions> <out-file>
    python3 kt-diff.py cmp  <file-a> <file-b>

`dump` enumerates random small 7-by-7 Mini Xiangqi positions and, for each,
every 4-ply shuttle cycle `m1 m2 reverse(m1) reverse(m2)` that restores the
position exactly.  Each cycle is replayed to its third occurrence and
`is_optional_game_end` recorded for the 8-, 9- and 10-ply histories built from
it, so both side-to-move parities are covered.  Only cycles in which a king is
attacked at some ply are recorded: those are the only ones in which the
king-as-chase-target question can bite.

`cmp` diffs two dumps line by line.  Run `dump` once against the fork build, in
which kings are exempt as chase targets (the contract's rule), and once against
the research control build in which kings are NOT exempt.  A differing line is a
legal sequence whose adjudicated result depends on the king-target exclusion.

Workspace-only research scratch; part of no repository.
"""
import random
import sys

FILES = "abcdefg"
SQ = [f + str(r) for r in range(1, 8) for f in FILES]
WPAL = [f + str(r) for r in (1, 2, 3) for f in "cde"]
BPAL = [f + str(r) for r in (5, 6, 7) for f in "cde"]
INVENTORY = ["R", "R", "C", "C", "N", "N", "P", "P"]

VARIANT = "mxq"
INI = """
[mxq:minixiangqi]
chasingRule = axf
nMoveRule = 0
promotedSoldiersChaseable = false
"""


def make_fen(pieces, stm):
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
    return "/".join(rows) + " " + stm + " - - 0 1"


def random_pos(rng):
    used, pieces = set(), {}
    wk, bk = rng.choice(WPAL), rng.choice(BPAL)
    pieces[wk] = "K"
    pieces[bk] = "k"
    used.update([wk, bk])
    for upper, n in ((True, rng.randint(1, 3)), (False, rng.randint(1, 3))):
        for t in rng.sample(INVENTORY, n):
            free = [s for s in SQ if s not in used]
            if not free:
                break
            s = rng.choice(free)
            pieces[s] = t if upper else t.lower()
            used.add(s)
    return make_fen(pieces, rng.choice(["w", "b"]))


def placement(fen):
    q = fen.split()
    return q[0] + " " + q[1]


def rev(m):
    return m[2:4] + m[0:2]


def dump(build, seed, npos, out):
    sys.path.insert(0, build)
    import pyffish as sf

    sf.load_variant_config(INI)
    rng = random.Random(seed)
    lines = []
    positions = cycles = king_cycles = 0

    for _ in range(npos):
        start = random_pos(rng)
        try:
            l0 = sf.legal_moves(VARIANT, start, [])
        except Exception:
            continue
        if not l0:
            continue
        positions += 1
        base = placement(start)
        for m1 in l0:
            h1 = [m1]
            for m2 in sf.legal_moves(VARIANT, start, h1):
                h2 = h1 + [m2]
                m3 = rev(m1)
                if m3 not in sf.legal_moves(VARIANT, start, h2):
                    continue
                h3 = h2 + [m3]
                m4 = rev(m2)
                if m4 not in sf.legal_moves(VARIANT, start, h3):
                    continue
                cyc = h3 + [m4]
                if placement(sf.get_fen(VARIANT, start, cyc)) != base:
                    continue
                cycles += 1
                if not any(sf.gives_check(VARIANT, start, cyc[: i + 1]) for i in range(4)):
                    continue
                king_cycles += 1
                hist = cyc * 3
                for extra in (0, 1, 2):
                    seq = hist[: 8 + extra]
                    ok = True
                    for i in range(len(seq)):
                        if seq[i] not in sf.legal_moves(VARIANT, start, seq[:i]):
                            ok = False
                            break
                    if not ok:
                        continue
                    ended, value = sf.is_optional_game_end(VARIANT, start, seq)
                    v = value if ended else 0
                    lines.append(f"{start}|{' '.join(seq)}|{int(ended)}|{v}")

    open(out, "w").write("\n".join(lines) + "\n")
    print(f"build={build} seed={seed} sampled={npos} usable={positions} "
          f"4-ply cycles={cycles} king-touching={king_cycles} records={len(lines)}")
    return 0


def cmp_files(pa, pb):
    a = open(pa).read().splitlines()
    b = open(pb).read().splitlines()
    if len(a) != len(b):
        print(f"LENGTH MISMATCH {len(a)} vs {len(b)}")
    diffs = 0
    for i, (x, y) in enumerate(zip(a, b)):
        if x != y:
            diffs += 1
            if diffs <= 40:
                print(f"DIFF line {i}:\n  A {x}\n  B {y}")
    print(f"lines compared: {min(len(a), len(b))}   differing: {diffs}")
    return 1 if diffs else 0


if __name__ == "__main__":
    if sys.argv[1] == "cmp":
        sys.exit(cmp_files(sys.argv[2], sys.argv[3]))
    sys.exit(dump(sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), sys.argv[5]))
