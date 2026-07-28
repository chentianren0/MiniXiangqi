import sys, json, pathlib
sys.path.insert(0, "/Users/tianren/coding/minixiangqi/discussion-drafts/w-base")
import pyffish as sf

MATE = 32000
TARGET = "mxq_target"
INI = """
[mxq_target:minixiangqi]
chasingRule = axf
nMoveRule = 0
promotedSoldiersChaseable = false
"""
sf.load_variant_config(INI)
print("engine:", sf.info())

def key(fen):
    p = fen.split()
    return (p[0], p[1])

def report(name, start, moves):
    print("=" * 78)
    print(f"{name}   start={start}")
    # legality
    for i in range(len(moves)):
        legal = sf.legal_moves(TARGET, start, moves[:i])
        if moves[i] not in legal:
            print(f"  ILLEGAL move {i} {moves[i]}; legal={sorted(legal)}")
            return
    print(f"  all {len(moves)} moves legal")
    # occurrence trace
    keys = [key(sf.get_fen(TARGET, start, moves[:i])) for i in range(len(moves) + 1)]
    final = sf.get_fen(TARGET, start, moves)
    fk = key(final)
    occ = [i for i, k in enumerate(keys) if k == fk]
    print(f"  final_fen  = {final}")
    print(f"  in_check   = {sf.gives_check(TARGET, start, moves)}")
    print(f"  occurrences of final position at plies {occ}  (count={len(occ)})")
    # per ply check state
    chk = "".join("T" if sf.gives_check(TARGET, start, moves[:i]) else "f" for i in range(len(moves) + 1))
    print(f"  check per ply (0..n) = {chk}")
    for n in range(len(moves) + 1):
        e, v = sf.is_optional_game_end(TARGET, start, moves[:n])
        if e or n == len(moves):
            stm = sf.get_fen(TARGET, start, moves[:n]).split()[1]
            print(f"    ply {n:2d} stm={stm}  is_optional_game_end = ({e}, {v if e else '-'})")

W = ["a5b5", "a3b3", "b5a5", "b3a3"]

report("mx-chs-028", "3rk2/7/7/3R3/1c5/7/3K3 w - - 0 1",
       ["d4d3", "b3b4", "d3d4", "b4b3"] * 2)
report("mx-chs-029", "2k4/7/R6/2r4/7/2P4/2K4 w - - 0 1",
       ["a5a4", "c4c5", "a4a5", "c5c4"] * 2)
report("mx-chs-030", "4k2/7/c6/7/7/7/R1K4 w - - 0 1", ["a1a3"] + W * 2)
report("mx-chs-031", "4k2/7/c6/7/1R5/7/2K4 w - - 0 1", ["b3a3"] + W * 2)
report("mx-chs-032", "4k2/7/c6/7/7/7/R1K4 w - - 0 1", ["a1a3"] + W * 2 + ["a5b5"])
