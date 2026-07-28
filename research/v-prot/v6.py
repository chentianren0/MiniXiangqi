import sys, json, pathlib
sys.path.insert(0,'/Users/tianren/coding/minixiangqi/discussion-drafts/v-prot')
from mxq import *
D = pathlib.Path('/Users/tianren/coding/minixiangqi/fx-protection/fixtures/rules')
def bd(fid):
    fx=json.loads((D/f"{fid}.json").read_text()); b,_,_,_=parse_fen(fx['start_fen'])
    return {sqname(*s):p for s,p in b.items()}, fx
pairs=[("mx-chs-002","mx-chs-005"),("mx-chs-006","mx-chs-007"),("mx-chs-006","mx-chs-008"),
       ("mx-chs-006","mx-chs-009"),("mx-chs-009","mx-chs-010"),("mx-chs-010","mx-chs-011"),
       ("mx-chs-002","mx-chs-013"),("mx-chs-010","mx-chs-012")]
for a,b in pairs:
    A,fa=bd(a); B,fb=bd(b)
    only_a={k:v for k,v in A.items() if B.get(k)!=v}
    only_b={k:v for k,v in B.items() if A.get(k)!=v}
    ga=fa['assertions']['game_state']['state']; gb=fb['assertions']['game_state']['state']
    same_moves = fa['moves']==fb['moves']
    print(f"{a} -> {b}: removed/changed={only_a}  added/changed={only_b}  same_moves={same_moves}  {ga} -> {gb}")
print()
# slate cross-check
SLATE = {
 "mx-chs-005": ("4k2/7/c3r2/7/1R5/7/2K1R2 w - - 0 1", ["b3a3","a5b5","a3b3","b5a5"], "black-wins"),
 "mx-chs-006": ("3k3/4R2/2c4/7/7/7/2K4 w - - 0 1",    ["e6e5","c5c6","e5e6","c6c5"], "black-wins"),
 "mx-chs-007": ("3k3/4R2/2c3r/7/7/7/2K4 w - - 0 1",   ["e6e5","c5c6","e5e6","c6c5"], "claimable-draw"),
 "mx-chs-008": ("3k3/1p2R2/2c4/7/7/7/2K4 w - - 0 1",  ["e6e5","c5c6","e5e6","c6c5"], "claimable-draw"),
 "mx-chs-009": ("2k4/4R2/2c4/7/7/7/2K4 w - - 0 1",    ["e6e5","c5c6","e5e6","c6c5"], "black-wins"),
 "mx-chs-010": ("2k4/4R2/2c4/7/7/7/3K3 w - - 0 1",    ["e6e5","c5c6","e5e6","c6c5"], "claimable-draw"),
 "mx-chs-011": ("2k4/4R2/2c4/1N5/7/7/3K3 w - - 0 1",  ["e6e5","c5c6","e5e6","c6c5"], "claimable-draw"),
 "mx-chs-012": ("7/7/1ck4/7/7/7/R3K2 w - - 0 1",      ["a1b1","b5a5","b1a1","a5b5"], "black-wins"),
 "mx-chs-013": ("4k2/7/c3c2/7/1R5/7/2K4 w - - 0 1",   ["b3a3","a5b5","a3b3","b5a5"], "black-wins"),
}
for fid,(fen,cycle,state) in SLATE.items():
    fx=json.loads((D/f"{fid}.json").read_text())
    ok_fen = fx['start_fen']==fen
    ok_mv  = fx['moves']==cycle*2
    ok_st  = fx['assertions']['game_state']['state']==state
    ok_occ = fx['assertions']['game_state']['at_occurrence']==3
    ok_bd  = fx['boundary']['prefix_len']==4
    print(f"{fid}: slate fen={ok_fen} moves=M8x2 {ok_mv} state={ok_st} occ3={ok_occ} prefix4={ok_bd}")
