import json, pathlib, sys
sys.path.insert(0, "/Users/tianren/coding/minixiangqi/discussion-drafts/w-base")
import pyffish as sf
print("engine:", sf.info())
MATE=32000
INI = """
[mxq_target:minixiangqi]
chasingRule = axf
nMoveRule = 0
promotedSoldiersChaseable = false

[mxq_control:minixiangqi]
chasingRule = axf
nMoveRule = 0
"""
sf.load_variant_config(INI)
D = pathlib.Path("/Users/tianren/coding/minixiangqi/fx-discovery/fixtures/rules")
for n in ["mx-chs-026","mx-chs-027","mx-mix-004"]:
    fx = json.loads((D/(n+".json")).read_text())
    s, mv = fx["start_fen"], fx["moves"]
    print("="*70); print(n, fx["title"])
    for V in ("mxq_target","mxq_control"):
        flags=[]; fens=[]; ok=True
        for i in range(len(mv)):
            legal = sf.legal_moves(V, s, mv[:i])
            if mv[i] not in legal:
                print(f"  {V}: ILLEGAL move {i} {mv[i]}"); ok=False; break
        if not ok: continue
        for i in range(len(mv)+1):
            fens.append(sf.get_fen(V, s, mv[:i]))
            flags.append("T" if sf.gives_check(V, s, mv[:i]) else "f")
        ends=[sf.is_optional_game_end(V, s, mv[:i]) for i in range(len(mv)+1)]
        print(f"  [{V}] checkflags {''.join(flags)}")
        print(f"    final fen  : {fens[-1]}")
        print(f"    fixture fen: {fx['assertions']['result_fen']}  MATCH={fens[-1]==fx['assertions']['result_fen']}")
        print(f"    in_check   : {flags[-1]=='T'} vs fixture {fx['assertions']['in_check']}  MATCH={(flags[-1]=='T')==fx['assertions']['in_check']}")
        print(f"    ends per ply: {ends}")
        # occurrence counting of the final position, done by me
        key=lambda f: " ".join(f.split()[:2])
        k=key(fens[-1]); occ=[i for i,f in enumerate(fens) if key(f)==k]
        print(f"    my occurrence plies for final position: {occ}  count={len(occ)}")
        b=fx["boundary"]
        print(f"    boundary prefix {b['prefix_len']}: end={ends[b['prefix_len']]}, my occ count there={len([i for i in occ if i<=b['prefix_len']])}")
        gs=fx["assertions"]["game_state"]
        stm_red = fens[-1].split()[1]=="w"
        want = 0 if gs["state"] in ("draw","claimable-draw") else (MATE if ((gs["state"]=="red-wins")==stm_red) else -MATE)
        got = ends[-1]
        print(f"    expected optional value {want} for {gs['state']}; engine {got}  MATCH={got[0] and got[1]==want}")
