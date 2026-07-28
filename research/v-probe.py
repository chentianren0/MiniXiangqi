#!/usr/bin/env python3
"""Independent verifier probes: my own positions, not the implementer's.

Usage: python3 v-probe.py <dir-with-pyffish.so>
"""
import sys
import pathlib

BUILD = pathlib.Path(sys.argv[1]).resolve()
sys.path.insert(0, str(BUILD))
import pyffish as sf  # noqa: E402

INI = """
[mxqaxf:minixiangqi]
chasingRule = axf
nMoveRule = 0
promotedSoldiersChaseable = false
"""
sf.load_variant_config(INI)

HAS_RULE = hasattr(sf, "optional_game_end_rule")


def show(label, variant, fen, moves):
    for i in range(len(moves)):
        if moves[i] not in sf.legal_moves(variant, fen, moves[:i]):
            print(f"{label:34s} ILLEGAL MOVE {moves[i]} at ply {i}")
            return
    flag, value = sf.is_optional_game_end(variant, fen, moves)
    r = ""
    if HAS_RULE:
        r = f"  rule={sf.optional_game_end_rule(variant, fen, moves)}"
    print(f"{label:34s} plies={len(moves):3d} flag={flag} value={value if flag else '-'}{r}")


# ---------------------------------------------------------------- P1
# White chariot on the e-file is absolutely pinned to the white king on e1 by the
# black chariot on e8. It "attacks" the black cannon off the pin line, but Rxc4 /
# Rxc3 can never be played.
P1_PINNED = "3k5/9/4r4/9/9/9/2c1R4/9/9/4K4 w - - 0 1"
P1_FREE = "3k5/9/4r4/9/9/9/2c1R4/9/9/5K3 w - - 0 1"
P1_WHEEL = ["e4e3", "c4c5", "e3e4", "c5c4"]

# ---------------------------------------------------------------- P2
# Both kings on the e-file. The black chariot shuttling e5/e6 is attacked by the
# white chariot shuttling a5/a6 and attacks it right back, so the mutual attack
# cancels - unless the black chariot counts as flying-general pinned.
P2_REALPIN = "4k4/9/9/9/R8/4r4/9/9/9/4K4 w - - 0 1"
P2_WHITE_BLOCKER = "4k4/9/9/9/R8/4r4/9/4P4/9/4K4 w - - 0 1"
P2_OFF_SEGMENT = "4r4/9/4k4/9/R8/4r4/9/9/9/4K4 w - - 0 1"
P2_WHEEL = ["a6a5", "e5e6", "a5a6", "e6e5"]

for label, fen in (("P1 pinned chaser", P1_PINNED), ("P1 free chaser (control)", P1_FREE)):
    for n in (2, 3):
        show(f"{label} x{n}", "xiangqi", fen, P1_WHEEL * n)

for label, fen in (("P2 real pin (control)", P2_REALPIN),
                   ("P2 white blocker between kings", P2_WHITE_BLOCKER),
                   ("P2 black piece off segment", P2_OFF_SEGMENT)):
    for n in (2, 3):
        show(f"{label} x{n}", "xiangqi", fen, P2_WHEEL * n)

# ---------------------------------------------------------------- P3
# Mutual perpetual chase entered by a quiet move: the contract requires a draw and
# forbids the winner from depending on which side made the entry move.
for fen, entry, wheel, tag in (
    ("2k2r1/7/1c2R2/7/1Nr1nC1/7/1R1K3 w - - 0 1", "d1e1",
     ["e3f5", "b3c5", "f5e3", "c5b3"], "P3 mutual, quiet White entry"),
    ("3k1r1/7/1cN1R2/7/2r1nC1/7/1R2K2 b - - 0 1", "d7c7",
     ["c5b3", "e3f5", "b3c5", "f5e3"], "P3 mutual, quiet Black entry"),
):
    for extra in ([], ["x"]):
        mv = [entry] + wheel * 2 + (wheel[:1] if extra else [])
        show(f"{tag}{' +1' if extra else ''}", "mxqaxf", fen, mv)

# Unilateral chase entered by a quiet move, judged at the earliest point
show("P3 unilateral quiet entry @9", "mxqaxf", "4k2/7/c6/7/7/7/R1K4 w - - 0 1",
     ["a1a3"] + ["a5b5", "a3b3", "b5a5", "b3a3"] * 2)
show("P3 unilateral quiet entry @10", "mxqaxf", "4k2/7/c6/7/7/7/R1K4 w - - 0 1",
     ["a1a3"] + ["a5b5", "a3b3", "b5a5", "b3a3"] * 2 + ["a5b5"])

# ---------------------------------------------------------------- P4
if HAS_RULE:
    print("--- P4 accessor ---")
    print("constants:", [(n, getattr(sf, n)) for n in dir(sf) if n.startswith("OPTIONAL_END_")])
