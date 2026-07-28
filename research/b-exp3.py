#!/usr/bin/env python3
"""Agent-B experiment batch 3: window artifact control, soldier defenders,
and the flying-general false-pin false positive."""
import importlib.util
import os

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("bprobe", os.path.join(HERE, "b-probe.py"))
B = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(B)
B.setup()
probe = B.probe
CYC = lambda c: list(c) * 2  # noqa: E731

probe("N3 control for N1: the move creating occurrence 1 DOES chase",
      "4k2/7/c6/7/1R5/7/2K4 w - - 0 1",
      ["b3a3"] + CYC(["a5b5", "a3b3", "b5a5", "b3a3"]),
      "identical three occurrences and identical chase; only the ply-1 move differs from N1",
      prefixes=(5, 9))

probe("R1 target square defended by a black SOLDIER",
      "3k3/1p2R2/2c4/7/7/7/2K4 w - - 0 1",
      CYC(["e6e5", "c5c6", "e5e6", "c6c5"]),
      "soldier b6 defends c6; C0 without it is a violation -> soldiers count as roots")

probe("S1 flying-general FALSE pin: Nc3 blocks the file, so rc4/c5 is not really pinned",
      "2k4/7/R6/2r4/2N4/7/2K4 w - - 0 1",
      CYC(["a5a4", "c4c5", "a4a5", "c5c4"]),
      "rook-vs-rook would be symmetric; engine bypasses that because it marks rc4 pinned")

probe("S2 control: white king off the c-file, so no flying-general pin at all",
      "2k4/7/R6/2r4/2N4/7/3K3 w - - 0 1",
      CYC(["a5a4", "c4c5", "a4a5", "c5c4"]),
      "expect draw (symmetric rook attack)")

# is the S1 target genuinely free to leave the c-file?
import sys  # noqa: E402
mv = B.legal("2k4/7/R6/2r4/2N4/7/2K4 w - - 0 1", ["a5a4"])
print("\nS1 sanity: black moves available after a5a4 for the c4 rook:",
      sorted(m for m in mv if m.startswith("c4")))
