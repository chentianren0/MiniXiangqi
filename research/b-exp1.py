#!/usr/bin/env python3
"""Agent-B experiment batch 1: protection semantics, attacker legality, discovery."""
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("bprobe", os.path.join(HERE, "b-probe.py"))
B = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(B)
B.setup()

probe = B.probe
CYC = lambda c: list(c) * 2  # noqa: E731  (4-ply cycle twice = 3 occurrences)

# ---------------------------------------------------------------- baselines
probe("A0 baseline mx-chs-001 (unprotected cannon)",
      "4k2/7/c6/7/1R5/7/2K4 w - - 0 1",
      CYC(["b3a3", "a5b5", "a3b3", "b5a5"]),
      "expect: AXF violation, Red loses")

probe("A1 baseline mx-chs-002 (rook on e5 protects)",
      "4k2/7/c3r2/7/1R5/7/2K4 w - - 0 1",
      CYC(["b3a3", "a5b5", "a3b3", "b5a5"]),
      "expect: neutral draw")

# ------------------------------------------------- Q1a: pinned defender
probe("B1 pinned defender (white Re1 pins black Re5 to Ke7)",
      "4k2/7/c3r2/7/1R5/7/2K1R2 w - - 0 1",
      CYC(["b3a3", "a5b5", "a3b3", "b5a5"]),
      "same as A1 but the e5 defender is pinned; expect violation if pins void protection")

# --------------------------------- Q1b: X-ray defender through the attacker
XRAY = ["e6e5", "c5c6", "e5e6", "c6c5"]
probe("C0 control: no defender at all (Re6/e5 chases cannon c5/c6)",
      "3k3/4R2/2c4/7/7/7/2K4 w - - 0 1", CYC(XRAY),
      "expect: violation (both white moves chase)")

probe("C1 X-ray defender g5 covers c5 only (through the attacker on e5)",
      "3k3/4R2/2c3r/7/7/7/2K4 w - - 0 1", CYC(XRAY),
      "if X-ray-through-attacker counts as protection: chase breaks on the e6e5 move -> draw")

# ------------------------- Q1c: king as sole defender + flying general
probe("D1 king sole defender, flying general blocks recapture (wK on c-file)",
      "2k4/4R2/2c4/7/7/7/2K4 w - - 0 1", CYC(XRAY),
      "black Kc7 defends c6; white Kc1 sees c6 down the open c-file -> recapture illegal")

probe("D2 control: same but white king off the c-file (recapture legal)",
      "2k4/4R2/2c4/7/7/7/3K3 w - - 0 1", CYC(XRAY),
      "black Kc7 defends c6 and CAN recapture -> chase breaks on e5e6 -> draw")

# --------------------------------- Q3a: chase by a pinned (immobile) attacker
probe("E1 chasing rook is absolutely pinned; the 'threat' can never be executed",
      "2r1k2/7/7/2R4/4c2/7/2K4 w - - 0 1",
      CYC(["c4c3", "e3e4", "c3c4", "e4e3"]),
      "white Rc3/c4 is pinned by Rc7 against Kc1; capturing on e3/e4 is illegal")

# ------------------------------------------- Q3b: pure discovered chase
probe("F1 discovered chase: white horse shuttles d3<->c5 uncovering Rd1 / Ra5",
      "4k2/7/R2n3/7/3N3/7/2KR3 w - - 0 1",
      CYC(["d3c5", "e7e6", "c5d3", "e6e7"]),
      "no direct attack on d5 ever; both white moves discover a rook attack on the horse")

probe("F2 control: remove Ra5 so only one of the two white moves discovers",
      "4k2/7/3n3/7/3N3/7/2KR3 w - - 0 1",
      CYC(["d3c5", "e7e6", "c5d3", "e6e7"]),
      "expect: neutral draw")

# ------------------------------ Q5: off-by-one window (chase must predate occ. 1)
probe("G1 same chase, but preceded by two non-chasing filler plies",
      "4k2/7/c6/7/7/1R5/2K4 w - - 0 1",
      ["b2b3", "e7e6"] + CYC(["b3a3", "a5b5", "a3b3", "b5a5"]),
      "3 occurrences at plies 2/6/10; white's ply-1 move does not chase",
      prefixes=(6, 10))

probe("G2 control: identical 8-ply chase from the ply-2 position",
      "4k3/7/c6/7/1R5/7/2K4 w - - 0 1",
      CYC(["b3a3", "a5b5", "a3b3", "b5a5"]),
      "black king on e6; expect violation")
