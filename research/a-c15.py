V = "minixiangqiaxf"
fen = "3k3/7/c6/R6/7/7/4K2 w - - 0 1"
mv = ['a4d4','d7c7','d4a4','c7d7']*2
for i in range(len(mv)):
    assert mv[i] in pyffish.legal_moves(V, fen, mv[:i]), (i, mv[i])
print("result_fen", pyffish.get_fen(V, fen, mv))
print("in_check", pyffish.gives_check(V, fen, mv))
print("end", pyffish.is_optional_game_end(V, fen, mv))
print("boundary(4)", pyffish.is_optional_game_end(V, fen, mv[:4]))
print("check flags per ply:", [pyffish.gives_check(V, fen, mv[:i+1]) for i in range(len(mv))])
