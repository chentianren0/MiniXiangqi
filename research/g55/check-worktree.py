#!/usr/bin/env python3
"""Run the approved MiniXiangqi rules fixtures against a built pyffish.

Usage:
    python3 engine-fixture-check.py <dir-containing-pyffish.so>

Checks every fixture in MiniXiangqi/fixtures/rules/ against the target variant
(AXF chasing, no move-count rule, soldiers exempt as chase targets) and, for
comparison, against the same variant without the soldier exemption.

Exit status 0 means every fixture matched its normative expectation under the
target variant.
"""
import json
import pathlib
import sys

MATE = 32000

TARGET = "mxq_target"
CONTROL = "mxq_control"

INI = f"""
[{TARGET}:minixiangqi]
chasingRule = axf
nMoveRule = 0
promotedSoldiersChaseable = false

[{CONTROL}:minixiangqi]
chasingRule = axf
nMoveRule = 0
"""

FIXTURES = pathlib.Path("/Users/tianren/coding/minixiangqi/fx-patch-gated") / "fixtures" / "rules"


def side_to_move(fen):
    return fen.split()[1]


def expected_optional_value(state, fen):
    """Engine value for a repetition outcome, from the side-to-move perspective."""
    if state == "claimable-draw" or state == "draw":
        return 0
    stm_is_red = side_to_move(fen) == "w"
    red_wins = state == "red-wins"
    # Side to move wins -> +MATE, side to move loses -> -MATE
    return MATE if (red_wins == stm_is_red) else -MATE


def check_fixture(sf, variant, fx):
    """Return a list of failure strings for one fixture under one variant."""
    fails = []
    fid = fx["id"]
    start, moves = fx["start_fen"], fx["moves"]
    a = fx["assertions"]

    # every scripted move must be legal at its turn
    for i in range(len(moves)):
        legal = sf.legal_moves(variant, start, moves[:i])
        if moves[i] not in legal:
            fails.append(f"{fid}: move {i} {moves[i]!r} not legal")
            return fails

    final = sf.get_fen(variant, start, moves)
    if final != a["result_fen"]:
        fails.append(f"{fid}: result_fen {final!r} != {a['result_fen']!r}")

    if sf.gives_check(variant, start, moves) != a["in_check"]:
        fails.append(f"{fid}: in_check != {a['in_check']}")

    legal = sf.legal_moves(variant, start, moves)
    if a.get("legal_moves") is not None:
        if sorted(legal) != sorted(a["legal_moves"]):
            fails.append(f"{fid}: legal set mismatch: got {sorted(legal)}")
    for rejected in a.get("rejected_moves") or []:
        if rejected in legal:
            fails.append(f"{fid}: rejected move {rejected!r} was legal")
    for probe in a.get("applied") or []:
        got = sf.get_fen(variant, start, moves + [probe["move"]])
        if got != probe["result_fen"]:
            fails.append(f"{fid}: probe {probe['move']} -> {got!r} != {probe['result_fen']!r}")
        if sf.gives_check(variant, start, moves + [probe["move"]]) != probe["in_check"]:
            fails.append(f"{fid}: probe {probe['move']} check state mismatch")

    gs = a["game_state"]
    state, reason = gs["state"], gs.get("reason")
    ended, value = sf.is_optional_game_end(variant, start, moves)

    if reason in ("checkmate", "stalemate"):
        if legal:
            fails.append(f"{fid}: expected no legal moves for {reason}, got {len(legal)}")
        else:
            # game_result is loss for the side to move
            if sf.game_result(variant, start, moves) != -MATE:
                fails.append(f"{fid}: game_result != -MATE for {reason}")
            stm_is_red = side_to_move(final) == "w"
            if (state == "red-wins") == stm_is_red:
                fails.append(f"{fid}: {state} contradicts side to move {side_to_move(final)}")
    elif state == "ongoing":
        if ended:
            fails.append(f"{fid}: expected ongoing, engine reported optional end value {value}")
    else:
        want = expected_optional_value(state, final)
        if not ended:
            fails.append(f"{fid}: expected {state}/{reason}, engine reported no optional end")
        elif value != want:
            fails.append(f"{fid}: expected value {want} for {state}/{reason}, got {value}")

    # boundary: one repetition cycle earlier must not yet be terminal or claimable
    b = fx.get("boundary")
    if b:
        prefix = moves[: b["prefix_len"]]
        ended_early, _ = sf.is_optional_game_end(variant, start, prefix)
        if ended_early:
            fails.append(f"{fid}: boundary prefix ({b['prefix_len']} plies) already ended")

    return fails


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    sys.path.insert(0, sys.argv[1])
    import pyffish as sf

    print(f"engine: {sf.info()}")
    sf.load_variant_config(INI)

    fixtures = [json.loads(p.read_text()) for p in sorted(FIXTURES.glob("mx-*.json"))]
    print(f"fixtures: {len(fixtures)} from {FIXTURES}\n")

    target_fails, control_fails = [], []
    for fx in fixtures:
        tf = check_fixture(sf, TARGET, fx)
        cf = check_fixture(sf, CONTROL, fx)
        target_fails += tf
        control_fails += cf
        mark = "FAIL" if tf else "ok  "
        note = "" if bool(tf) == bool(cf) else ("  <-- differs from control" if not tf else "  <-- control passes")
        print(f"  [{mark}] {fx['id']:<12} {fx['title'][:58]}{note}")

    print(f"\ntarget variant  (soldiers exempt):     {len(target_fails)} failure(s)")
    for f in target_fails:
        print(f"    {f}")
    print(f"control variant (soldiers chaseable): {len(control_fails)} failure(s)")
    for f in control_fails:
        print(f"    {f}")

    return 1 if target_fails else 0


if __name__ == "__main__":
    sys.exit(main())
