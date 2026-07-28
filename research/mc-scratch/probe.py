import sys
sys.path.insert(0, "/Users/tianren/coding/minixiangqi/discussion-drafts/w-base")
import pyffish as sf

INI = """
[mxq_target:minixiangqi]
chasingRule = axf
nMoveRule = 0
promotedSoldiersChaseable = false

[mxq_control:minixiangqi]
chasingRule = axf
nMoveRule = 0
"""
sf.load_variant_config(INI)
print("engine:", sf.info())

def board(fen):
    rows = fen.split()[0].split("/")
    out = []
    for i, r in enumerate(rows):
        rank = 7 - i
        line = []
        for ch in r:
            if ch.isdigit():
                line += ["."] * int(ch)
            else:
                line.append(ch)
        out.append(f"{rank} " + " ".join(line))
    out.append("  " + " ".join("abcdefg"))
    return "\n".join(out)

CASES = [
 ("mx-chs-033", "2k4/7/1cN1R2/7/4n2/7/1R2K2 w - - 0 1", ["c5b3","e3f5","b3c5","f5e3"]*2),
 ("mx-chs-034", "2k2r1/7/2N4/7/2r1nC1/7/4K2 w - - 0 1", ["c5b3","e3f5","b3c5","f5e3"]*2),
 ("mx-mix-002", "2k2r1/7/1cN1R2/7/2r1nC1/7/1R2K2 w - - 0 1", ["c5b3","e3f5","b3c5","f5e3"]*2),
 ("mx-mix-003", "3k3/7/c6/R6/7/7/4K2 w - - 0 1", ["a4d4","d7c7","d4a4","c7d7"]*2),
]

for v in ("mxq_target", "mxq_control"):
    print("="*70)
    print("VARIANT", v)
    for name, start, moves in CASES:
        print("-"*60)
        print(name, start)
        print(board(start))
        ok = True
        flags = []
        fens = []
        for i in range(len(moves)+1):
            fens.append(sf.get_fen(v, start, moves[:i]))
            flags.append("T" if sf.gives_check(v, start, moves[:i]) else "f")
        for i in range(len(moves)):
            legal = sf.legal_moves(v, start, moves[:i])
            if moves[i] not in legal:
                print(f"  ILLEGAL move {i} {moves[i]}; legal={sorted(legal)}")
                ok = False
                break
        if not ok:
            continue
        print("  check flags per ply:", "".join(flags))
        print("  final fen:", fens[-1])
        print("  in_check final:", flags[-1])
        # occurrence structure
        keys = [" ".join(f.split()[:2]) for f in fens]
        print("  occurrences of final pos at plies:", [i for i,k in enumerate(keys) if k == keys[-1]])
        for pl in (len(moves)-4, len(moves)):
            e, val = sf.is_optional_game_end(v, start, moves[:pl])
            print(f"  is_optional_game_end at {pl} plies: ended={e} value={val if e else '(garbage)'}  stm={fens[pl].split()[1]}")
        print("  game_result:", sf.game_result(v, start, moves) if not sf.legal_moves(v, start, moves) else "(has legal moves)")
