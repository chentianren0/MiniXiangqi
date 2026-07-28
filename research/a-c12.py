V = "minixiangqiaxf"
def V0(fen, mv):
    for i in range(len(mv)):
        if mv[i] not in pyffish.legal_moves(V, fen, mv[:i]):
            return f"ILLEGAL ply {i+1} {mv[i]}"
    return pyffish.is_optional_game_end(V, fen, mv)
CH = "4k2/7/c6/7/1R5/7/2K4 w - - 0 1"
idle = ['c1c2','e7e6','c2c1','e6e7']; chase = ['b3a3','a5b5','a3b3','b5a5']
for n in (2,3):
    print(f"idle + {n} chase cycles (occurrence {n+2}):", V0(CH, idle + chase*n))
