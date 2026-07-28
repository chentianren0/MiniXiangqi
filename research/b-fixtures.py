#!/usr/bin/env python3
"""Agent-B: emit exact fixture field values (round-tripped FENs, result FEN,
in_check, boundary observation, engine result) for every proposed fixture."""
import importlib.util
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("bprobe", os.path.join(HERE, "b-probe.py"))
B = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(B)
B.setup()
pf, AXF, BUILTIN = B.pyffish, B.AXF, B.BUILTIN

C = lambda c: list(c) * 2  # noqa: E731
SH = ["b3a3", "a5b5", "a3b3", "b5a5"]
XR = ["e6e5", "c5c6", "e5e6", "c6c5"]
HS = ["a4c3", "d5c5", "c3a4", "c5d5"]
RR = ["a4a5", "d5d4", "a5a4", "d4d5"]
DC = ["d3c5", "e7e6", "c5d3", "e6e7"]
MU = ["c5c3", "e3e1", "c3c5", "e1e3"]
MC = ["e3d5", "d4f5", "d5e3", "f5d4"]
AB = ["c4d4", "d7c7", "d4c4", "c7d7"]
TT = ["c4d4", "e7e6", "d4c4", "e6e7"]
PA = ["c4c3", "e3e4", "c3c4", "e4e3"]
FP = ["a5a4", "c4c5", "a4a5", "c5c4"]
NN = ["a5b5", "a3b3", "b5a5", "b3a3"]
MX = ["f5d6", "b5d5", "d6f5", "d5b5"]

FX = [
    ("mx-chs-005", "chs", "4k2/7/c3r2/7/1R5/7/2K1R2 w - - 0 1", C(SH), 4),
    ("mx-chs-006", "chs", "3k3/4R2/2c4/7/7/7/2K4 w - - 0 1", C(XR), 4),
    ("mx-chs-007", "chs", "3k3/4R2/2c3r/7/7/7/2K4 w - - 0 1", C(XR), 4),
    ("mx-chs-008", "chs", "2k4/4R2/2c4/7/7/7/2K4 w - - 0 1", C(XR), 4),
    ("mx-chs-009", "chs", "2k4/4R2/2c4/7/7/7/3K3 w - - 0 1", C(XR), 4),
    ("mx-chs-010", "chs", "3k3/1p2R2/2c4/7/7/7/2K4 w - - 0 1", C(XR), 4),
    ("mx-chs-011", "chs", "3k3/7/3r2r/N6/7/7/4K2 w - - 0 1", C(HS), 4),
    ("mx-chs-012", "chs", "3k3/7/3c2r/N6/7/7/4K2 w - - 0 1", C(HS), 4),
    ("mx-chs-013", "chs", "3k3/7/3r3/R6/7/7/2K4 w - - 0 1", C(RR), 4),
    ("mx-chs-014", "chs", "3k3/7/3r3/R6/7/7/2KR3 w - - 0 1", C(RR), 4),
    ("mx-chs-015", "chs", "4k2/7/7/c6/1P5/7/2K4 w - - 0 1",
     C(["b3a3", "a4b4", "a3b3", "b4a4"]), 4),
    ("mx-chs-016", "chs", "4k2/7/7/7/2c4/2K4/7 w - - 0 1",
     C(["c2d2", "c3d3", "d2c2", "d3c3"]), 4),
    ("mx-chs-017", "chs", "4k2/7/R2n3/7/3N3/7/2KR3 w - - 0 1", C(DC), 4),
    ("mx-chs-018", "chs", "4k2/3n3/2c4/2R4/7/7/3K3 w - - 0 1", C(TT), 4),
    ("mx-chs-019", "chs", "2r1k2/7/7/2R4/4c2/7/2K4 w - - 0 1", C(PA), 4),
    ("mx-chs-020", "chs", "2k4/7/R6/2r4/2N4/7/2K4 w - - 0 1", C(FP), 4),
    ("mx-chs-021", "chs", "4k2/7/c6/7/7/7/R1K4 w - - 0 1", ["a1a3"] + C(NN), 5),
    ("mx-chs-022", "chs", "4k2/7/c6/7/1R5/7/2K4 w - - 0 1", ["b3a3"] + C(NN), 5),
    ("mx-chs-023", "chs", "2k4/4R2/2c4/1N5/7/7/3K3 w - - 0 1", C(XR), 4),
    ("mx-chk-003", "chk", "7/7/2k3C/3n3/4N2/7/3K3 w - - 0 1", C(MC), 4),
    ("mx-chk-004", "chk", "3c3/7/2k4/3n3/4N2/7/3K3 w - - 0 1", C(MC), 4),
    ("mx-mix-001", "mix", "3c3/7/2k3C/3n3/4N2/7/3K3 w - - 0 1", C(MC), 4),
    ("mx-mix-002", "mix", "3k3/7/1NR4/3r3/1N2rn1/2KR3/5n1 w - - 0 1", C(MU), 4),
    ("mx-mix-003", "mix", "3k3/7/2c4/2R4/7/7/4K2 w - - 0 1", C(AB), 4),
    ("mx-mix-004", "mix", "3k3/7/1r3N1/7/7/2K4/3C3 w - - 0 1", C(MX), 4),
    ("mx-chs-024", "chs", "3k3/7/1r3N1/7/7/2K4/7 w - - 0 1", C(MX), 4),
]

out = []
for fid, area, fen, moves, bl in FX:
    rt = pf.get_fen(AXF, fen, [])
    ok = all(m in pf.legal_moves(AXF, fen, moves[:i]) for i, m in enumerate(moves))
    rec = {
        "id": fid, "area": area, "start_fen": fen,
        "start_fen_roundtrip_ok": rt == fen, "roundtrip": rt,
        "all_moves_legal": ok, "n_moves": len(moves),
        "moves": moves,
        "result_fen": pf.get_fen(AXF, fen, moves),
        "in_check": pf.gives_check(AXF, fen, moves),
        "boundary_prefix_len": bl,
        "boundary_axf": pf.is_optional_game_end(AXF, fen, moves[:bl])[0],
        "final_axf": pf.is_optional_game_end(AXF, fen, moves),
        "final_builtin": pf.is_optional_game_end(BUILTIN, fen, moves),
    }
    out.append(rec)
    print("%-12s rt=%-5s legal=%-5s bnd_ended=%-5s axf=%-14s builtin=%-14s %s"
          % (fid, rec["start_fen_roundtrip_ok"], ok, rec["boundary_axf"],
             rec["final_axf"], rec["final_builtin"], rec["result_fen"]))
print()
print(json.dumps([{k: v for k, v in r.items() if k != "moves"} for r in out])[:0] or "", end="")
