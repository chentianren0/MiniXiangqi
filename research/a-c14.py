import json
V = "minixiangqiaxf"
F = [
 ("mx-chs-005","4k2/7/c3r2/7/1R5/7/2K1R2 w - - 0 1",['b3a3','a5b5','a3b3','b5a5']*2,4),
 ("mx-chs-006","4k2/7/c3c2/7/1R5/7/2K4 w - - 0 1",['b3a3','a5b5','a3b3','b5a5']*2,4),
 ("mx-chs-007","7/7/1ck4/7/7/7/R3K2 w - - 0 1",['a1b1','b5a5','b1a1','a5b5']*2,4),
 ("mx-chs-008","7/3k3/3c3/6R/7/7/2K4 w - - 0 1",['g4g5','d5d4','g5g4','d4d5']*2,4),
 ("mx-chs-009","4R2/7/2kc3/7/7/7/3K3 w - - 0 1",['e7d7','d5e5','d7e7','e5d5']*2,4),
 ("mx-chs-010","4R2/7/2kc3/7/7/7/4K2 w - - 0 1",['e7d7','d5e5','d7e7','e5d5']*2,4),
 ("mx-chs-011","4k2/3N3/r3r2/7/7/7/3K3 w - - 0 1",['d6c4','a5b5','c4d6','b5a5']*2,4),
 ("mx-chs-012","4k2/3N3/c3r2/7/7/7/3K3 w - - 0 1",['d6c4','a5b5','c4d6','b5a5']*2,4),
 ("mx-chs-013","4k2/7/r6/7/1R5/7/2K4 w - - 0 1",['b3a3','a5b5','a3b3','b5a5']*2,4),
 ("mx-chs-014","3k3/7/c6/7/1R5/7/2K4 w - - 0 1",['b3a3','a5a6','a3b3','a6a5']*2,4),
 ("mx-chs-015","3k3/7/c6/7/2R4/7/4K2 w - - 0 1",['c3a3','a5b5','a3b3','b5c5','b3c3','c5a5']*2,6),
 ("mx-chs-016","4k2/7/c6/7/1R5/7/2K4 w - - 0 1",['c1c2','e7e6','c2c1','e6e7','b3a3','a5b5','a3b3','b5a5'],4),
 ("mx-chs-017","4k2/7/c6/7/1R5/7/2K4 w - - 0 1",['c1c2','e7e6','c2c1','e6e7']+['b3a3','a5b5','a3b3','b5a5']*2,8),
 ("mx-chs-018","4k2/7/R1Nc3/7/7/7/2KR3 w - - 0 1",['c5d3','e7e6','d3c5','e6e7']*2,4),
 ("mx-chs-019","3rk2/7/7/3R3/1c5/7/3K3 w - - 0 1",['d4d3','b3b4','d3d4','b4b3']*2,4),
 ("mx-chs-020","2k2r1/7/1cN1R2/7/2r1nC1/7/1R2K2 w - - 0 1",['c5b3','e3f5','b3c5','f5e3']*2,4),
 ("mx-chs-021","2k4/7/1cN1R2/7/4n2/7/1R2K2 w - - 0 1",['c5b3','e3f5','b3c5','f5e3']*2,4),
 ("mx-chs-022","2k2r1/7/2N4/7/2r1nC1/7/4K2 w - - 0 1",['c5b3','e3f5','b3c5','f5e3']*2,4),
 ("mx-chs-023","3k3/7/c5c/7/R6/7/2K4 w - - 0 1",['a3g3','d7d6','g3a3','d6d7']*2,4),
 ("mx-chs-024","R6/7/c3k2/7/1R5/7/3K3 w - - 0 1",['b3a3','a5b5','a7b7','b5a5','b7a7','a5b5','a3b3','b5a5']*2,8),
 ("mx-chs-025","4k2/7/1c5/2P4/7/7/3K3 w - - 0 1",['c4b4','b5c5','b4c4','c5b5']*2,4),
 ("mx-chs-026","4k2/7/7/7/2c4/3K3/7 w - - 0 1",['d2c2','c3d3','c2d2','d3c3']*2,4),
]
for fid, fen, mv, cyc in F:
    for i in range(len(mv)):
        assert mv[i] in pyffish.legal_moves(V, fen, mv[:i]), (fid, i, mv[i])
    rf = pyffish.get_fen(V, fen, mv)
    ic = pyffish.gives_check(V, fen, mv)
    end = pyffish.is_optional_game_end(V, fen, mv)
    bnd = pyffish.is_optional_game_end(V, fen, mv[:len(mv)-cyc])
    print(f'{fid}  plies={len(mv)} bnd_prefix={len(mv)-cyc}')
    print(f'   result_fen "{rf}"  in_check={ic}')
    print(f'   engine end={end}  boundary_end={bnd[0]}')
