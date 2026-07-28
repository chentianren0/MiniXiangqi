#!/usr/bin/env python3
"""Agent-B experiment batch 4: verify and minimize the mutual perpetual check."""
import importlib.util
import os

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("bprobe", os.path.join(HERE, "b-probe.py"))
B = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(B)
B.setup()
probe, pf, AXF = B.probe, B.pyffish, B.AXF
CYC = lambda c: list(c) * 2  # noqa: E731
MV = ["e3d5", "d4f5", "d5e3", "f5d4"]

RAW = "3c3/6r/2k3C/3n3/4N2/4R2/3K3 w - - 0 1"
MIN = "3c3/7/2k3C/3n3/4N2/7/3K3 w - - 0 1"

probe("V0 raw search hit (mutual perpetual check)", RAW, CYC(MV))
probe("V1 minimized: kings + two cannons + two horses only", MIN, CYC(MV),
      "expect draw at the third occurrence, nothing at the second")
print(B.board(MIN))

# every state must have the side to move in check
print("\nV1 check states along the cycle (side to move in check?):")
for i in range(9):
    f = pf.get_fen(AXF, MIN, MV * 2)  # placeholder
    f = pf.get_fen(AXF, MIN, (MV * 2)[:i])
    print("  ply %d  stm=%s in_check=%s  fen=%s"
          % (i, f.split()[1], pf.gives_check(AXF, MIN, (MV * 2)[:i]), f))

probe("V2 control: black's cannon removed -> only white perpetually checks",
      "7/7/2k3C/3n3/4N2/7/3K3 w - - 0 1", CYC(MV),
      "expect Red loses (stm loses at ply 8)")

probe("V3 control: white's cannon removed -> only black perpetually checks",
      "3c3/7/2k4/3n3/4N2/7/3K3 w - - 0 1", CYC(MV),
      "expect Black loses (stm wins at ply 8)")
