import importlib.util, random, time
spec = importlib.util.spec_from_file_location("asearch", "a-search.py")
S = importlib.util.module_from_spec(spec); spec.loader.exec_module(S)
S.get_fen = pyffish.get_fen; S.legal_moves = pyffish.legal_moves; S.gives_check = pyffish.gives_check
V = "minixiangqiaxf"
random.seed(23)
t0 = time.time(); found = 0; tried = 0; cand = 0
while time.time() - t0 < 420 and found < 6:
    tried += 1
    nw, nb = random.choice([(2,2),(2,3),(3,2),(3,3)])
    pieces = S.gen(nw, nb, ["R","N","C","P"], ["r","n","c","p"])
    for stm in ("w", "b"):
        fen = S.to_fen(pieces, stm)
        try:
            if not pyffish.gives_check(V, fen, []):
                continue
            lm = pyffish.legal_moves(V, fen, [])
        except Exception:
            continue
        if not lm:
            continue
        cand += 1
        for c in S.cycles(V, fen, [True, True, True, True]):
            found += 1
            print("MUTUAL-CHECK CYCLE:", fen, c, "->", pyffish.is_optional_game_end(V, fen, c*2), flush=True)
print(f"tried={tried} in-check-candidates={cand} found={found} elapsed={time.time()-t0:.1f}s")
