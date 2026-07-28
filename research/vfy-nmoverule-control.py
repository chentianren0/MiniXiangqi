#!/usr/bin/env python3
"""Verifier-owned misconfiguration control.

Runs every fixture under two engine variants that differ ONLY by the presence of
`nMoveRule = 0`, using engine-fixture-check.py's own check_fixture so the pass
criteria are identical. A fixture that guards the absent move-count draw must
pass the first and fail the second; every other fixture is expected to be blind.
"""
import importlib.util
import json
import pathlib
import sys

here = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, sys.argv[1])
import pyffish as sf

spec = importlib.util.spec_from_file_location("efc", here / "engine-fixture-check.py")
efc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(efc)

GOOD = "mxq_good"
BAD = "mxq_bad"
INI = f"""
[{GOOD}:minixiangqi]
chasingRule = axf
nMoveRule = 0
promotedSoldiersChaseable = false

[{BAD}:minixiangqi]
chasingRule = axf
promotedSoldiersChaseable = false
"""

print(f"engine: {sf.info()}")
sf.load_variant_config(INI)

d = pathlib.Path(sys.argv[2])
fixtures = [json.loads(p.read_text()) for p in sorted(d.glob("mx-*.json"))]
detectors, blind, broken = [], [], []
for fx in fixtures:
    g = efc.check_fixture(sf, GOOD, fx)
    b = efc.check_fixture(sf, BAD, fx)
    tag = f"{'pass' if not g else 'FAIL'} / {'pass' if not b else 'FAIL'}"
    if not g and b:
        detectors.append(fx["id"])
        print(f"  {fx['id']:<12} {tag}   <-- DETECTS the missing nMoveRule = 0")
        for x in b:
            print(f"       {x}")
    elif not g and not b:
        blind.append(fx["id"])
    else:
        broken.append(fx["id"])

print(f"\ndetectors: {detectors}")
print(f"blind to the misconfiguration: {len(blind)} fixtures")
print(f"failing even under the correct variant: {broken}")
