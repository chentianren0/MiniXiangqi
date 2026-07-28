#!/usr/bin/env python3
"""Probe the mutual-perpetual-chase quiet-entry parity corner (fixtures mx-mix-005..008).

Usage:  python3 gap-mutual-probe.py <dir-with-pyffish.so>

Builds the mx-mix-002 mutual chase entered by a quiet king step from each side
in turn and reports what the engine adjudicates at the third occurrence (9
plies) and at the one-ply-later continuation (10 plies), plus the unilateral
halves that establish which sides are violating over the judged window.
"""
import sys

INI = """
[mxq_target:minixiangqi]
chasingRule = axf
nMoveRule = 0
promotedSoldiersChaseable = false
"""
V = "mxq_target"

# The mx-mix-002 wheel in its two phases.
P = "2k2r1/7/1cN1R2/7/2r1nC1/7/1R2K2 w - - 0 1"   # mx-mix-002's own start
WHEEL_P = ["c5b3", "e3f5", "b3c5", "f5e3"]
X = "2k2r1/7/1c2R2/7/1Nr1nC1/7/1R2K2 b - - 0 1"   # P after c5b3
WHEEL_X = ["e3f5", "b3c5", "f5e3", "c5b3"]

# A: White makes the quiet entry (white king steps e2->e1), reaching X.
YA, EA = "2k2r1/7/1c2R2/7/1Nr1nC1/4K2/1R5 w - - 0 1", "e2e1"
# B: Black makes the quiet entry (black king steps c6->c7), reaching P.
ZB, EB = "5r1/2k4/1cN1R2/7/2r1nC1/7/1R2K2 b - - 0 1", "c6c7"

# Unilateral halves of A, cut exactly as mx-chs-033/034 cut mx-mix-002.
YA_WHITE = "2k4/7/1c2R2/7/1N2n2/4K2/1R5 w - - 0 1"      # both black chariots deleted
YA_BLACK = "2k2r1/7/7/7/1Nr1nC1/4K2/7 w - - 0 1"        # white chariots + black cannon deleted
# Unilateral halves of B.
ZB_WHITE = "7/2k4/1cN1R2/7/4n2/7/1R2K2 b - - 0 1"
ZB_BLACK = "5r1/2k4/2N4/7/2r1nC1/7/4K2 b - - 0 1"


def label(fen, ended, value):
    if not ended:
        return "ongoing"
    if value == 0:
        return "value 0 (draw or claimable threefold - indistinguishable)"
    stm = fen.split()[1]
    loser = "Red" if ((stm == "w") == (value < 0)) else "Black"
    return f"{loser} LOSES (value {value})"


def run(sf, name, start, moves, note=""):
    fen = sf.get_fen(V, start, moves)
    ended, value = sf.is_optional_game_end(V, start, moves)
    print(f"  {name:<28} {len(moves):>2} plies -> {str((ended, value)):<15} {label(fen, ended, value)}  {note}")


def legality(sf, name, fen):
    p = fen.split()
    flipped = " ".join([p[0], "b" if p[1] == "w" else "w"] + p[2:])
    print(f"  {name:<10} {fen:<46} stm-in-check={sf.gives_check(V, fen, [])} "
          f"other-in-check={sf.gives_check(V, flipped, [])}")


def same_position(a, b):
    """Contract: placement and side to move only; the two counters are ignored."""
    return a.split()[:2] == b.split()[:2]


def main():
    sys.path.insert(0, sys.argv[1])
    import pyffish as sf
    print(f"engine: {sf.info()}   build: {sys.argv[1]}")
    sf.load_variant_config(INI)

    print("\n== position legality (side not to move must not be in check) ==")
    for n, f in (("YA", YA), ("X", X), ("ZB", ZB), ("P", P)):
        legality(sf, n, f)

    print("\n== the entry moves are legal, quiet, and change no attack ==")
    for n, start, mv, dest in (("A", YA, EA, X), ("B", ZB, EB, P)):
        after = sf.get_fen(V, start, [mv])
        print(f"  {n}: {mv}  legal={mv in sf.legal_moves(V, start, [])}  "
              f"gives_check={sf.gives_check(V, start, [mv])}  reaches_target={same_position(after, dest)}")
        for tgt, side in (("b5", "w"), ("f3", "b")):
            def atk(fen):
                q = fen.split(); q[1] = side
                return sorted(m for m in sf.legal_moves(V, " ".join(q), []) if m[2:4] == tgt)
            print(f"      attackers of {tgt}: before {atk(start)}  after {atk(after)}")

    print("\n== bare wheels (history begins at the first occurrence: the shape every approved fixture has) ==")
    run(sf, "mx-mix-002 (from P)", P, WHEEL_P * 2, "contract: draw / mutual")
    run(sf, "re-phased (from X)", X, WHEEL_X * 2, "contract: draw / mutual")

    print("\n== A: White makes the quiet entry (mx-mix-005 @9, mx-mix-006 @10) ==")
    run(sf, "A boundary (2nd occurrence)", YA, [EA] + WHEEL_X[:4])
    run(sf, "mx-mix-005", YA, [EA] + WHEEL_X * 2, "contract: draw / mutual")
    run(sf, "mx-mix-006 boundary", YA, [EA] + (WHEEL_X * 2)[:5])
    run(sf, "mx-mix-006", YA, [EA] + WHEEL_X * 2 + [WHEEL_X[0]], "contract: draw / mutual")

    print("\n== B: Black makes the quiet entry (mx-mix-007 @9, mx-mix-008 @10) ==")
    run(sf, "B boundary (2nd occurrence)", ZB, [EB] + WHEEL_P[:4])
    run(sf, "mx-mix-007", ZB, [EB] + WHEEL_P * 2, "contract: draw / mutual")
    run(sf, "mx-mix-008 boundary", ZB, [EB] + (WHEEL_P * 2)[:5])
    run(sf, "mx-mix-008", ZB, [EB] + WHEEL_P * 2 + [WHEEL_P[0]], "contract: draw / mutual")

    print("\n== unilateral halves, same entry and same wheel: who is violating over the window ==")
    for n, f, start, wheel, entry in (("A white-half", YA_WHITE, YA, WHEEL_X, EA),
                                      ("A black-half", YA_BLACK, YA, WHEEL_X, EA),
                                      ("B white-half", ZB_WHITE, ZB, WHEEL_P, EB),
                                      ("B black-half", ZB_BLACK, ZB, WHEEL_P, EB)):
        legality(sf, n, f)
        run(sf, n + " @9", f, [entry] + wheel * 2)
        run(sf, n + " @10", f, [entry] + wheel * 2 + [wheel[0]])
    print()


if __name__ == "__main__":
    main()
