import json, pathlib, sys, random
sys.path.insert(0,'/Users/tianren/coding/minixiangqi/discussion-drafts/v-prot')
sys.path.insert(0,'/Users/tianren/coding/minixiangqi/discussion-drafts/r-scratch')
import mxq, pyffish as sf
sf.load_variant_config("[mxq_target:minixiangqi]\nchasingRule = axf\nnMoveRule = 0\npromotedSoldiersChaseable = false\n")
V="mxq_target"
D = pathlib.Path('/Users/tianren/coding/minixiangqi/fx-protection/fixtures/rules')

def play(fen, moves):
    b, stm, half, full = mxq.parse_fen(fen)
    for m in moves:
        a, t = mxq.parse_sq(m[:2]), mxq.parse_sq(m[2:])
        cap = t in b
        assert (a,t) in mxq.legal_moves(b, stm), f"illegal {m}"
        b = mxq.apply_move(b,(a,t))
        half = 0 if cap else half+1
        if stm=="b": full += 1
        stm = "b" if stm=="w" else "w"
    return b, stm, half, full

bad=0; checked=0
random.seed(7)
for p in sorted(D.glob('mx-*.json')):
    fx = json.loads(p.read_text())
    start, moves = fx['start_fen'], fx['moves']
    for i in range(len(moves)+1):
        b, stm, half, full = play(start, moves[:i])
        mine_fen = mxq.to_fen(b, stm, half, full)
        eng_fen = sf.get_fen(V, start, moves[:i])
        mine_lm = mxq.legal_move_strs(b, stm)
        eng_lm = sorted(sf.legal_moves(V, start, moves[:i]))
        mine_chk = mxq.in_check(b, stm)
        eng_chk = sf.gives_check(V, start, moves[:i])
        checked += 1
        if mine_fen != eng_fen: print(f"FEN  {fx['id']}@{i}: mine={mine_fen} eng={eng_fen}"); bad+=1
        if mine_lm != eng_lm:
            print(f"LM   {fx['id']}@{i}: only-mine={set(mine_lm)-set(eng_lm)} only-eng={set(eng_lm)-set(mine_lm)}"); bad+=1
        if mine_chk != eng_chk: print(f"CHK  {fx['id']}@{i}"); bad+=1
    # random walk stress from the start position
    for trial in range(40):
        b, stm, half, full = mxq.parse_fen(start); hist=[]
        for d in range(10):
            lm = mxq.legal_moves(b, stm)
            eng = sorted(sf.legal_moves(V, start, hist))
            mine = mxq.legal_move_strs(b, stm)
            checked += 1
            if mine != eng:
                print(f"RW   {fx['id']} {hist}: only-mine={set(mine)-set(eng)} only-eng={set(eng)-set(mine)}"); bad+=1; break
            if not lm: break
            mv = random.choice(lm)
            s = mxq.sqname(*mv[0])+mxq.sqname(*mv[1])
            cap = mv[1] in b
            b = mxq.apply_move(b, mv); half = 0 if cap else half+1
            if stm=="b": full+=1
            stm = "b" if stm=="w" else "w"; hist.append(s)
print(f"\nmodel cross-check: {checked} comparisons, {bad} disagreements")
