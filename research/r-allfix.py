#!/usr/bin/env python3
"""Replay every fixture proposed by design A and design B against fork HEAD (MX target variant)."""
import sys, os
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from r_harness import *  # noqa
import pyffish  # noqa

setup()


def R(a, b, c, d, n=2, lead=()):
    return list(lead) + [a, b, c, d] * n


# (label, expected-state-per-design, fen, moves, boundary_prefix)
CASES = [
    # ---------------- Design A ----------------
    ("A/chs-005 pinned defender",              "black-wins", "4k2/7/c3r2/7/1R5/7/2K1R2 w - - 0 1", R("b3a3","a5b5","a3b3","b5a5"), 4),
    ("A/chs-006 cannon defender no screen",    "black-wins", "4k2/7/c3c2/7/1R5/7/2K4 w - - 0 1",  R("b3a3","a5b5","a3b3","b5a5"), 4),
    ("A/chs-007 king outside palace",          "black-wins", "7/7/1ck4/7/7/7/R3K2 w - - 0 1",      R("a1b1","b5a5","b1a1","a5b5"), 4),
    ("A/chs-008 king inside palace",           "claim-draw", "7/3k3/3c3/6R/7/7/2K4 w - - 0 1",     R("g4g5","d5d4","g5g4","d4d5"), 4),
    ("A/chs-009 flying general voids",         "black-wins", "4R2/7/2kc3/7/7/7/3K3 w - - 0 1",     R("e7d7","d5e5","d7e7","e5d5"), 4),
    ("A/chs-010 king off file",                "claim-draw", "4R2/7/2kc3/7/7/7/4K2 w - - 0 1",     R("e7d7","d5e5","d7e7","e5d5"), 4),
    ("A/chs-011 horse vs protected rook",      "black-wins", "4k2/3N3/r3r2/7/7/7/3K3 w - - 0 1",   R("d6c4","a5b5","c4d6","b5a5"), 4),
    ("A/chs-012 horse vs protected cannon",    "claim-draw", "4k2/3N3/c3r2/7/7/7/3K3 w - - 0 1",   R("d6c4","a5b5","c4d6","b5a5"), 4),
    ("A/chs-013 rook vs rook",                 "claim-draw", "4k2/7/r6/7/1R5/7/2K4 w - - 0 1",     R("b3a3","a5b5","a3b3","b5a5"), 4),
    ("A/chs-014 one chase one idle",           "claim-draw", "3k3/7/c6/7/1R5/7/2K4 w - - 0 1",     R("b3a3","a5a6","a3b3","a6a5"), 4),
    ("A/chs-015 six-ply cycle",                "black-wins", "3k3/7/c6/7/2R4/7/4K2 w - - 0 1",     ["c3a3","a5b5","a3b3","b5c5","b3c3","c5a5"]*2, 6),
    ("A/chs-016 idle then chase (3rd occ)",    "claim-draw", "4k2/7/c6/7/1R5/7/2K4 w - - 0 1",     ["c1c2","e7e6","c2c1","e6e7","b3a3","a5b5","a3b3","b5a5"], 4),
    ("A/chs-017 idle then 2 chase cycles",     "black-wins", "4k2/7/c6/7/1R5/7/2K4 w - - 0 1",     ["c1c2","e7e6","c2c1","e6e7"]+["b3a3","a5b5","a3b3","b5a5"]*2, 8),
    ("A/chs-018 pure discovered chase",        "black-wins", "4k2/7/R1Nc3/7/7/7/2KR3 w - - 0 1",   R("c5d3","e7e6","d3c5","e6e7"), 4),
    ("A/chs-019 pinned attacker",              "claim-draw", "3rk2/7/7/3R3/1c5/7/3K3 w - - 0 1",   R("d4d3","b3b4","d3d4","b4b3"), 4),
    ("A/chs-020 mutual chase",                 "draw",       "2k2r1/7/1cN1R2/7/2r1nC1/7/1R2K2 w - - 0 1", R("c5b3","e3f5","b3c5","f5e3"), 4),
    ("A/chs-021 white half",                   "black-wins", "2k4/7/1cN1R2/7/4n2/7/1R2K2 w - - 0 1", R("c5b3","e3f5","b3c5","f5e3"), 4),
    ("A/chs-022 black half",                   "red-wins",   "2k2r1/7/2N4/7/2r1nC1/7/4K2 w - - 0 1", R("c5b3","e3f5","b3c5","f5e3"), 4),
    ("A/chs-023 alternating targets",          "claim-draw", "3k3/7/c5c/7/R6/7/2K4 w - - 0 1",     R("a3g3","d7d6","g3a3","d6d7"), 4),
    ("A/chs-024 alternating attackers",        "black-wins", "R6/7/c3k2/7/1R5/7/3K3 w - - 0 1",    ["b3a3","a5b5","a7b7","b5a5","b7a7","a5b5","a3b3","b5a5"]*2, 8),
    ("A/chs-025 soldier as chaser",            "claim-draw", "4k2/7/1c5/2P4/7/7/3K3 w - - 0 1",    R("c4b4","b5c5","b4c4","c5b5"), 4),
    ("A/chs-026 king as chaser",               "claim-draw", "4k2/7/7/7/2c4/3K3/7 w - - 0 1",      R("d2c2","c3d3","c2d2","d3c3"), 4),
    ("A/chk-003 alternating check/chase",      "claim-draw", "3k3/7/c6/R6/7/7/4K2 w - - 0 1",      R("a4d4","d7c7","d4a4","c7d7"), 4),
    # ---------------- Design B ----------------
    ("B/chs-005 pinned defender",              "black-wins", "4k2/7/c3r2/7/1R5/7/2K1R2 w - - 0 1", R("b3a3","a5b5","a3b3","b5a5"), 4),
    ("B/chs-006 c-file family base",           "black-wins", "3k3/4R2/2c4/7/7/7/2K4 w - - 0 1",    R("e6e5","c5c6","e5e6","c6c5"), 4),
    ("B/chs-007 X-ray defender",               "claim-draw", "3k3/4R2/2c3r/7/7/7/2K4 w - - 0 1",   R("e6e5","c5c6","e5e6","c6c5"), 4),
    ("B/chs-008 king sole def, flying general","black-wins", "2k4/4R2/2c4/7/7/7/2K4 w - - 0 1",    R("e6e5","c5c6","e5e6","c6c5"), 4),
    ("B/chs-009 king sole def, legal recap",   "claim-draw", "2k4/4R2/2c4/7/7/7/3K3 w - - 0 1",    R("e6e5","c5c6","e5e6","c6c5"), 4),
    ("B/chs-010 soldier defender",             "claim-draw", "3k3/1p2R2/2c4/7/7/7/2K4 w - - 0 1",  R("e6e5","c5c6","e5e6","c6c5"), 4),
    ("B/chs-023 king recap illegal (non-FG)",  "claim-draw", "2k4/4R2/2c4/1N5/7/7/3K3 w - - 0 1",  R("e6e5","c5c6","e5e6","c6c5"), 4),
    ("B/chs-011 horse vs protected chariot",   "black-wins", "3k3/7/3r2r/N6/7/7/4K2 w - - 0 1",    R("a4c3","d5c5","c3a4","c5d5"), 4),
    ("B/chs-012 horse vs protected cannon",    "claim-draw", "3k3/7/3c2r/N6/7/7/4K2 w - - 0 1",    R("a4c3","d5c5","c3a4","c5d5"), 4),
    ("B/chs-013 chariot vs chariot",           "claim-draw", "3k3/7/3r3/R6/7/7/2K4 w - - 0 1",     R("a4a5","d5d4","a5a4","d4d5"), 4),
    ("B/chs-014 same-type but pinned",         "black-wins", "3k3/7/3r3/R6/7/7/2KR3 w - - 0 1",    R("a4a5","d5d4","a5a4","d4d5"), 4),
    ("B/chs-015 soldier never chases",         "claim-draw", "4k2/7/7/c6/1P5/7/2K4 w - - 0 1",     R("b3a3","a4b4","a3b3","b4a4"), 4),
    ("B/chs-016 king never chases",            "claim-draw", "4k2/7/7/7/2c4/2K4/7 w - - 0 1",      R("c2d2","c3d3","d2c2","d3c3"), 4),
    ("B/chs-017 pure discovered chase",        "black-wins", "4k2/7/R2n3/7/3N3/7/2KR3 w - - 0 1",  R("d3c5","e7e6","c5d3","e6e7"), 4),
    ("B/chs-018 alternating targets",          "claim-draw", "4k2/3n3/2c4/2R4/7/7/3K3 w - - 0 1",  R("c4d4","e7e6","d4c4","e6e7"), 4),
    ("B/chs-022 chaser not to move at det.",   "black-wins", "4k2/7/c6/7/1R5/7/2K4 w - - 0 1",     ["b3a3"]+R("a5b5","a3b3","b5a5","b3a3"), 5),
    ("B/chs-019 pinned attacker",              "claim-draw", "2r1k2/7/7/2R4/4c2/7/2K4 w - - 0 1",  R("c4c3","e3e4","c3c4","e4e3"), 4),
    ("B/chs-020 flying-general false pin",     "claim-draw", "2k4/7/R6/2r4/2N4/7/2K4 w - - 0 1",   R("a5a4","c4c5","a4a5","c5c4"), 4),
    ("B/chs-021 window too wide",              "black-wins", "4k2/7/c6/7/7/7/R1K4 w - - 0 1",      ["a1a3"]+R("a5b5","a3b3","b5a5","b3a3"), 5),
    ("B/chk-003 cannon battery check",         "black-wins", "7/7/2k3C/3n3/4N2/7/3K3 w - - 0 1",   R("e3d5","d4f5","d5e3","f5d4"), 4),
    ("B/chk-004 discovered perpetual check",   "red-wins",   "3c3/7/2k4/3n3/4N2/7/3K3 w - - 0 1",  R("e3d5","d4f5","d5e3","f5d4"), 4),
    ("B/mix-001 mutual perpetual check",       "draw",       "3c3/7/2k3C/3n3/4N2/7/3K3 w - - 0 1", R("e3d5","d4f5","d5e3","f5d4"), 4),
    ("B/mix-002 mutual perpetual chase",       "draw",       "3k3/7/1NR4/3r3/1N2rn1/2KR3/5n1 w - - 0 1", R("c5c3","e3e1","c3c5","e1e3"), 4),
    ("B/mix-003 alternating check/chase",      "claim-draw", "3k3/7/2c4/2R4/7/7/4K2 w - - 0 1",    R("c4d4","d7c7","d4c4","c7d7"), 4),
    ("B/mix-004 check outranks chase",         "black-wins", "3k3/7/1r3N1/7/7/2K4/3C3 w - - 0 1",  R("f5d6","b5d5","d6f5","d5b5"), 4),
    ("B/chs-024 chase alone (mix-004 minus C)","red-wins",   "3k3/7/1r3N1/7/7/2K4/7 w - - 0 1",    R("f5d6","b5d5","d6f5","d5b5"), 4),
]


def observed(fen, moves):
    f, v = ogc(fen, moves, MX)
    if not f:
        return "ongoing"
    if v == 0:
        return "draw-or-claimable(0)"
    lo = loser(fen, moves, v, MX)
    return ("black-wins" if lo == "Red" else "red-wins")


print("%-42s %-12s %-22s %s" % ("case", "design says", "engine (MX target)", "notes"))
print("-" * 110)
for label, want, fen, mv, bp in CASES:
    ok, bad = play(fen, mv, MX)
    if not ok:
        print("%-42s %-12s %-22s ILLEGAL@%d(%s)" % (label, want, "-", bad, mv[bad]))
        continue
    got = observed(fen, mv)
    # boundary
    fb, vb = ogc(fen, mv[:bp], MX)
    bnote = "" if not fb else "BOUNDARY@%d ALREADY ENDED(%s)" % (bp, vb)
    agree = (want in ("claim-draw", "draw") and got == "draw-or-claimable(0)") or (want == got)
    mark = "  " if agree else "**"
    rf = pyffish.get_fen(MX, fen, list(mv))
    ic = pyffish.gives_check(MX, fen, list(mv))
    print("%s%-40s %-12s %-22s %s | fen=%s in_check=%s" % (mark, label, want, got, bnote, rf, ic))
