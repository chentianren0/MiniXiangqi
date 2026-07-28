#!/usr/bin/env python3
"""Emit the slate 5.2 fixtures byte-exactly in the approved serialization."""
import json
import pathlib

OUT = pathlib.Path("/Users/tianren/coding/minixiangqi/fx-classes/fixtures/rules")


def fixture(fid, title, start_fen, cycle, state, reason, at_occurrence, result_fen,
            boundary_expect, rationale):
    moves = list(cycle) * 2
    gs = {"state": state, "reason": reason, "at_occurrence": at_occurrence}
    return {
        "id": fid,
        "title": title,
        "area": "chs",
        "variant": "minixiangqi",
        "start_fen": start_fen,
        "moves": moves,
        "assertions": {
            "in_check": False,
            "result_fen": result_fen,
            "legal_moves": None,
            "rejected_moves": None,
            "applied": None,
            "game_state": gs,
        },
        "boundary": {"prefix_len": 4, "expect": boundary_expect},
        "rationale": rationale,
    }


TERMINAL = "second occurrence; not yet terminal"
NEUTRAL = "second occurrence; not yet claimable"

FIXTURES = [
    fixture(
        "mx-chs-014",
        "A horse chasing a protected chariot is still a chase",
        "3k3/7/3r2r/N6/7/7/4K2 w - - 0 1",
        ["a4c3", "d5c5", "c3a4", "c5d5"],
        "black-wins", "perpetual-chase", 3,
        "3k3/7/3r2r/N6/7/7/4K2 w - - 8 5",
        TERMINAL,
        "The white horse renews its attack on the black chariot after every move "
        "(c3 attacks d5, a4 attacks c5) while the chariot flees between d5 and c5. "
        "The chariot is defended on both squares by its partner on g5, but an attack by "
        "a horse or a cannon on a chariot is a chase independently of protection, because "
        "the capture wins material even after the recapture, so the chasing side (Red) "
        "loses at the third occurrence.",
    ),
    fixture(
        "mx-chs-015",
        "A horse chasing a protected cannon is not a chase",
        "3k3/7/3c2r/N6/7/7/4K2 w - - 0 1",
        ["a4c3", "d5c5", "c3a4", "c5d5"],
        "claimable-draw", "threefold-repetition", 3,
        "3k3/7/3c2r/N6/7/7/4K2 w - - 8 5",
        NEUTRAL,
        "One-piece differential of mx-chs-014: the target's type changes from chariot to "
        "cannon while the black chariot on g5 defends it on d5 and c5 by the same geometry. "
        "The horse and the cannon are treated as equals, so no value relation overrides the "
        "defence and the protected target is not chased; the repetition is neutral and "
        "merely claimable at the third occurrence.",
    ),
    fixture(
        "mx-chs-016",
        "Chariot against chariot is a mutual attack, not a chase",
        "3k3/7/3r3/R6/7/7/2K4 w - - 0 1",
        ["a4a5", "d5d4", "a5a4", "d4d5"],
        "claimable-draw", "threefold-repetition", 3,
        "3k3/7/3r3/R6/7/7/2K4 w - - 8 5",
        NEUTRAL,
        "The white chariot renews its attack on the undefended black chariot after every "
        "move (a5 attacks d5, a4 attacks d4), and black's replies attack nothing. A target "
        "of the same type as the attacking piece is nevertheless not a chase target, because "
        "the attack is mutual and the target can answer it, so the repetition is neutral.",
    ),
    fixture(
        "mx-chs-017",
        "A pinned same-type target cannot answer, so the chase stands",
        "3k3/7/3r3/R6/7/7/2KR3 w - - 0 1",
        ["a4a5", "d5d4", "a5a4", "d4d5"],
        "black-wins", "perpetual-chase", 3,
        "3k3/7/3r3/R6/7/7/2KR3 w - - 8 5",
        TERMINAL,
        "One-piece differential of mx-chs-016: the white chariot added on d1 pins the black "
        "chariot to its king on d7, so the same-type target cannot answer the mutual attack "
        "and the exclusion does not apply. The undefended pinned chariot is chased on every "
        "white move — the black king on d7 defends neither d5 nor d4 — and the chasing side "
        "(Red) loses at the third occurrence.",
    ),
    fixture(
        "mx-chs-018",
        "A soldier's move never creates a chase",
        "4k2/7/7/c6/1P5/7/2K4 w - - 0 1",
        ["b3a3", "a4b4", "a3b3", "b4a4"],
        "claimable-draw", "threefold-repetition", 3,
        "4k2/7/7/c6/1P5/7/2K4 w - - 8 5",
        NEUTRAL,
        "This is a meaningful negative, not a position without an attack: the white soldier "
        "genuinely attacks the undefended black cannon after each of its moves — a3 attacks "
        "a4 and b3 attacks b4, and the capture is legal — and the same wheel with a chariot "
        "in place of the soldier is a perpetual chase. A soldier takes no part in the chase "
        "rule as a chasing piece, so only the attacker-class rule produces the neutral "
        "repetition. The fixture also pins that a soldier move does not reset the halfmove "
        "clock: the fifth FEN field is 8 after eight plies of which four are soldier moves.",
    ),
    fixture(
        "mx-chs-019",
        "A king's move never creates a chase",
        "4k2/7/7/7/3c3/2K4/7 w - - 0 1",
        ["c2d2", "d3c3", "d2c2", "c3d3"],
        "claimable-draw", "threefold-repetition", 3,
        "4k2/7/7/7/3c3/2K4/7 w - - 8 5",
        NEUTRAL,
        "The companion meaningful negative to mx-chs-018 for the other excluded attacker: "
        "the white king genuinely attacks the undefended black cannon after each of its "
        "moves — d2 attacks d3 and c2 attacks c3, and the capture is legal — and the same "
        "shuttle driven by a chariot is a perpetual chase. A king takes no part in the chase "
        "rule as a chasing piece, so only the attacker-class rule produces the neutral "
        "repetition.",
    ),
]


def main():
    for fx in FIXTURES:
        p = OUT / f"{fx['id']}.json"
        p.write_text(json.dumps(fx, indent=2, ensure_ascii=False) + "\n")
        print(f"wrote {p}")


if __name__ == "__main__":
    main()
