#!/usr/bin/env python3
"""Independent verification of mx-mix-005..008 (verifier-written, not the builder's probe).

Usage: python3 verify-mutual-entry.py <build-dir>
"""
import json, pathlib, sys

sys.path.insert(0, sys.argv[1])
import pyffish as sf

INI = """
[mxq:minixiangqi]
chasingRule = axf
nMoveRule = 0
promotedSoldiersChaseable = false
"""
sf.load_variant_config(INI)
V = "mxq"
FX = pathlib.Path("/Users/tianren/coding/minixiangqi/gap-mutual-entry/fixtures/rules")

print("engine:", sf.info(), " build:", sys.argv[1])


def key(fen):
    """Position identity per the contract: placement + side to move only."""
    p = fen.split()
    return (p[0], p[1])


def swap_stm(fen):
    p = fen.split()
    p[1] = "b" if p[1] == "w" else "w"
    return " ".join(p)


def board_from_fen(fen):
    rows = fen.split()[0].split("/")
    b = {}
    for ri, row in enumerate(rows):
        rank = 7 - ri
        f = 0
        for ch in row:
            if ch.isdigit():
                f += int(ch)
            else:
                b["abcdefg"[f] + str(rank)] = ch
                f += 1
    return b


def fen_from_board(b, stm):
    rows = []
    for rank in range(7, 0, -1):
        row, empty = "", 0
        for f in "abcdefg":
            p = b.get(f + str(rank))
            if p is None:
                empty += 1
            else:
                if empty:
                    row += str(empty); empty = 0
                row += p
        if empty:
            row += str(empty)
        rows.append(row)
    return "/".join(rows) + f" {stm} - - 0 1"


def attackers_of(fen, square, by):
    """Legal moves by side `by` that land on `square` in this exact position."""
    f = fen if fen.split()[1] == by else swap_stm(fen)
    try:
        mv = sf.legal_moves(V, f, [])
    except Exception as e:
        return ["<illegal position: %s>" % e]
    return sorted(m for m in mv if m[2:4] == square)


def defenders_of(fen, square, owner):
    """Substitute an enemy piece on `square` and list owner-side captures of it."""
    b = board_from_fen(fen)
    piece = b[square]
    b[square] = piece.swapcase()          # make it an enemy piece of the owner
    f = fen_from_board(b, owner)
    try:
        mv = sf.legal_moves(V, f, [])
    except Exception as e:
        return ["<illegal: %s>" % e]
    return sorted(m for m in mv if m[2:4] == square)


for fid in ("mx-mix-005", "mx-mix-006", "mx-mix-007", "mx-mix-008"):
    fx = json.loads((FX / f"{fid}.json").read_text())
    start, moves = fx["start_fen"], fx["moves"]
    print("\n" + "=" * 78)
    print(fid, "|", fx["title"])
    print("start:", start)

    # --- ply-by-ply: legality, capture-freedom, check, position identity ---
    seen = {}
    fens = [sf.get_fen(V, start, [])]
    seen[key(fens[0])] = [0]
    prev_pieces = len(board_from_fen(fens[0]))
    print(" ply  move    fen                                                  chk  occ")
    print(f"   0  ----    {fens[0]:<52} {sf.gives_check(V, start, []):d}    1")
    ok = True
    for i, m in enumerate(moves):
        legal = sf.legal_moves(V, start, moves[:i])
        if m not in legal:
            print(f"   ILLEGAL move {i+1} {m}")
            ok = False
            break
        f = sf.get_fen(V, start, moves[: i + 1])
        fens.append(f)
        chk = sf.gives_check(V, start, moves[: i + 1])
        n = len(board_from_fen(f))
        cap = " CAPTURE!" if n != prev_pieces else ""
        prev_pieces = n
        occ = seen.setdefault(key(f), [])
        occ.append(i + 1)
        print(f"  {i+1:2d}  {m}  {f:<52} {chk:d}   {len(occ)}{cap}")
    print("  result_fen match:", fens[-1] == fx["assertions"]["result_fen"], "|",
          "in_check match:", sf.gives_check(V, start, moves) == fx["assertions"]["in_check"])
    print("  occurrence map (>=2):", {k[0][:14] + "..|" + k[1]: v for k, v in seen.items() if len(v) > 1})

    # --- entry move: does it change either attack configuration? ---
    tgt = ("b5", "f3")
    print("  entry move", moves[0], "attack config before/after:")
    for sq, side in ((tgt[0], "w"), (tgt[1], "b")):
        before = attackers_of(fens[0], sq, side)
        after = attackers_of(fens[1], sq, side)
        print(f"    attackers of {sq} by {side}: before={before} after={after} "
              f"{'UNCHANGED' if before == after else '*** CHANGED ***'}")

    # --- every position in the judged window: attackers and defenders of both targets ---
    print("  judged window (plies 1..%d):" % len(moves))
    for i in range(1, len(fens)):
        f = fens[i]
        b = board_from_fen(f)
        wa = attackers_of(f, "b5", "w") if b.get("b5") == "c" else ["<no black cannon on b5>"]
        ba = attackers_of(f, "f3", "b") if b.get("f3") == "C" else ["<no white cannon on f3>"]
        wd = defenders_of(f, "b5", "b") if b.get("b5") == "c" else []
        bd = defenders_of(f, "f3", "w") if b.get("f3") == "C" else []
        print(f"    ply {i:2d}: W->b5 {str(wa):<14} defenders {wd}   |   B->f3 {str(ba):<14} defenders {bd}")

    # --- engine verdicts at each prefix ---
    print("  is_optional_game_end by prefix length:")
    for n in range(0, len(moves) + 1):
        e, v = sf.is_optional_game_end(V, start, moves[:n])
        stm = sf.get_fen(V, start, moves[:n]).split()[1]
        note = ""
        if e and v != 0:
            note = "  -> " + ("RED LOSES" if stm == "w" else "BLACK LOSES")
        print(f"    {n:2d} plies (stm {stm}): ended={e} value={v}{note}")

    b = fx["boundary"]
    e, v = sf.is_optional_game_end(V, start, moves[: b["prefix_len"]])
    print(f"  boundary prefix_len={b['prefix_len']}: ended={e} value={v}  "
          f"({'OK' if not e else 'ALREADY ENDED'})")
