#!/usr/bin/env python3
"""Generate the mx-chs-005 .. mx-chs-013 protection fixtures into the fx-protection worktree.

Expectations are derived from MiniXiangqi/docs/xiangqi-rules.md (the contract), not from
the engine; p-check.py replays them against the engine afterwards.
"""
import json
import pathlib

OUT = pathlib.Path("/Users/tianren/coding/minixiangqi/fx-protection/fixtures/rules")

W1 = ["e6e5", "c5c6", "e5e6", "c6c5"]  # c-file family cycle
W2 = ["b3a3", "a5b5", "a3b3", "b5a5"]  # mx-chs-001/002 rook-shuttle cycle
W3 = ["a1b1", "b5a5", "b1a1", "a5b5"]  # mx-chs-012 cycle


def fx(fid, title, start, cycle, state, reason, result_fen, rationale):
    terminal = state != "claimable-draw"
    return {
        "id": fid,
        "title": title,
        "area": "chs",
        "variant": "minixiangqi",
        "start_fen": start,
        "moves": cycle * 2,
        "assertions": {
            "in_check": False,
            "result_fen": result_fen,
            "legal_moves": None,
            "rejected_moves": None,
            "applied": None,
            "game_state": {
                "state": state,
                "reason": reason,
                "at_occurrence": 3,
            },
        },
        "boundary": {
            "prefix_len": 4,
            "expect": "second occurrence; not yet terminal"
            if terminal
            else "second occurrence; not yet claimable",
        },
        "rationale": rationale,
    }


FIXTURES = [
    fx(
        "mx-chs-005",
        "A pinned defender does not protect the chased cannon",
        "4k2/7/c3r2/7/1R5/7/2K1R2 w - - 0 1",
        W2,
        "black-wins",
        "perpetual-chase",
        "4k2/7/c3r2/7/1R5/7/2K1R2 w - - 8 5",
        "Differential partner of mx-chs-002: the only addition is the white rook on e1, "
        "which pins the black chariot on e5 against its king on e7. The pinned chariot cannot "
        "legally recapture on a5 or b5, so it does not protect, the chased cannon is unprotected "
        "at every step of the shuttle, and the chasing side (Red) loses at the third occurrence.",
    ),
    fx(
        "mx-chs-006",
        "Chase base for the c-file protection family: an unprotected cannon",
        "3k3/4R2/2c4/7/7/7/2K4 w - - 0 1",
        W1,
        "black-wins",
        "perpetual-chase",
        "3k3/4R2/2c4/7/7/7/2K4 w - - 8 5",
        "The white rook renews its attack on the same black cannon after every Red move (e5 "
        "attacks c5 along rank 5, e6 attacks c6 along rank 6) while the cannon shuttles between "
        "c5 and c6, and the black king on d7 defends neither square. The target is unprotected "
        "throughout and the chasing side (Red) loses at the third occurrence; this is the "
        "unmodified base of the mx-chs-006 to mx-chs-011 differential chain.",
    ),
    fx(
        "mx-chs-007",
        "An X-ray defender behind the attacker protects",
        "3k3/4R2/2c3r/7/7/7/2K4 w - - 0 1",
        W1,
        "claimable-draw",
        "threefold-repetition",
        "3k3/4R2/2c3r/7/7/7/2K4 w - - 8 5",
        "mx-chs-006 plus the black chariot on g5, the single change. Protection is tested in the "
        "position that would arise after the capture, where the chasing rook no longer stands on "
        "e5, so the chariot's line through the chaser counts and g5c5 recaptures: Red's e6e5 "
        "attacks a protected cannon, no chase of an unprotected target is sustained across every "
        "Red move, and the repetition is neutral and merely claimable.",
    ),
    fx(
        "mx-chs-008",
        "A soldier is a valid defender",
        "3k3/1p2R2/2c4/7/7/7/2K4 w - - 0 1",
        W1,
        "claimable-draw",
        "threefold-repetition",
        "3k3/1p2R2/2c4/7/7/7/2K4 w - - 8 5",
        "mx-chs-006 plus the black soldier on b6, the single change; it defends c6 sideways. The "
        "soldier exclusion from the chase rule covers being chased and chasing, not defending, so "
        "Red's e5e6 attacks a protected cannon, the chase is not sustained across every Red move, "
        "and the repetition is neutral and merely claimable.",
    ),
    fx(
        "mx-chs-009",
        "A general as sole defender does not protect when the flying general voids the recapture",
        "2k4/4R2/2c4/7/7/7/2K4 w - - 0 1",
        W1,
        "black-wins",
        "perpetual-chase",
        "2k4/4R2/2c4/7/7/7/2K4 w - - 8 5",
        "mx-chs-006 with the black king moved d7 to c7, the single change, from where it defends "
        "c6 inside its own palace. The recapture c7c6 is illegal because it would leave the two "
        "kings facing on an otherwise empty c-file, so the cannon is as unprotected on c6 as it "
        "already is on c5 and the chasing side (Red) loses at the third occurrence.",
    ),
    fx(
        "mx-chs-010",
        "A general as sole defender protects when the recapture is legal",
        "2k4/4R2/2c4/7/7/7/3K3 w - - 0 1",
        W1,
        "claimable-draw",
        "threefold-repetition",
        "2k4/4R2/2c4/7/7/7/3K3 w - - 8 5",
        "mx-chs-009 with the white king moved c1 to d1, the single change. The kings no longer "
        "share a file, so c7c6 is a legal recapture and the cannon is protected on c6: Red's "
        "e5e6 is not a chase, the chase is not sustained across every Red move, and the "
        "repetition is neutral and merely claimable.",
    ),
    fx(
        "mx-chs-011",
        "Adopted limit: a king recapture illegal for a non-flying-general reason still counts as protection",
        "2k4/4R2/2c4/1N5/7/7/3K3 w - - 0 1",
        W1,
        "claimable-draw",
        "threefold-repetition",
        "2k4/4R2/2c4/1N5/7/7/3K3 w - - 8 5",
        "mx-chs-010 plus the white horse on b4, the single change; the horse covers c6, so c7c6 "
        "is illegal for a reason other than the flying general. The accepted interpretation "
        "judges a general as sole defender on the flying-generals condition alone, so the cannon "
        "still counts as protected here and the repetition stays neutral. The fixture "
        "deliberately under-detects: a strict recapture test would instead make Red lose, and "
        "this fixture is what a change to that interpretation would have to amend.",
    ),
    fx(
        "mx-chs-012",
        "A king protects only inside its own palace",
        "7/7/1ck4/7/7/7/R3K2 w - - 0 1",
        W3,
        "black-wins",
        "perpetual-chase",
        "7/7/1ck4/7/7/7/R3K2 w - - 8 5",
        "The white rook renews its attack on the same black cannon after every Red move while "
        "the cannon shuttles between a5 and b5; both squares are on the black king's rank and b5 "
        "is adjacent to it, but both lie outside its palace, so the king can never recapture "
        "there and the target is unprotected throughout. This is not a one-piece differential of "
        "another fixture: its positive half, a king that does protect, is mx-chs-010.",
    ),
    fx(
        "mx-chs-013",
        "A cannon protects only through exactly one screen",
        "4k2/7/c3c2/7/1R5/7/2K4 w - - 0 1",
        W2,
        "black-wins",
        "perpetual-chase",
        "4k2/7/c3c2/7/1R5/7/2K4 w - - 8 5",
        "Differential partner of mx-chs-002, with the defending black chariot on e5 replaced by a "
        "black cannon. A cannon captures only over exactly one screen, and rank 5 between e5 and "
        "the capture square is empty, so the cannon defends neither a5 nor b5 and never protects "
        "a piece it has a clear line to, including the piece immediately next to it. The chased "
        "cannon is unprotected and the chasing side (Red) loses at the third occurrence.",
    ),
]


def main():
    for f in FIXTURES:
        path = OUT / f"{f['id']}.json"
        path.write_text(json.dumps(f, indent=2, ensure_ascii=False) + "\n")
        print(f"wrote {path}")


if __name__ == "__main__":
    main()
