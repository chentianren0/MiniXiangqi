import sys, json, pathlib
sys.path.insert(0,"/Users/tianren/coding/minixiangqi/discussion-drafts/w-base")
import pyffish as sf
print("engine:", sf.info())
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
D = pathlib.Path("/Users/tianren/coding/minixiangqi/fx-mutual-chase/fixtures/rules")
for fid in ["mx-chs-033","mx-chs-034","mx-mix-002","mx-mix-003"]:
    fx = json.loads((D/(fid+".json")).read_text())
    s, mv, a = fx["start_fen"], fx["moves"], fx["assertions"]
    print("="*70); print(fid, fx["title"])
    print(" start:", s)
    ok = True
    for i in range(len(mv)):
        legal = sf.legal_moves("mxq_target", s, mv[:i])
        if mv[i] not in legal:
            print(f"  PLY {i}: ILLEGAL {mv[i]} ; legal={sorted(legal)}"); ok=False; break
    print("  all moves legal:", ok)
    fens = [sf.get_fen("mxq_target", s, mv[:i]) for i in range(len(mv)+1)]
    for i,f in enumerate(fens):
        chk = sf.gives_check("mxq_target", s, mv[:i])
        print(f"   ply {i}: {f}   in_check={chk}")
    print("  result_fen match:", fens[-1]==a["result_fen"], repr(fens[-1]))
    print("  in_check match:", sf.gives_check("mxq_target",s,mv)==a["in_check"])
    # occurrence structure: placement+stm equality
    key = lambda f: " ".join(f.split()[:2])
    k0 = key(fens[0])
    occ = [i for i,f in enumerate(fens) if key(f)==k0]
    print("  occurrences of start position at plies:", occ, " count:", len(occ))
    # optional end at each prefix
    for L in range(0, len(mv)+1):
        e,v = sf.is_optional_game_end("mxq_target", s, mv[:L])
        e2,v2 = sf.is_optional_game_end("mxq_control", s, mv[:L])
        print(f"   prefix {L}: target={e,v}  control={e2,v2}")
    print("  asserted:", a["game_state"], " boundary:", fx["boundary"])
