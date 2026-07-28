import json,pathlib,sys
sys.path.insert(0,'/Users/tianren/coding/minixiangqi/discussion-drafts/w-base')
import pyffish as sf
INI="""
[mxq_target:minixiangqi]
chasingRule = axf
nMoveRule = 0
promotedSoldiersChaseable = false
"""
sf.load_variant_config(INI)
V="mxq_target"
D=pathlib.Path('/Users/tianren/coding/minixiangqi/fx-patch-gated/fixtures/rules')
def key(fen):
    p=fen.split(); return p[0]+" "+p[1]
for fid in ["mx-chs-028","mx-chs-029","mx-chs-030","mx-chs-031","mx-chs-032"]:
    o=json.loads((D/f"{fid}.json").read_text())
    start,moves=o['start_fen'],o['moves']
    print("="*70); print(fid, o['title'])
    print("start:",start,"| plies:",len(moves),"| moves:"," ".join(moves))
    fens=[]
    for i in range(len(moves)+1):
        f=sf.get_fen(V,start,moves[:i]); fens.append(f)
    finalkey=key(fens[-1])
    occ=[i for i,f in enumerate(fens) if key(f)==finalkey]
    print("final fen:",fens[-1])
    print("matches result_fen:",fens[-1]==o['assertions']['result_fen'])
    print("in_check engine:",sf.gives_check(V,start,moves),"asserted:",o['assertions']['in_check'])
    print("occurrences of final position at plies:",occ,"-> count",len(occ),"asserted at_occurrence",o['assertions']['game_state']['at_occurrence'])
    b=o['boundary']; pl=b['prefix_len']
    print("boundary prefix_len",pl,"-> that ply's fen:",fens[pl],"same position as final:",key(fens[pl])==finalkey)
    print("   occurrences up to and including prefix:",[i for i in occ if i<=pl])
    print("   engine at prefix:",sf.is_optional_game_end(V,start,moves[:pl]))
    print("   engine at final:",sf.is_optional_game_end(V,start,moves))
    # legality trace
    for i,m in enumerate(moves):
        lm=sf.legal_moves(V,start,moves[:i])
        assert m in lm, (fid,i,m)
    print("   all moves legal at their turn: True")
    # per-ply optional end scan
    scan=[]
    for i in range(1,len(moves)+1):
        e,v=sf.is_optional_game_end(V,start,moves[:i])
        scan.append(f"{i}:{'-' if not e else v}")
    print("   per-ply optional-end:", " ".join(scan))
