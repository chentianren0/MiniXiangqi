import importlib.util, os, random, sys, time
spec = importlib.util.spec_from_file_location("asearch", os.path.join(os.path.dirname(os.path.abspath("a-search.py")), "a-search.py"))
S = importlib.util.module_from_spec(spec); spec.loader.exec_module(S)
S.get_fen = pyffish.get_fen; S.legal_moves = pyffish.legal_moves; S.gives_check = pyffish.gives_check
V = "minixiangqiaxf"
random.seed(11)
t0 = time.time(); found = []; tried = 0
while time.time() - t0 < 100 and len(found) < 4:
    tried += 1
    nw, nb = random.choice([(2,2),(2,3),(3,2),(3,3)])
    pieces = S.gen(nw, nb, ["R","N","C"], ["r","n","c"])
    fen = S.to_fen(pieces, "w")
    try:
        if pyffish.gives_check(V, fen, []):   # white to move, white must not be checking-illegal
            pass
        lm = pyffish.legal_moves(V, fen, [])
    except Exception:
        continue
    if not lm: continue
    # black must not already be in check-from-white illegality: check via black-to-move probe
    bfen = fen.replace(" w ", " b ")
    try:
        if pyffish.gives_check(V, bfen, []):  # black in check with black to move is fine
            pass
    except Exception:
        continue
    if pyffish.gives_check(V, fen, []):  # side to move (white) in check -> skip for simplicity
        continue
    cs = S.cycles(V, fen, [True, True, True, True])
    for c in cs:
        found.append((fen, c))
        print("MUTUAL-CHECK CYCLE:", fen, c, "->", pyffish.is_optional_game_end(V, fen, c*2))
print(f"tried={tried} found={len(found)} elapsed={time.time()-t0:.1f}s")
