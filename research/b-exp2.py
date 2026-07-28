#!/usr/bin/env python3
"""Agent-B experiment batch 2: value ordering, symmetry, attacker classes,
mixed sequences, mutual chase, and the chaseThem window artifact."""
import importlib.util
import os

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("bprobe", os.path.join(HERE, "b-probe.py"))
B = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(B)
B.setup()
probe = B.probe
CYC = lambda c: list(c) * 2  # noqa: E731

# --------- Q6 value ordering: horse chasing a PROTECTED rook is a chase anyway
HORSE = ["a4c3", "d5c5", "c3a4", "c5d5"]
probe("H1 horse chases a PROTECTED black rook",
      "3k3/7/3r2r/N6/7/7/4K2 w - - 0 1", CYC(HORSE),
      "Rg5 defends c5 and d5; horse-vs-rook should be a chase regardless of protection")

probe("H2 same shape, target is a PROTECTED cannon instead of a rook",
      "3k3/7/3c2r/N6/7/7/4K2 w - - 0 1", CYC(HORSE),
      "horse-vs-cannon is value-neutral, so protection should matter -> draw")

probe("H3 same shape, target is an UNPROTECTED cannon",
      "3k3/7/3c4/N6/7/7/4K2 w - - 0 1", CYC(HORSE),
      "expect violation")

# ------------- Q1/Q6 symmetric exclusion and the pinned-target exception
ROOKS = ["a4a5", "d5d4", "a5a4", "d4d5"]
probe("I1 rook chases an UNPROTECTED rook (mutual attack, no pin)",
      "3k3/7/3r3/R6/7/7/2K4 w - - 0 1", CYC(ROOKS),
      "same-type attack should be excluded as symmetric -> draw")

probe("I2 same, but the target rook is pinned by Rd1 against Kd7",
      "3k3/7/3r3/R6/7/7/2KR3 w - - 0 1", CYC(ROOKS),
      "pin should defeat the symmetry exclusion -> violation")

# --------------------------- Q6 attacker classes: soldier and king never chase
probe("J1 soldier repeatedly attacks an unprotected cannon",
      "4k2/7/7/c6/1P5/7/2K4 w - - 0 1",
      CYC(["b3a3", "a4b4", "a3b3", "b4a4"]),
      "soldier movers are excluded from the chase classifier -> draw")

probe("K1 king repeatedly attacks an unprotected cannon inside its own palace",
      "4k2/7/7/7/2c4/2K4/7 w - - 0 1",
      CYC(["c2d2", "c3d3", "d2c2", "d3c3"]),
      "king movers are excluded -> draw")

# ------------------------------------- Q4 mixed check/chase by the SAME side
probe("M1 white alternates check and chase on successive moves",
      "3k3/7/2c4/2R4/7/7/4K2 w - - 0 1",
      CYC(["c4d4", "d7c7", "d4c4", "c7d7"]),
      "Rd4 checks (no chase), Rc4 chases c5 (no check) -> neither class sustained")

probe("M2 white chases two DIFFERENT targets on alternate moves",
      "4k2/3n3/2c4/2R4/7/7/3K3 w - - 0 1",
      CYC(["c4d4", "e7e6", "d4c4", "e6e7"]),
      "Rd4 chases the horse d6, Rc4 chases the cannon c5 -> empty intersection")

# --------------------------------- Q1 king-sole-defender false negative probe
probe("D3 king is sole defender but a white horse covers the recapture square",
      "2k4/4R2/2c4/1N5/7/7/3K3 w - - 0 1",
      CYC(["e6e5", "c5c6", "e5e6", "c6c5"]),
      "Kxc6 would be illegal (Nb4 covers c6); engine only models the flying-general case")

# ------------------------- Q5 chaseThem window: move INTO the first occurrence
probe("N1 chaser to move at occurrence 1 via a non-chasing rook move",
      "4k2/7/c6/7/7/7/R1K4 w - - 0 1",
      ["a1a3"] + CYC(["a5b5", "a3b3", "b5a5", "b3a3"]),
      "occurrences at plies 1/5/9; the a1a3 move that created occ.1 does not chase",
      prefixes=(5, 9))

probe("N2 control: identical 8 plies starting from the occurrence-1 position",
      "4k2/7/c6/7/R6/7/2K4 b - - 0 1",
      CYC(["a5b5", "a3b3", "b5a5", "b3a3"]),
      "expect violation (Red loses, Black to move at detection)")

# ------------------------------------------------------- Q4 mutual chase
MUT = ["c5c3", "e3e1", "c3c5", "e1e3"]
probe("L1 MUTUAL discovered chase (white horses vs rd4, black horses vs Rd2)",
      "3k3/7/1NR4/3r3/1N2rn1/2KR3/5n1 w - - 0 1", CYC(MUT),
      "both sides renew a discovered horse attack on an enemy rook every move")

probe("L2 control: black mechanism broken (horse f3 removed)",
      "3k3/7/1NR4/3r3/1N2r2/2KR3/5n1 w - - 0 1", CYC(MUT),
      "white alone chases -> Red wins")

probe("L3 control: white mechanism broken (horse b5 removed)",
      "3k3/7/2R4/3r3/1N2rn1/2KR3/5n1 w - - 0 1", CYC(MUT),
      "black alone chases -> Black wins")
