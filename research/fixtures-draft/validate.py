#!/usr/bin/env python3
"""Validate the draft Mini Xiangqi conformance fixtures against pyffish.

Runs every mx-*.json fixture in this directory through the previously built
pyffish 0.0.89 extension (discussion-drafts/evidence/pyffish-build) twice:

  1. under the built-in `minixiangqi` variant, and
  2. under the AXF child `minixiangqiaxf` loaded from
     minixiangqiaxf-validation.ini (chasingRule = axf, nMoveRule = 0).

For each fixture and variant it verifies/records:
  - validate_fen on the start FEN;
  - that every move in `moves` is legal at its turn;
  - that the two variants produce identical legal-move sets at every ply;
  - the final FEN, check state, and (if asserted) the exact legal-move set,
    rejected moves, and one-move `applied` transitions;
  - game_result when the asserted legal-move set is empty (mate/stalemate);
  - is_immediate_game_end / is_optional_game_end at the final position and,
    for repetition fixtures, at the boundary prefix one cycle earlier.

The script never asserts engine agreement with the fixture's normative
game_state: it prints raw engine values so the draft document can classify
each fixture as ENGINE-AGREES / ENGINE-DIVERGES / NOT-ENGINE-TESTABLE.

Run from this directory:  python3 validate.py [--json out.json]
"""

import glob
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PYFFISH_DIR = os.path.join(HERE, "..", "evidence", "pyffish-build")
INI = os.path.join(HERE, "minixiangqiaxf-validation.ini")

sys.path.insert(0, PYFFISH_DIR)
import pyffish  # noqa: E402

BUILTIN = "minixiangqi"
AXF = "minixiangqiaxf"
VALUE_MATE = 32000


def load_axf_child():
    with open(INI) as fh:
        config = fh.read()
    pyffish.load_variant_config(config)
    assert AXF in pyffish.variants(), "AXF child variant did not register"


def check(label, ok, detail, out):
    out.append({"check": label, "ok": bool(ok), "detail": detail})
    return ok


def run_fixture(fx, variant, out):
    fen = fx["start_fen"]
    moves = fx["moves"]
    a = fx["assertions"]

    ok_fen = pyffish.validate_fen(fen, variant)
    check("validate_fen", ok_fen == pyffish.FEN_OK, {"returned": ok_fen}, out)

    # Every move legal at its turn; both variants agree on every legal set.
    for i, mv in enumerate(moves):
        legal = pyffish.legal_moves(variant, fen, moves[:i])
        if not check("move_legal[%d]=%s" % (i, mv), mv in legal,
                     {"legal_count": len(legal)}, out):
            return  # later observations would be meaningless

    final_legal = sorted(pyffish.legal_moves(variant, fen, moves))
    final_fen = pyffish.get_fen(variant, fen, moves)
    in_check = pyffish.gives_check(variant, fen, moves)

    check("result_fen", final_fen == a["result_fen"],
          {"engine": final_fen, "fixture": a["result_fen"]}, out)
    check("in_check", in_check == a["in_check"], {"engine": in_check}, out)

    if a["legal_moves"] is not None:
        want = sorted(a["legal_moves"])
        check("legal_moves_exact", final_legal == want,
              {"engine_only": sorted(set(final_legal) - set(want)),
               "fixture_only": sorted(set(want) - set(final_legal)),
               "count": len(final_legal)}, out)
    if a["rejected_moves"]:
        bad = [m for m in a["rejected_moves"] if m in final_legal]
        check("rejected_moves_absent", not bad, {"wrongly_legal": bad}, out)

    for ap in a["applied"] or []:
        mv = ap["move"]
        if not check("applied_legal:%s" % mv, mv in final_legal, {}, out):
            continue
        got = pyffish.get_fen(variant, fen, moves + [mv])
        check("applied_fen:%s" % mv, got == ap["result_fen"],
              {"engine": got, "fixture": ap["result_fen"]}, out)
        chk2 = pyffish.gives_check(variant, fen, moves + [mv])
        check("applied_check:%s" % mv, chk2 == ap["in_check"],
              {"engine": chk2}, out)

    # Raw terminal observations (recorded, not asserted).
    obs = {
        "is_immediate_game_end": pyffish.is_immediate_game_end(variant, fen, moves),
        "is_optional_game_end": pyffish.is_optional_game_end(variant, fen, moves),
    }
    if a["legal_moves"] == []:
        # game_result is only meaningful when there is no legal move.
        obs["game_result"] = pyffish.game_result(variant, fen, moves)
    out.append({"check": "terminal_observations", "ok": None, "detail": obs})

    if fx.get("boundary"):
        n = fx["boundary"]["prefix_len"]
        pre = moves[:n]
        bobs = {
            "prefix_len": n,
            "is_optional_game_end": pyffish.is_optional_game_end(variant, fen, pre),
            "is_immediate_game_end": pyffish.is_immediate_game_end(variant, fen, pre),
        }
        # The boundary prefix must NOT already be an optional end.
        check("boundary_not_yet_ended", not bobs["is_optional_game_end"][0], bobs, out)


def cross_variant_legal_sets(fx, out):
    fen, moves = fx["start_fen"], fx["moves"]
    for i in range(len(moves) + 1):
        lb = sorted(pyffish.legal_moves(BUILTIN, fen, moves[:i]))
        la = sorted(pyffish.legal_moves(AXF, fen, moves[:i]))
        if lb != la:
            check("variants_same_legal[%d]" % i, False,
                  {"builtin_only": sorted(set(lb) - set(la)),
                   "axf_only": sorted(set(la) - set(lb))}, out)
            return
    check("variants_same_legal", True, {"plies": len(moves) + 1}, out)


def freeze_probes():
    """Empirical freeze-fact probes recorded alongside the fixtures."""
    p = {}
    p["pyffish_version"] = pyffish.version()
    p["engine_info"] = pyffish.info()
    p["start_fen_builtin"] = pyffish.start_fen(BUILTIN)
    p["start_fen_axf_child"] = pyffish.start_fen(AXF)

    start = p["start_fen_builtin"]
    p["start_legal_moves"] = sorted(pyffish.legal_moves(BUILTIN, start, []))
    p["start_fen_roundtrip"] = pyffish.get_fen(BUILTIN, start, [])

    # Halfmove clock: soldier moves must NOT reset it; captures must.
    p["halfmove_after_soldier_move"] = pyffish.get_fen(BUILTIN, start, ["d2d3"])
    p["halfmove_capture_seq"] = ["d2d3", "d6d5", "d3d4", "d5d4"]
    p["halfmove_after_capture"] = pyffish.get_fen(BUILTIN, start, p["halfmove_capture_seq"])

    # Soldier on the last rank: still moves sideways only, no promotion suffix.
    lastrank_fen = "3k3/P6/7/7/7/7/2K4 w - - 0 1"
    p["soldier_pre_last_rank_moves"] = sorted(pyffish.legal_moves(BUILTIN, lastrank_fen, []))
    p["soldier_last_rank_fen"] = pyffish.get_fen(BUILTIN, lastrank_fen, ["a6a7"])
    p["soldier_on_last_rank_black_reply_then_white_moves"] = sorted(
        pyffish.legal_moves(BUILTIN, lastrank_fen, ["a6a7", "d7d6"]))

    # Move-string format scan over every fixture position and ply.
    return p


def main():
    load_axf_child()
    fixtures = []
    for path in sorted(glob.glob(os.path.join(HERE, "mx-*.json"))):
        with open(path) as fh:
            fixtures.append(json.load(fh))
    order = {"move": 0, "end": 1, "rep": 2, "chk": 3, "chs": 4}
    fixtures.sort(key=lambda f: (order.get(f["area"], 9), f["id"]))

    report = {"probes": freeze_probes(), "fixtures": []}

    import re
    move_re = re.compile(r"^[a-g][1-7][a-g][1-7]$")
    bad_move_strings = set()

    for fx in fixtures:
        entry = {"id": fx["id"], "results": {}}
        for variant in (BUILTIN, AXF):
            out = []
            run_fixture(fx, variant, out)
            entry["results"][variant] = out
        xo = []
        cross_variant_legal_sets(fx, xo)
        entry["cross_variant"] = xo
        report["fixtures"].append(entry)

        for i in range(len(fx["moves"]) + 1):
            for m in pyffish.legal_moves(BUILTIN, fx["start_fen"], fx["moves"][:i]):
                if not move_re.match(m):
                    bad_move_strings.add(m)

    report["probes"]["nonconforming_move_strings"] = sorted(bad_move_strings)

    # Human-readable summary.
    fails = 0
    for e in report["fixtures"]:
        for variant in (BUILTIN, AXF):
            for c in e["results"][variant]:
                if c["ok"] is False:
                    fails += 1
                    print("FAIL %-12s %-14s %-28s %s" %
                          (e["id"], variant, c["check"], json.dumps(c["detail"])))
        for c in e["cross_variant"]:
            if c["ok"] is False:
                fails += 1
                print("FAIL %-12s %-14s %-28s %s" %
                      (e["id"], "cross", c["check"], json.dumps(c["detail"])))
    print("checks failed:", fails)

    for e in report["fixtures"]:
        for variant in (BUILTIN, AXF):
            for c in e["results"][variant]:
                if c["check"] == "terminal_observations":
                    print("OBS  %-12s %-14s %s" % (e["id"], variant, json.dumps(c["detail"])))
                if c["check"] == "boundary_not_yet_ended":
                    print("BND  %-12s %-14s ok=%s %s" %
                          (e["id"], variant, c["ok"], json.dumps(c["detail"])))

    if "--json" in sys.argv:
        out_path = sys.argv[sys.argv.index("--json") + 1]
        with open(out_path, "w") as fh:
            json.dump(report, fh, indent=2)
        print("full report:", out_path)

    print("probes:", json.dumps(report["probes"], indent=2))
    return 1 if fails else 0


if __name__ == "__main__":
    raise SystemExit(main())
