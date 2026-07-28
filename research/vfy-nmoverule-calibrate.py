#!/usr/bin/env python3
"""Calibrate the verifier's own rules implementation against the approved fixtures."""
import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import importlib.util

spec = importlib.util.spec_from_file_location(
    "vfyrules", pathlib.Path(__file__).resolve().parent / "vfy-nmoverule-rules.py")
R = importlib.util.module_from_spec(spec)
spec.loader.exec_module(R)


def replay(fx):
    pos = R.Pos.from_fen(fx["start_fen"])
    for mv in fx["moves"]:
        pos, _ = R.apply_move(pos, mv)
    return pos


def check(fx):
    fails = []
    fid = fx["id"]
    try:
        pos = replay(fx)
    except ValueError as e:
        return [f"{fid}: {e}"]
    a = fx["assertions"]
    if pos.fen() != a["result_fen"]:
        fails.append(f"{fid}: result_fen {pos.fen()!r} != {a['result_fen']!r}")
    if R.in_check(pos) != a["in_check"]:
        fails.append(f"{fid}: in_check {R.in_check(pos)} != {a['in_check']}")
    lm = R.legal_moves(pos)
    if a.get("legal_moves") is not None and sorted(a["legal_moves"]) != lm:
        fails.append(f"{fid}: legal set mismatch, mine={lm}")
    for rej in a.get("rejected_moves") or []:
        m = rej["move"] if isinstance(rej, dict) else rej
        if m in lm:
            fails.append(f"{fid}: rejected move {m} is legal in my implementation")
    for probe in a.get("applied") or []:
        if probe["move"] not in lm:
            fails.append(f"{fid}: probe {probe['move']} not legal in my implementation")
            continue
        nxt, _ = R.apply_move(pos, probe["move"])
        if nxt.fen() != probe["result_fen"]:
            fails.append(f"{fid}: probe {probe['move']} -> {nxt.fen()!r} != {probe['result_fen']!r}")
        if R.in_check(nxt) != probe["in_check"]:
            fails.append(f"{fid}: probe {probe['move']} check state mismatch")
    return fails


def main():
    d = pathlib.Path(sys.argv[1])
    fixtures = [json.loads(p.read_text()) for p in sorted(d.glob("mx-*.json"))]
    allf = []
    for fx in fixtures:
        f = check(fx)
        allf += f
        if f:
            for x in f:
                print("  " + x)
    print(f"{len(fixtures)} fixtures, {len(allf)} mismatches against my contract implementation")
    return 1 if allf else 0


if __name__ == "__main__":
    sys.exit(main())
