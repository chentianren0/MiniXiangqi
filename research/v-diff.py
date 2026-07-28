#!/usr/bin/env python3
"""Independent verifier differential: emit deterministic adjudication lines for a build.

Usage: python3 v-diff.py <dir-with-pyffish.so> <mode> [seed] [samples]

modes:
  chase   4-ply-wheel repetition histories in the chasing variants, entered by the
          move that created the first occurrence (the parity-sensitive shape)
  broad   random games in every variant the build offers, sampling
          is_optional_game_end at every ply

Output is one line per adjudication, fully self-describing so that a plain diff
between two builds also catches any divergence in the generated histories.
"""
import random
import sys
import pathlib

BUILD = pathlib.Path(sys.argv[1]).resolve()
MODE = sys.argv[2]
SEED = int(sys.argv[3]) if len(sys.argv) > 3 else 1
SAMPLES = int(sys.argv[4]) if len(sys.argv) > 4 else 200

sys.path.insert(0, str(BUILD))
import pyffish as sf  # noqa: E402

INI = """
[mxqaxf:minixiangqi]
chasingRule = axf
nMoveRule = 0
promotedSoldiersChaseable = false

[mxqaxfsc:minixiangqi]
chasingRule = axf
nMoveRule = 0

[xqsoldierexempt:xiangqi]
promotedSoldiersChaseable = false
"""
sf.load_variant_config(INI)

CHASE_VARIANTS = ["xiangqi", "xqsoldierexempt", "mxqaxf", "mxqaxfsc", "minixiangqi"]


def reverse(m):
    return m[2:4] + m[0:2]


def emit(tag, variant, fen, moves):
    try:
        flag, value = sf.is_optional_game_end(variant, fen, moves)
    except Exception as e:  # noqa: BLE001
        print(f"{tag}\t{variant}\tERR\t{e}\t{' '.join(moves)}")
        return
    v = value if flag else 0
    print(f"{tag}\t{variant}\t{int(flag)}\t{v}\t{len(moves)}\t{' '.join(moves)}")


def random_history(rng, variant, start, plies):
    moves = []
    for _ in range(plies):
        legal = sf.legal_moves(variant, start, moves)
        if not legal:
            break
        if sf.is_immediate_game_end(variant, start, moves)[0]:
            break
        moves.append(rng.choice(legal))
    return moves


def find_wheels(variant, start, moves, rng, want=2):
    """Quiet 4-ply wheels m1 m2 rev(m1) rev(m2) that restore the position."""
    out = []
    base = sf.get_fen(variant, start, moves).split()[0:2]
    l1 = [m for m in sf.legal_moves(variant, start, moves)
          if not sf.is_capture(variant, start, moves, m) and len(m) == 4]
    rng.shuffle(l1)
    for m1 in l1[:14]:
        h1 = moves + [m1]
        l2 = [m for m in sf.legal_moves(variant, start, h1)
              if not sf.is_capture(variant, start, h1, m) and len(m) == 4]
        rng.shuffle(l2)
        for m2 in l2[:14]:
            h2 = h1 + [m2]
            m3 = reverse(m1)
            if m3 not in sf.legal_moves(variant, start, h2):
                continue
            h3 = h2 + [m3]
            m4 = reverse(m2)
            if m4 not in sf.legal_moves(variant, start, h3):
                continue
            h4 = h3 + [m4]
            if sf.get_fen(variant, start, h4).split()[0:2] != base:
                continue
            out.append([m1, m2, m3, m4])
            if len(out) >= want:
                return out
    return out


def mode_chase():
    rng = random.Random(SEED)
    for variant in CHASE_VARIANTS:
        start = sf.start_fen(variant)
        found = 0
        attempt = 0
        while found < SAMPLES and attempt < SAMPLES * 40:
            attempt += 1
            plies = rng.choice([6, 8, 10, 12, 16, 20, 24, 30, 40])
            hist = random_history(rng, variant, start, plies)
            if len(hist) < 2:
                continue
            wheels = find_wheels(variant, start, hist, rng)
            for w in wheels:
                found += 1
                full = hist + w * 3
                for L in (len(hist) + n for n in (4, 8, 9, 10, 11, 12)):
                    emit(f"chase{SEED}", variant, start, full[:L])


def mode_broad():
    rng = random.Random(SEED)
    for variant in sorted(sf.variants()):
        try:
            start = sf.start_fen(variant)
        except Exception:  # noqa: BLE001
            continue
        for game in range(SAMPLES):
            moves = []
            for _ in range(90):
                try:
                    legal = sf.legal_moves(variant, start, moves)
                except Exception:  # noqa: BLE001
                    break
                if not legal:
                    break
                moves.append(rng.choice(legal))
                emit(f"broad{SEED}", variant, start, moves)
                try:
                    if sf.is_immediate_game_end(variant, start, moves)[0]:
                        break
                except Exception:  # noqa: BLE001
                    break


BOARDS = {
    "xiangqi": (9, 10, "RNBAKCP", "rnbakcp", "wb"),
    "xqsoldierexempt": (9, 10, "RNBAKCP", "rnbakcp", "wb"),
    "mxqaxf": (7, 7, "RNKCP", "rnkcp", "wb"),
    "mxqaxfsc": (7, 7, "RNKCP", "rnkcp", "wb"),
    "minixiangqi": (7, 7, "RNKCP", "rnkcp", "wb"),
}


def random_sparse_fen(variant, rng):
    files, ranks, wp, bp, _ = BOARDS[variant]
    grid = [[None] * files for _ in range(ranks)]
    # kings inside the palace
    pf = [3, 4, 5] if files == 9 else [2, 3, 4]
    wr = [0, 1, 2] if ranks == 10 else [0, 1, 2]
    br = [7, 8, 9] if ranks == 10 else [4, 5, 6]
    wk = (rng.choice(wr), rng.choice(pf))
    bk = (rng.choice(br), rng.choice(pf))
    if wk == bk:
        return None
    grid[wk[0]][wk[1]] = "K"
    grid[bk[0]][bk[1]] = "k"
    others = [c for c in wp if c != "K"] + [c for c in bp if c != "k"]
    for _ in range(rng.randint(2, 6)):
        p = rng.choice(others)
        r, f = rng.randrange(ranks), rng.randrange(files)
        if grid[r][f] is not None:
            continue
        if p in "BbAa" or p in "Pp":
            continue  # keep to pieces with no region/promotion subtleties
        grid[r][f] = p
    rows = []
    for r in range(ranks - 1, -1, -1):
        row, empty = "", 0
        for f in range(files):
            c = grid[r][f]
            if c is None:
                empty += 1
            else:
                if empty:
                    row += str(empty)
                    empty = 0
                row += c
        if empty:
            row += str(empty)
        rows.append(row)
    stm = rng.choice("wb")
    fen = "/".join(rows) + f" {stm} - - 0 1"
    try:
        if sf.validate_fen(fen, variant) != sf.FEN_OK:
            return None
    except Exception:  # noqa: BLE001
        return None
    return fen


def mode_sparse():
    rng = random.Random(SEED)
    for variant in CHASE_VARIANTS:
        found = 0
        attempt = 0
        while found < SAMPLES and attempt < SAMPLES * 200:
            attempt += 1
            fen = random_sparse_fen(variant, rng)
            if fen is None:
                continue
            # 1-3 plies of prefix so the first occurrence is created by a real move
            hist = random_history(rng, variant, fen, rng.choice([1, 2, 3]))
            if not hist:
                continue
            try:
                wheels = find_wheels(variant, fen, hist, rng)
            except Exception:  # noqa: BLE001
                continue
            for w in wheels:
                found += 1
                full = hist + w * 3
                for L in (len(hist) + n for n in (4, 8, 9, 10, 11, 12)):
                    emit(f"sp{SEED}", variant, fen, full[:L])


def mode_rep():
    """Every variant, forced repetition: random prefix then a 4-ply wheel repeated."""
    rng = random.Random(SEED)
    for variant in sorted(sf.variants()):
        try:
            start = sf.start_fen(variant)
        except Exception:  # noqa: BLE001
            continue
        found = 0
        attempt = 0
        while found < SAMPLES and attempt < SAMPLES * 12:
            attempt += 1
            try:
                hist = random_history(rng, variant, start, rng.choice([2, 4, 6, 10, 14]))
                if len(hist) < 2:
                    continue
                wheels = find_wheels(variant, start, hist, rng, want=1)
            except Exception:  # noqa: BLE001
                break
            for w in wheels:
                found += 1
                full = hist + w * 3
                for L in (len(hist) + n for n in (4, 8, 9, 10, 11, 12)):
                    emit(f"rep{SEED}", variant, start, full[:L])


def mode_long():
    """Every variant, long random games so the n-move rule can fire."""
    rng = random.Random(SEED)
    for variant in sorted(sf.variants()):
        try:
            start = sf.start_fen(variant)
        except Exception:  # noqa: BLE001
            continue
        for _ in range(SAMPLES):
            moves = []
            for ply in range(400):
                try:
                    legal = sf.legal_moves(variant, start, moves)
                except Exception:  # noqa: BLE001
                    break
                if not legal:
                    break
                moves.append(rng.choice(legal))
                if ply >= 40:
                    emit(f"long{SEED}", variant, start, moves)
                try:
                    if sf.is_immediate_game_end(variant, start, moves)[0]:
                        break
                except Exception:  # noqa: BLE001
                    break


if MODE == "chase":
    mode_chase()
elif MODE == "rep":
    mode_rep()
elif MODE == "long":
    mode_long()
elif MODE == "sparse":
    mode_sparse()
elif MODE == "broad":
    mode_broad()
else:
    raise SystemExit("unknown mode")
