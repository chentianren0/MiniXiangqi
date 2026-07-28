import sys
sys.path.insert(0,'/Users/tianren/coding/minixiangqi/discussion-drafts/w-base')
import pyffish as sf
sf.load_variant_config("""
[mxq_target:minixiangqi]
chasingRule = axf
nMoveRule = 0
promotedSoldiersChaseable = false
""")
V="mxq_target"
def lm(fen,mv=[]): return sorted(sf.legal_moves(V,fen,mv))

print("--- 028: is the white chariot pinned on the d-file? ---")
s="3rk2/7/7/3R3/1c5/7/3K3 w - - 0 1"
mv=["d4d3","b3b4","d3d4","b4b3","d4d3","b3b4","d3d4","b4b3"]
for i in [0,2,4,6,8]:
    L=lm(s,mv[:i]); R=[m for m in L if m[:2] in ("d4","d3")]
    print(f" ply{i} white-chariot moves: {R}")
print(" any capture of the cannon anywhere in history:", [ (i,m) for i in range(0,9,2) for m in lm(s,mv[:i]) if m in ("d3b3","d4b4","d3b4","d4b3")])
print(" control: delete pinning chariot d7 ->", sf.is_optional_game_end(V,"4k2/7/7/3R3/1c5/7/3K3 w - - 0 1",mv))
print(" control: white king on c1 (pin gone) ->", sf.is_optional_game_end(V,"3rk2/7/7/3R3/1c5/7/2K4 w - - 0 1",mv))

print()
print("--- 029: is the black chariot pinned? ---")
s2="2k4/7/R6/2r4/7/2P4/2K4 w - - 0 1"
mv2=["a5a4","c4c5","a4a5","c5c4","a5a4","c4c5","a4a5","c5c4"]
print(" black chariot moves after a5a4:", [m for m in lm(s2,["a5a4"]) if m[:2]=="c4"])
print(" white soldier c2 moves at ply0:", [m for m in lm(s2) if m[:2]=="c2"])
print(" control: white king d1 instead of c1 ->", sf.is_optional_game_end(V,"2k4/7/R6/2r4/7/2P4/3K3 w - - 0 1",mv2))
print(" control: remove the soldier c2 ->", sf.is_optional_game_end(V,"2k4/7/R6/2r4/7/7/2K4 w - - 0 1",mv2))

print()
print("--- 030 entry move: does R on a1 already attack a5? ---")
s3="4k2/7/c6/7/7/7/R1K4 w - - 0 1"
print(" a-file chariot moves at ply0:", [m for m in lm(s3) if m[:2]=="a1"])
print(" (a1a5 present => the attack already stood on the a-file)")
print("--- 031 entry move b3a3: did R on b3 attack a5? ---")
s4="4k2/7/c6/7/1R5/7/2K4 w - - 0 1"
print(" chariot moves at ply0:", [m for m in lm(s4) if m[:2]=="b3"])
