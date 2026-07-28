import sys
sys.path.insert(0, "/Users/tianren/coding/minixiangqi/discussion-drafts/w-base")
import pyffish as sf
sf.load_variant_config("[mxq_target:minixiangqi]\nchasingRule = axf\nnMoveRule = 0\npromotedSoldiersChaseable = false\n")
V="mxq_target"
def grid(fen):
    g={}
    for i,r in enumerate(fen.split()[0].split("/")):
        rank,f=7-i,0
        for ch in r:
            if ch.isdigit(): f+=int(ch)
            else: g["abcdefg"[f]+str(rank)]=ch; f+=1
    return g
def caps(fen, side):
    p=fen.split(); p[1]=side; f2=" ".join(p)
    g=grid(fen)
    out=[]
    for m in sf.legal_moves(V,f2,[]):
        t=m[2:4]
        if t in g and (g[t].isupper() != (side=="w")):
            out.append(f"{g[m[0:2]]}{m[0:2]}x{g[t]}{t}")
    return sorted(out)
CASES=[
 ("mx-chs-033","2k4/7/1cN1R2/7/4n2/7/1R2K2 w - - 0 1",["c5b3","e3f5","b3c5","f5e3"]*2),
 ("mx-chs-034","2k2r1/7/2N4/7/2r1nC1/7/4K2 w - - 0 1",["c5b3","e3f5","b3c5","f5e3"]*2),
 ("mx-mix-002","2k2r1/7/1cN1R2/7/2r1nC1/7/1R2K2 w - - 0 1",["c5b3","e3f5","b3c5","f5e3"]*2),
 ("mx-mix-003","3k3/7/c6/R6/7/7/4K2 w - - 0 1",["a4d4","d7c7","d4a4","c7d7"]*2),
]
for name,start,moves in CASES:
    print("="*66); print(name)
    for i in range(len(moves)+1):
        fen=sf.get_fen(V,start,moves[:i])
        mv=moves[i-1] if i else "(start)"
        print(f"  ply {i} after {mv:<6} W-attacks={caps(fen,'w')}  B-attacks={caps(fen,'b')}")
