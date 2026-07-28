#!/usr/bin/env python3
"""Validate the contract model against the SIX already-approved movement fixtures and the
three ending fixtures, before using it to derive anything new.

Usage: python3 chariot-model-selfcheck.py <fixtures-dir>
"""
import json, pathlib, sys
import chariot_model_shim as M   # see loader below

def main():
    d = pathlib.Path(sys.argv[1])
    ids = ["mx-move-001", "mx-move-002", "mx-move-003", "mx-move-004", "mx-move-005",
           "mx-move-006", "mx-end-001", "mx-end-002", "mx-end-003"]
    bad = 0
    for fid in ids:
        fx = json.loads((d / f"{fid}.json").read_text())
        fen = fx["start_fen"]
        for mv in fx["moves"]:
            fen = M.push(fen, mv)
        a = fx["assertions"]
        probs = []
        if fen != a["result_fen"]:
            probs.append(f"result_fen {fen!r} != {a['result_fen']!r}")
        if M.in_check(fen) != a["in_check"]:
            probs.append(f"in_check {M.in_check(fen)} != {a['in_check']}")
        lm = M.legal_moves(fen)
        if a["legal_moves"] is not None and lm != sorted(a["legal_moves"]):
            probs.append("legal set: model=%s fixture=%s" % (lm, sorted(a["legal_moves"])))
        for rj in a["rejected_moves"] or []:
            if rj in lm:
                probs.append(f"rejected {rj} was legal in model")
        for pr in a["applied"] or []:
            got = M.push(fen, pr["move"])
            if got != pr["result_fen"]:
                probs.append(f"probe {pr['move']} -> {got!r} != {pr['result_fen']!r}")
            if M.in_check(got) != pr["in_check"]:
                probs.append(f"probe {pr['move']} check {M.in_check(got)} != {pr['in_check']}")
        print(("  [FAIL] " if probs else "  [ok  ] ") + fid)
        for p in probs:
            print("      " + p)
        bad += len(probs)
    print(f"\n{bad} disagreement(s) between the contract model and the approved fixtures")
    return 1 if bad else 0

if __name__ == "__main__":
    sys.exit(main())
