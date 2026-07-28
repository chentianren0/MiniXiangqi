#!/usr/bin/env python3
"""Verify every claimed engine defect from designs A and B against fork HEAD."""
import sys, os
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from r_harness import *  # noqa
import pyffish  # noqa

setup()
print("engine:", pyffish.info())

print("\n\n############ CLAIM P3: pinned attacker chases (A mx-chs-019 / B mx-chs-019) ############")
probe("A repro: pinned white rook on d-file",
      "3rk2/7/7/3R3/1c5/7/3K3 w - - 0 1", M8("d4d3","b3b4","d3d4","b4b3"),
      note="Rd4 absolutely pinned by rd7 against Kd1; 'attacks' cannon b3/b4 which it can never capture")
probe("B repro: pinned white rook on c-file",
      "2r1k2/7/7/2R4/4c2/7/2K4 w - - 0 1", M8("c4c3","e3e4","c3c4","e4e3"),
      note="Rc4 absolutely pinned by rc7 against Kc1; 'attacks' cannon e3/e4")

print("\n\n############ CLAIM P1: flying-general FALSE pin (B mx-chs-020) ############")
probe("B repro: white N on c3 already blocks the c-file",
      "2k4/7/R6/2r4/2N4/7/2K4 w - - 0 1", M8("a5a4","c4c5","a4a5","c5c4"),
      note="Rook-vs-rook symmetric attack; black rook NOT pinned (Nc3 blocks) yet engine marks it pinned")
probe("B control S2: white king off the c-file",
      "2k4/7/R6/2r4/2N4/7/3K3 w - - 0 1", M8("a5a4","c4c5","a4a5","c5c4"),
      note="same but Kd1: no flying-general term at all -> symmetric exclusion applies")
# demonstrate the black rook really is free
print("   black rook legal moves after a5a4:",
      sorted(m for m in pyffish.legal_moves(MX, "2k4/7/R6/2r4/2N4/7/2K4 w - - 0 1", ["a5a4"]) if m.startswith("c4")))

print("\n\n############ CLAIM P2: chaseThem window one move too wide (B mx-chs-021/022) ############")
probe("B mx-chs-021: lead a1a3 (no chase) then the wheel",
      "4k2/7/c6/7/7/7/R1K4 w - - 0 1", ["a1a3"] + ["a5b5","a3b3","b5a5","b3a3"]*2,
      note="lead move does NOT chase; identical wheel afterwards", prefixes=[5])
probe("B mx-chs-022: lead b3a3 (chases) then the same wheel",
      "4k2/7/c6/7/1R5/7/2K4 w - - 0 1", ["b3a3"] + ["a5b5","a3b3","b5a5","b3a3"]*2,
      note="lead move DOES chase; wheel byte-identical to 021", prefixes=[5])

print("\n\n############ CLAIM: king-root recapture illegal for a non-flying-general reason ############")
probe("A probe row 8: second attacker covers the flight square",
      "7/3k3/3c3/6R/4N2/7/2K4 w - - 0 1", M8("g4g5","d5d4","g5g4","d4d5"),
      note="A claims under-detection")
probe("B mx-chs-023: white horse b4 covers c6",
      "2k4/4R2/2c4/1N5/7/7/3K3 w - - 0 1", M8("e6e5","c5c6","e5e6","c6c5"),
      note="B claims the same under-detection")
probe("B mx-chs-009 control (no horse)",
      "2k4/4R2/2c4/7/7/7/3K3 w - - 0 1", M8("e6e5","c5c6","e5e6","c6c5"))
probe("B mx-chs-008 (flying general voids king recapture)",
      "2k4/4R2/2c4/7/7/7/2K4 w - - 0 1", M8("e6e5","c5c6","e5e6","c6c5"))

print("\n\n############ CLAIM: mutual perpetual check IS constructible (B mx-mix-001) ############")
probe("B mx-mix-001 mutual perpetual check",
      "3c3/7/2k3C/3n3/4N2/7/3K3 w - - 0 1", M8("e3d5","d4f5","d5e3","f5d4"),
      variants=(MX, BUILTIN))
probe("B mx-chk-003 (delete black cannon): White alone checks",
      "7/7/2k3C/3n3/4N2/7/3K3 w - - 0 1", M8("e3d5","d4f5","d5e3","f5d4"),
      variants=(MX, BUILTIN))
probe("B mx-chk-004 (delete white cannon): Black alone checks",
      "3c3/7/2k4/3n3/4N2/7/3K3 w - - 0 1", M8("e3d5","d4f5","d5e3","f5d4"),
      variants=(MX, BUILTIN))

print("\n\n############ CLAIM: check-over-chase mixed IS constructible (B mx-mix-004) ############")
probe("B mx-mix-004 check outranks chase",
      "3k3/7/1r3N1/7/7/2K4/3C3 w - - 0 1", M8("f5d6","b5d5","d6f5","d5b5"),
      variants=(MX, BUILTIN))
probe("B mx-chs-024 (delete white cannon): Black's chase alone",
      "3k3/7/1r3N1/7/7/2K4/7 w - - 0 1", M8("f5d6","b5d5","d6f5","d5b5"),
      variants=(MX, BUILTIN))

print("\n\n############ CLAIM: mutual perpetual chase ############")
probe("A mx-chs-020 mutual chase",
      "2k2r1/7/1cN1R2/7/2r1nC1/7/1R2K2 w - - 0 1", M8("c5b3","e3f5","b3c5","f5e3"),
      variants=(MX, BUILTIN))
probe("A white half", "2k4/7/1cN1R2/7/4n2/7/1R2K2 w - - 0 1", M8("c5b3","e3f5","b3c5","f5e3"))
probe("A black half", "2k2r1/7/2N4/7/2r1nC1/7/4K2 w - - 0 1", M8("c5b3","e3f5","b3c5","f5e3"))
probe("B mx-mix-002 mutual chase",
      "3k3/7/1NR4/3r3/1N2rn1/2KR3/5n1 w - - 0 1", M8("c5c3","e3e1","c3c5","e1e3"),
      variants=(MX, BUILTIN))
