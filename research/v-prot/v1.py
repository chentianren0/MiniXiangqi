import json, pathlib, sys
sys.path.insert(0, '/Users/tianren/coding/minixiangqi/discussion-drafts/r-scratch')
import pyffish as sf
INI = """
[mxq_target:minixiangqi]
chasingRule = axf
nMoveRule = 0
promotedSoldiersChaseable = false
"""
sf.load_variant_config(INI)
V = "mxq_target"
D = pathlib.Path('/Users/tianren/coding/minixiangqi/fx-protection/fixtures/rules')
NEW = [f"mx-chs-{n:03d}" for n in range(5, 14)]
for fid in NEW:
    fx = json.loads((D / f"{fid}.json").read_text())
    start, moves = fx["start_fen"], fx["moves"]
    print(f"--- {fid}  start={start}")
    # per-ply trace
    trace = []
    for i in range(len(moves)+1):
        ended, val = sf.is_optional_game_end(V, start, moves[:i])
        fen = sf.get_fen(V, start, moves[:i])
        chk = sf.gives_check(V, start, moves[:i])
        trace.append((i, fen.split()[1], chk, ended, val))
    for t in trace:
        flag = "END" if t[3] else "."
        print(f"    ply {t[0]} stm={t[1]} check={int(t[2])} {flag} val={t[4]}")
    # position occurrence count of the final position key
    keys = [" ".join(sf.get_fen(V, start, moves[:i]).split()[:2]) for i in range(len(moves)+1)]
    fk = keys[-1]
    print(f"    final key occurs at plies {[i for i,k in enumerate(keys) if k==fk]} (count {keys.count(fk)})")
    print(f"    game_result at final: {sf.game_result(V, start, moves)}  legal={len(sf.legal_moves(V,start,moves))}")
