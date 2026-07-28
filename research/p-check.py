#!/usr/bin/env python3
"""Replay the fx-protection worktree's rules fixtures against the r-scratch pyffish build.

Reuses engine-fixture-check.py's checker verbatim, but over a chosen fixture directory,
and adds a per-ply trace plus an explicit boundary-state check.
"""
import importlib.util
import json
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
SO_DIR = HERE / "r-scratch"
FIXDIR = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else (
    HERE.parent / "fx-protection" / "fixtures" / "rules"
)

spec = importlib.util.spec_from_file_location("efc", HERE / "engine-fixture-check.py")
efc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(efc)

sys.path.insert(0, str(SO_DIR))
import pyffish as sf  # noqa: E402

print(f"engine: {sf.info()}")
sf.load_variant_config(efc.INI)
V = efc.TARGET

NEW = {f"mx-chs-{n:03d}" for n in range(5, 14)}
paths = sorted(p for p in FIXDIR.glob("mx-*.json") if p.stem in NEW)
print(f"fixtures: {len(paths)} from {FIXDIR}\n")

fails = []
for p in paths:
    fx = json.loads(p.read_text())
    # byte-exact serialization check
    if p.read_text() != json.dumps(fx, indent=2, ensure_ascii=False) + "\n":
        fails.append(f"{fx['id']}: serialization not canonical")
    f = efc.check_fixture(sf, V, fx)
    # explicit boundary state: at prefix_len the outcome must not exist yet
    b = fx["boundary"]
    ended, val = sf.is_optional_game_end(V, fx["start_fen"], fx["moves"][: b["prefix_len"]])
    if ended:
        f.append(f"{fx['id']}: boundary prefix already ended ({val})")
    # per-ply optional-end trace, to see exactly where the outcome attaches
    trace = []
    for i in range(len(fx["moves"]) + 1):
        e, v = sf.is_optional_game_end(V, fx["start_fen"], fx["moves"][:i])
        trace.append("." if not e else ("=" if v == 0 else ("+" if v > 0 else "-")))
    fails += f
    mark = "FAIL" if f else "ok  "
    gs = fx["assertions"]["game_state"]
    print(f"  [{mark}] {fx['id']}  {gs['state']:<15} {gs['reason']:<22} ply-trace {''.join(trace)}")

print()
if fails:
    print(f"{len(fails)} failure(s):")
    for x in fails:
        print(f"    {x}")
else:
    print("all new fixtures agree with the engine under the target variant")
sys.exit(1 if fails else 0)
