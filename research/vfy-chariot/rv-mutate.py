#!/usr/bin/env python3
"""Mutation test: does each fixture actually detect a broken chariot?

Injects three chariot defects into the verifier model and reports, for each
mutant, which fixtures still pass (blind to the defect) and which fail (detect
it).  A fixture that passes under every mutant does not guard chariot movement.

Usage: rv-mutate.py <fixture-dir-with-new> <fixture-dir-base-only>
"""
import importlib.util
import json
import pathlib
import sys

here = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("rvmodel", here / "rv-model.py")
M = importlib.util.module_from_spec(spec)
spec.loader.exec_module(M)
spec2 = importlib.util.spec_from_file_location("rvcheck", here / "rv-check.py")

MUTANTS = {
    "jump       (slides through the first piece)      ": ("jump",),
    "jump_own   (slides through its OWN pieces only)  ": ("jump_own",),
    "jump_enemy (slides through ENEMY pieces only)    ": ("jump_enemy",),
    "diagonal   (also moves diagonally)               ": ("diagonal",),
    "range2     (at most two squares per move)        ": ("range3",),
    "capture_own(may capture its own pieces)          ": ("capture_own",),
    "no_capture (slides but never captures)           ": ("no_capture",),
    "late1      (ray stops ONE square past the blocker)": ("late1",),
    "no_edge    (cannot land on file a/g or rank 1/7)  ": ("no_edge",),
    "cannon_like(needs exactly one screen to capture)  ": ("cannon_like",),
}


def fixture_fails(fx):
    """Reuse rv-check's per-fixture logic under the currently installed mutation."""
    fails = []
    fid, a = fx["id"], fx["assertions"]
    fen = fx["start_fen"]
    for i, mv in enumerate(fx["moves"]):
        if mv not in M.legal_moves(fen):
            return [f"{fid}: scripted move {i} {mv} illegal"]
        fen, _ = M.apply_fen(fen, mv)
    if fen != a["result_fen"]:
        fails.append(f"{fid}: result_fen")
    board, stm, _, _ = M.parse_fen(fen)
    if M.in_check(board, stm) != a["in_check"]:
        fails.append(f"{fid}: in_check")
    legal = M.legal_moves(fen)
    if a.get("legal_moves") is not None and sorted(a["legal_moves"]) != legal:
        extra = sorted(set(legal) - set(a["legal_moves"]))
        missing = sorted(set(a["legal_moves"]) - set(legal))
        fails.append(f"{fid}: legal set (+{extra} -{missing})")
    for rej in a.get("rejected_moves") or []:
        if rej in legal:
            fails.append(f"{fid}: rejected {rej} became legal")
    for probe in a.get("applied") or []:
        if probe["move"] not in legal:
            fails.append(f"{fid}: probe {probe['move']} illegal")
            continue
        got, chk = M.apply_fen(fen, probe["move"])
        if got != probe["result_fen"] or chk != probe["in_check"]:
            fails.append(f"{fid}: probe {probe['move']}")
    return fails


def load(d):
    return [json.loads(p.read_text()) for p in sorted(pathlib.Path(d).glob("mx-*.json"))]


def main():
    new = load(sys.argv[1])
    base = {fx["id"] for fx in load(sys.argv[2])}
    added = [fx["id"] for fx in new if fx["id"] not in base]
    print(f"base branch: {len(base)} fixtures; added by this branch: {added}\n")

    for name, mut in MUTANTS.items():
        M.MUT = mut
        detect_base, detect_new = [], []
        for fx in new:
            try:
                bad = fixture_fails(fx)
            except AssertionError as e:      # mutant produced an incoherent position
                bad = [f"{fx['id']}: {e}"]
            if bad:
                (detect_new if fx["id"] in added else detect_base).append(fx["id"])
        print(f"mutant {name}")
        print(f"    detected by base-branch fixtures : {detect_base or 'NONE'}")
        print(f"    detected by the new fixtures     : {detect_new or 'NONE'}")
    M.MUT = ()

    # sanity: with no mutation nothing must fail
    assert not [f for fx in new for f in fixture_fails(fx)], "unmutated model disagrees"
    print("\nunmutated model: 0 disagreements (control)")


if __name__ == "__main__":
    sys.exit(main())
