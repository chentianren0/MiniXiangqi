V = "minixiangqiaxf"
import itertools
def V0(fen, mv):
    for i in range(len(mv)):
        if mv[i] not in pyffish.legal_moves(V, fen, mv[:i]):
            return f"ILLEGAL ply {i+1} {mv[i]}"
    return pyffish.is_optional_game_end(V, fen, mv)
CH = "4k2/7/c6/7/1R5/7/2K4 w - - 0 1"
print("chs-001 baseline (2 chase cycles):", V0(CH, ['b3a3','a5b5','a3b3','b5a5']*2))
print("SPAN idle cycle then chase cycle :", V0(CH, ['c1c2','e7e6','c2c1','e6e7','b3a3','a5b5','a3b3','b5a5']))
print("SPAN chase cycle then idle cycle :", V0(CH, ['b3a3','a5b5','a3b3','b5a5','c1c2','e7e6','c2c1','e6e7']))
print("SPAN 3 chase cycles (4th occ)    :", V0(CH, ['b3a3','a5b5','a3b3','b5a5']*3))
