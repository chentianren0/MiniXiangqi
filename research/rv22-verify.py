#!/usr/bin/env python3
"""PR #22 pre-merge review: execute the constructibility claims and the three
interpretations against the fork build in discussion-drafts/r-scratch.

Read-only with respect to every repository.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "r-scratch"))
import pyffish  # noqa: E402

BUILTIN = "minixiangqi"
MX = "minixiangqitarget"
AXF = "minixiangqiaxf"
MATE = 32000

INI = (
    "[minixiangqiaxf:minixiangqi]\n"
    "chasingRule = axf\n"
    "nMoveRule = 0\n"
    "\n"
    "[minixiangqitarget:minixiangqi]\n"
    "chasingRule = axf\n"
    "nMoveRule = 0\n"
    "promotedSoldiersChaseable = false\n"
)


def setup():
    pyffish.load_variant_config(INI)
    print("pyffish", pyffish.version(), pyffish.info())
    for v in (MX, AXF):
        assert v in pyffish.variants(), v


def piece_count(fen):
    return sum(1 for ch in fen.split()[0] if ch.isalpha())


def legality(fen, moves, variant=MX):
    for i, m in enumerate(moves):
        if m not in pyffish.legal_moves(variant, fen, list(moves[:i])):
            return i, sorted(pyffish.legal_moves(variant, fen, list(moves[:i])))
    return None, None


def check_flags(fen, moves, variant=MX):
    """Side-to-move-in-check flag at every ply 0..len(moves)."""
    out = []
    for n in range(len(moves) + 1):
        sub = list(moves[:n])
        if n == 0:
            # gives_check() reports whether the position AFTER the listed moves
            # has its side to move in check; with no moves, probe via a null-safe
            # route: use the fen itself through legal_moves + get_fen parity.
            out.append(pyffish.gives_check(variant, fen, []))
        else:
            out.append(pyffish.gives_check(variant, fen, sub))
    return "".join("T" if f else "f" for f in out)


def loser(fen, moves, val, variant=MX):
    if val is None or val == 0:
        return None
    stm = pyffish.get_fen(variant, fen, list(moves)).split()[1]
    stm_is_red = stm == "w"
    if val < 0:
        return "Red" if stm_is_red else "Black"
    return "Black" if stm_is_red else "Red"


def report(name, fen, moves, variants=(MX, AXF, BUILTIN), prefixes=()):
    print("\n=== %s ===" % name)
    print("  fen    : %s   (%d pieces)" % (fen, piece_count(fen)))
    print("  moves  : %s   (%d plies)" % (" ".join(moves), len(moves)))
    bad, legal = legality(fen, moves)
    if bad is not None:
        print("  !! ILLEGAL at index %d (%s); legal there: %s" % (bad, moves[bad], legal))
        return
    print("  legal  : all %d plies legal in %s" % (len(moves), MX))
    print("  check  : %s   (side-to-move in check, ply 0..%d)"
          % (check_flags(fen, moves), len(moves)))
    for n in list(prefixes) + [len(moves)]:
        line = "  ply %-3d" % n
        for v in variants:
            f, val = pyffish.is_optional_game_end(v, fen, list(moves[:n]))
            sval = val if f else "-"
            line += "  %s=(%s,%s)" % (v.replace("minixiangqi", "") or "builtin", f, sval)
            if v == MX and f:
                lo = loser(fen, moves[:n], val, v)
                if lo:
                    line += " [LOSER=%s]" % lo
                elif val == 0:
                    line += " [DRAW]"
        print(line)
    print("  final  : %s" % pyffish.get_fen(MX, fen, list(moves)))


def M8(a, b, c, d, times=2, lead=()):
    return list(lead) + [a, b, c, d] * times


if __name__ == "__main__":
    setup()

    # ---- Claim 1: mutual perpetual check IS constructible, six pieces -------
    report("mx-mix-001 mutual perpetual check (reconciliation s1 row 1 / s5.8)",
           "3c3/7/2k3C/3n3/4N2/7/3K3 w - - 0 1",
           M8("e3d5", "d4f5", "d5e3", "f5d4"), prefixes=(4,))

    # sibling trio: one cannon only -> unilateral perpetual check
    report("mx-chk-003 (white cannon only) — unilateral perpetual check",
           "7/7/2k3C/3n3/4N2/7/3K3 w - - 0 1",
           M8("e3d5", "d4f5", "d5e3", "f5d4"), prefixes=(4,))
    report("mx-chk-004 (black cannon only) — unilateral discovered perpetual check",
           "3c3/7/2k4/3n3/4N2/7/3K3 w - - 0 1",
           M8("e3d5", "d4f5", "d5e3", "f5d4"), prefixes=(4,))

    # ---- Claim 2: check-over-chase precedence IS constructible, five pieces -
    report("mx-mix-004 check-over-chase precedence (reconciliation s1 row 2 / s5.8)",
           "3k3/7/1r3N1/7/7/2K4/3C3 w - - 0 1",
           M8("f5d6", "b5d5", "d6f5", "d5b5"), prefixes=(4,))
    report("mx-chs-027 control (cannon deleted) — the chase component alone",
           "3k3/7/1r3N1/7/7/2K4/7 w - - 0 1",
           M8("f5d6", "b5d5", "d6f5", "d5b5"), prefixes=(4,))

    # ---- Interpretation 1: alternating check and chase ----------------------
    report("mx-mix-003 alternating check and chase — expected neutral draw",
           "3k3/7/c6/R6/7/7/4K2 w - - 0 1",
           M8("a4d4", "d7c7", "d4a4", "c7d7"), prefixes=(4,))

    # ---- Interpretation 2: renewal (along the line vs across onto it) ------
    report("mx-chs-030 entry a1a3 ALONG the file (9 plies)",
           "4k2/7/c6/7/7/7/R1K4 w - - 0 1",
           ["a1a3"] + ["a5b5", "a3b3", "b5a5", "b3a3"] * 2, prefixes=(5,))
    report("mx-chs-031 entry b3a3 ACROSS onto the file (9 plies)",
           "4k2/7/c6/7/1R5/7/2K4 w - - 0 1",
           ["b3a3"] + ["a5b5", "a3b3", "b5a5", "b3a3"] * 2, prefixes=(5,))
    report("mx-chs-032 same as 030 plus one ply (10 plies, other parity)",
           "4k2/7/c6/7/7/7/R1K4 w - - 0 1",
           ["a1a3"] + ["a5b5", "a3b3", "b5a5", "b3a3"] * 2 + ["a5b5"], prefixes=(6,))

    # ---- Interpretation 3: general as sole defender ------------------------
    report("mx-chs-009 king sole defender, flying general voids recapture",
           "2k4/4R2/2c4/7/7/7/2K4 w - - 0 1",
           M8("e6e5", "c5c6", "e5e6", "c6c5"), prefixes=(4,))
    report("mx-chs-010 king sole defender, recapture legal",
           "2k4/4R2/2c4/7/7/7/3K3 w - - 0 1",
           M8("e6e5", "c5c6", "e5e6", "c6c5"), prefixes=(4,))
    report("mx-chs-011 king recapture illegal for a NON-flying-general reason",
           "2k4/4R2/2c4/1N5/7/7/3K3 w - - 0 1",
           M8("e6e5", "c5c6", "e5e6", "c6c5"), prefixes=(4,))
