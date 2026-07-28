#!/usr/bin/env python3
"""Replay every fixture's movement content against the independent verifier model.

Usage: rv-check.py <fixture-dir> [id ...]

Checks, purely from the contract model and with no engine: every scripted move is
legal at its turn, the reached FEN and check state match, and where the fixture
asserts them, the exact legal set, the rejected moves and the applied probes.
Repetition / chase game_state is out of the model's scope and is not checked.
"""
import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import importlib.util

spec = importlib.util.spec_from_file_location(
    "rvmodel", pathlib.Path(__file__).resolve().parent / "rv-model.py")
M = importlib.util.module_from_spec(spec)
spec.loader.exec_module(M)


def replay(start, moves):
    fen = start
    for i, mv in enumerate(moves):
        legal = M.legal_moves(fen)
        if mv not in legal:
            raise AssertionError(f"move {i} {mv!r} illegal at {fen!r}")
        fen, _ = M.apply_fen(fen, mv)
    return fen


def check(fx, mut=()):
    fails = []
    fid = fx["id"]
    a = fx["assertions"]
    try:
        fen = replay(fx["start_fen"], fx["moves"])
    except AssertionError as e:
        return [f"{fid}: {e}"]

    if fen != a["result_fen"]:
        fails.append(f"{fid}: result_fen {fen!r} != {a['result_fen']!r}")
    board, stm, _, _ = M.parse_fen(fen)
    if M.in_check(board, stm) != a["in_check"]:
        fails.append(f"{fid}: in_check != {a['in_check']}")

    legal = M.legal_moves(fen, mut)
    if a.get("legal_moves") is not None and sorted(a["legal_moves"]) != legal:
        want = sorted(a["legal_moves"])
        fails.append(f"{fid}: legal set mismatch; model-only={sorted(set(legal)-set(want))} "
                     f"fixture-only={sorted(set(want)-set(legal))}")
    for rej in a.get("rejected_moves") or []:
        if rej in legal:
            fails.append(f"{fid}: rejected move {rej} is legal in the model")
    for probe in a.get("applied") or []:
        if probe["move"] not in legal:
            fails.append(f"{fid}: probe {probe['move']} is not legal in the model")
            continue
        got, chk = M.apply_fen(fen, probe["move"])
        if got != probe["result_fen"]:
            fails.append(f"{fid}: probe {probe['move']} -> {got!r} != {probe['result_fen']!r}")
        if chk != probe["in_check"]:
            fails.append(f"{fid}: probe {probe['move']} check {chk} != {probe['in_check']}")
    return fails


def main():
    d = pathlib.Path(sys.argv[1]).resolve()
    only = set(sys.argv[2:])
    fixtures = [json.loads(p.read_text()) for p in sorted(d.glob("mx-*.json"))]
    if only:
        fixtures = [f for f in fixtures if f["id"] in only]
    allf = []
    for fx in fixtures:
        f = check(fx)
        allf += f
        print(f"  [{'FAIL' if f else 'ok  '}] {fx['id']:<12} {fx['title'][:56]}")
    print(f"\n{len(allf)} disagreement(s) between the verifier model and {len(fixtures)} fixture(s)")
    for f in allf:
        print(f"    {f}")
    return 1 if allf else 0


if __name__ == "__main__":
    sys.exit(main())
