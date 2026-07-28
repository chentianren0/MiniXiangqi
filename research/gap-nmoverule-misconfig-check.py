#!/usr/bin/env python3
"""Regression control for the nMoveRule fixtures.

Runs the full fixture set twice with engine-fixture-check.py's checker:

  mxq_target   — the app's target variant, with nMoveRule = 0 as the rules
                 contract requires.
  mxq_nmove50  — identical except that `nMoveRule = 0` is omitted, so the
                 variant keeps Fairy-Stockfish's inherited default of 50. This
                 is the shipping mistake docs/xiangqi-rules.md warns about.

A fixture that closes the nMoveRule gap must pass under mxq_target and fail
under mxq_nmove50.

Usage: python3 gap-nmoverule-misconfig-check.py <dir-with-pyffish.so> <fixture-dir>
"""
import importlib.util
import json
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent

TARGET = "mxq_target"
MISCONFIG = "mxq_nmove50"

INI = f"""
[{TARGET}:minixiangqi]
chasingRule = axf
nMoveRule = 0
promotedSoldiersChaseable = false

[{MISCONFIG}:minixiangqi]
chasingRule = axf
promotedSoldiersChaseable = false
"""


def load_checker():
    spec = importlib.util.spec_from_file_location(
        "efc", HERE / "engine-fixture-check.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def main():
    sys.path.insert(0, sys.argv[1])
    import pyffish as sf

    efc = load_checker()
    print(f"engine: {sf.info()}")
    sf.load_variant_config(INI)

    fixture_dir = pathlib.Path(sys.argv[2]).resolve()
    fixtures = [json.loads(p.read_text()) for p in sorted(fixture_dir.glob("mx-*.json"))]
    print(f"fixtures: {len(fixtures)} from {fixture_dir}\n")
    print(f"{'fixture':<13} {'target(nMoveRule=0)':<21} {'misconfig(nMoveRule=50)'}")

    detectors = []
    for fx in fixtures:
        t = efc.check_fixture(sf, TARGET, fx)
        m = efc.check_fixture(sf, MISCONFIG, fx)
        detects = (not t) and bool(m)
        if detects:
            detectors.append(fx["id"])
        print(f"{fx['id']:<13} {'pass' if not t else 'FAIL':<21} "
              f"{'pass' if not m else 'FAIL'}"
              f"{'   <-- detects the misconfiguration' if detects else ''}")
        for f in m:
            print(f"                  misconfig detail: {f}")

    print(f"\nfixtures that detect a variant shipped without nMoveRule = 0: "
          f"{detectors or 'NONE'}")
    return 0 if detectors else 1


if __name__ == "__main__":
    sys.exit(main())
