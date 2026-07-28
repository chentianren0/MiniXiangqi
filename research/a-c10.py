import importlib.util, random, time
spec = importlib.util.spec_from_file_location("asearch", "a-search.py")
S = importlib.util.module_from_spec(spec); spec.loader.exec_module(S)
S.get_fen = pyffish.get_fen; S.legal_moves = pyffish.legal_moves; S.gives_check = pyffish.gives_check
V, N = "minixiangqiaxf", "minixiangqiaxfnochk"
random.seed(101)
t0 = time.time(); tried = cand = hits = 0
while time.time() - t0 < 400 and hits < 4:
    tried += 1
    nw, nb = random.choice([(2,2),(2,3),(3,2),(3,3)])
    pieces = S.gen(nw, nb, ["R","N","C","P"], ["r","n","c","p"])
    fen = S.to_fen(pieces, "w")
    try:
        if pyffish.gives_check(V, fen, []):
            continue
        lm = pyffish.legal_moves(V, fen, [])
    except Exception:
        continue
    if not lm:
        continue
    # cheap prefilter: white must have at least one checking move
    if not any(pyffish.gives_check(V, fen, [m]) for m in lm):
        continue
    cand += 1
    for c in S.cycles(V, fen, [True, False, True, False]):
        line = c * 2
        a = pyffish.is_optional_game_end(V, fen, line)
        b = pyffish.is_optional_game_end(N, fen, line)
        if a[0] and a[1] != 0 and b[0] and b[1] != 0 and a[1] != b[1]:
            hits += 1
            print("MIXED:", fen, c, "axf=", a, "nochk=", b, flush=True)
print(f"tried={tried} cand={cand} hits={hits} elapsed={time.time()-t0:.1f}s")
