import json, pathlib
from collections import OrderedDict

OUT = pathlib.Path("/Users/tianren/coding/minixiangqi/fx-patch-gated/fixtures/rules")
W = ["a5b5", "a3b3", "b5a5", "b3a3"]

def fx(fid, title, area, start, moves, in_check, result_fen, state, reason,
       at_occurrence, prefix_len, expect, rationale):
    gs = OrderedDict([("state", state), ("reason", reason)])
    if at_occurrence is not None:
        gs["at_occurrence"] = at_occurrence
    o = OrderedDict([
        ("id", fid),
        ("title", title),
        ("area", area),
        ("variant", "minixiangqi"),
        ("start_fen", start),
        ("moves", moves),
        ("assertions", OrderedDict([
            ("in_check", in_check),
            ("result_fen", result_fen),
            ("legal_moves", None),
            ("rejected_moves", None),
            ("applied", None),
            ("game_state", gs),
        ])),
        ("boundary", None if prefix_len is None else OrderedDict([
            ("prefix_len", prefix_len), ("expect", expect)])),
        ("rationale", rationale),
    ])
    (OUT / f"{fid}.json").write_text(json.dumps(o, indent=2, ensure_ascii=False) + "\n")
    print("wrote", fid)

fx("mx-chs-028",
   "An absolutely pinned chariot's threat is not a chase",
   "chs",
   "3rk2/7/7/3R3/1c5/7/3K3 w - - 0 1",
   ["d4d3", "b3b4", "d3d4", "b4b3"] * 2,
   False,
   "3rk2/7/7/3R3/1c5/7/3K3 w - - 8 5",
   "claimable-draw", "threefold-repetition", 3,
   4, "second occurrence; not yet claimable",
   "The white chariot shuttles between d4 and d3 and appears to attack the black cannon on b4 and b3 along the rank, but it is absolutely pinned on the d-file by the black chariot on d7 against the white king on d1: its legal moves at every ply of this history are d-file moves only, so the capture is never available. An attack the chasing piece could not legally make is not a threat and is not a chase, so the repetition is neutral and merely claimable at the third occurrence. Patch-gated against fork correction P1: the current unpatched engine ignores the pin and rules Red the loser here, so this fixture states the contract against the engine and is expected to fail until that correction lands.")

fx("mx-chs-029",
   "No flying-general pin exists when a piece of either colour blocks the file",
   "chs",
   "2k4/7/R6/2r4/7/2P4/2K4 w - - 0 1",
   ["a5a4", "c4c5", "a4a5", "c5c4"] * 2,
   False,
   "2k4/7/R6/2r4/7/2P4/2K4 w - - 8 5",
   "claimable-draw", "threefold-repetition", 3,
   4, "second occurrence; not yet claimable",
   "Both chariots are undefended and attack each other on equal terms, which the same-type exclusion makes a mutual attack rather than a chase, and the black chariot is not pinned: the white soldier on c2 also stands between the two kings on the c-file, and it defends neither a4 nor a5. A piece is pinned by the flying-general rule only when the two kings share a file and it is the only piece of either colour standing between them, so neither side chases and the repetition is neutral. Patch-gated against fork correction P2: the current unpatched engine computes that pin over the victim's pieces alone, treats the black chariot as pinned, and rules Red the loser, so this fixture states the contract against the engine and is expected to fail until that correction lands.")

fx("mx-chs-030",
   "The chase test must not reach behind the first of the three occurrences",
   "chs",
   "4k2/7/c6/7/7/7/R1K4 w - - 0 1",
   ["a1a3"] + W * 2,
   False,
   "4k2/7/c6/7/R6/7/2K4 b - - 9 5",
   "black-wins", "perpetual-chase", 3,
   5, "second occurrence; not yet terminal",
   "The entry move a1a3 advances the chariot toward the cannon along the a-file, on which its attack already stood, so it renews nothing and is not itself a chase; the four White moves strictly after the first occurrence at ply 1 each swing the chariot across onto the file the cannon now stands on and renew the chase of that one unprotected piece, completing the violation at the third occurrence. Only moves inside the three-occurrence window are part of the test, and adjudication does not depend on which side happens to be to move when the third occurrence lands, which mx-chs-032 pins as the identical wheel at the other parity. Patch-gated against fork correction P3: the current unpatched engine also intersects the chase set of the quiet entry move, which lies outside the window, and returns a draw at this parity, so this fixture states the contract against the engine and is expected to fail until that correction lands.")

fx("mx-chs-031",
   "Matched control: the same wheel entered by a chasing move",
   "chs",
   "4k2/7/c6/7/1R5/7/2K4 w - - 0 1",
   ["b3a3"] + W * 2,
   False,
   "4k2/7/c6/7/R6/7/2K4 b - - 9 5",
   "black-wins", "perpetual-chase", 3,
   5, "second occurrence; not yet terminal",
   "The matched control for mx-chs-030: the same four-move wheel and a byte-identical result_fen, differing only in that the entry move b3a3 swings the chariot across onto the cannon's file instead of advancing along it, so the entry itself renews the chase. Red loses at the third occurrence for the same reason as in mx-chs-030, and this fixture is a control rather than a patch-gated case because the current engine already agrees with it; that agreement is what makes the pair a decisive differential on the chase window. Note that the start position also stands for the third time at ply 8, so the contract rules this game terminal one ply earlier as well; the assertions here are those the rules facade must report for the complete nine-ply history, which is what makes it comparable with mx-chs-030.")

fx("mx-chs-032",
   "Matched control at the other parity: identical start and entry move to mx-chs-030",
   "chs",
   "4k2/7/c6/7/7/7/R1K4 w - - 0 1",
   ["a1a3"] + W * 2 + ["a5b5"],
   False,
   "4k2/7/1c5/7/R6/7/2K4 w - - 10 6",
   "black-wins", "perpetual-chase", 3,
   6, "second occurrence; not yet terminal",
   "The parity control for mx-chs-030: the same start position, the same quiet entry move a1a3, and the same four judged White moves at plies 3, 5, 7 and 9, with the three occurrences falling at plies 2, 6 and 10 instead of 1, 5 and 9. Red loses for the same reason, because adjudication does not depend on side-to-move parity; this fixture is a control rather than a patch-gated case because the current engine already agrees with it while it calls mx-chs-030 a draw, and that split on one identical set of judged moves is the whole content of the pair. Its nine-ply prefix is exactly mx-chs-030, which the contract already rules terminal, so this history is a probe of the adjudication function rather than a playable continuation.")
