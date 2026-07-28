import json, pathlib
from collections import OrderedDict

OUT = pathlib.Path("/Users/tianren/coding/minixiangqi/fx-mutual-chase/fixtures/rules")
WHEEL = ["c5b3", "e3f5", "b3c5", "f5e3"] * 2
MIX3 = ["a4d4", "d7c7", "d4a4", "c7d7"] * 2

def fx(id, title, area, start, moves, result_fen, state, reason, expect, rationale, in_check=False):
    return OrderedDict([
        ("id", id), ("title", title), ("area", area), ("variant", "minixiangqi"),
        ("start_fen", start), ("moves", moves),
        ("assertions", OrderedDict([
            ("in_check", in_check),
            ("result_fen", result_fen),
            ("legal_moves", None),
            ("rejected_moves", None),
            ("applied", None),
            ("game_state", OrderedDict([("state", state), ("reason", reason), ("at_occurrence", 3)])),
        ])),
        ("boundary", OrderedDict([("prefix_len", 4), ("expect", expect)])),
        ("rationale", rationale),
    ])

fixtures = [
 fx("mx-chs-033",
    "The White half of the mutual chase alone is a unilateral perpetual chase",
    "chs",
    "2k4/7/1cN1R2/7/4n2/7/1R2K2 w - - 0 1", WHEEL,
    "2k4/7/1cN1R2/7/4n2/7/1R2K2 w - - 8 5",
    "black-wins", "perpetual-chase",
    "second occurrence; not yet terminal",
    "White's two chariots alternate as the discovered attacker on the unprotected black cannon on b5 — e5 attacks it once the horse vacates c5, b1 once the horse returns and unblocks the b-file — so every White move renews the attack on one and the same piece from a square that piece was not attacked from before the move. Black's horse shuttle e3/f5 attacks nothing and renews nothing; the black cannon's own threat on an undefended white chariot is produced by White's moves and alternates between two different pieces, which is a chase of neither. Red therefore loses at the third occurrence; this is the White half of mx-mix-002 in isolation."),
 fx("mx-chs-034",
    "The Black half of the mutual chase alone is a unilateral perpetual chase",
    "chs",
    "2k2r1/7/2N4/7/2r1nC1/7/4K2 w - - 0 1", WHEEL,
    "2k2r1/7/2N4/7/2r1nC1/7/4K2 w - - 8 5",
    "red-wins", "perpetual-chase",
    "second occurrence; not yet terminal",
    "Black's two chariots alternate as the discovered attacker on the unprotected white cannon on f3 — c3 attacks it once the horse vacates e3, f7 once the horse returns and unblocks the f-file — so every Black move renews the attack on one and the same piece from a square that piece was not attacked from before the move. White's horse shuttle c5/b3 attacks nothing; the white cannon's own threat is produced by Black's moves and alternates between the two black chariots, which is a chase of neither. Black therefore loses at the third occurrence; this is the Black half of mx-mix-002 in isolation."),
 fx("mx-mix-002",
    "Mutual perpetual chase is a draw",
    "mix",
    "2k2r1/7/1cN1R2/7/2r1nC1/7/1R2K2 w - - 0 1", WHEEL,
    "2k2r1/7/1cN1R2/7/2r1nC1/7/1R2K2 w - - 8 5",
    "draw", "mutual-perpetual-chase",
    "second occurrence; not yet a draw by mutual violation",
    "The exact union of mx-chs-033 and mx-chs-034: Red perpetually chases the unprotected black cannon on b5 and Black perpetually chases the unprotected white cannon on f3, each renewed by every move that side makes after the first of the three occurrences, and neither side ever gives check. Both sides commit the same class of violation, so the contract's mutual rule makes this a draw carrying the reserved reason mutual-perpetual-chase rather than a claimable repetition. The current unpatched engine returns the draw value but cannot report the reason — it collapses a neutral threefold, a mutual perpetual check and a mutual perpetual chase onto the same value, and unlike mx-mix-001 no check-flag signal separates them — so this fixture's reason is gated on a fork accessor exposing which branch fired and is not validated by engine agreement."),
 fx("mx-mix-003",
    "A side alternating check and chase commits neither violation",
    "mix",
    "3k3/7/c6/R6/7/7/4K2 w - - 0 1", MIX3,
    "3k3/7/c6/R6/7/7/4K2 w - - 8 5",
    "claimable-draw", "threefold-repetition",
    "second occurrence; not yet claimable",
    "Red's chariot checks the black king from d4 on one move of each cycle and renews its attack on the unprotected black cannon on a5 from a4 on the other, so the check flags across the nine plies are f T f f f T f f f and Red alternates the two violation classes. Each accepted class is a single behaviour that must be sustained by every move the side makes across the counted occurrences; neither is, so Red commits neither and the repetition is neutral and merely claimable at the third occurrence. The engine implements no combined check-and-chase rule, so its agreement here is the absence of an implementation rather than evidence; the authority is the accepted interpretation in docs/xiangqi-rules.md."),
]

for f in fixtures:
    p = OUT / (f["id"] + ".json")
    p.write_text(json.dumps(f, indent=2, ensure_ascii=False) + "\n")
    print("wrote", p)
