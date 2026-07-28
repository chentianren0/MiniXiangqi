import sys, json, pathlib
sys.path.insert(0,"/Users/tianren/coding/minixiangqi/discussion-drafts/w-base")
import pyffish as sf
sf.load_variant_config("""
[mxq_target:minixiangqi]
chasingRule = axf
nMoveRule = 0
promotedSoldiersChaseable = false
""")
V="mxq_target"
FILES="abcdefg"
def board(fen):
    rows=fen.split()[0].split("/")
    b={}
    for ri,row in enumerate(rows):
        rank=7-ri; f=0
        for ch in row:
            if ch.isdigit(): f+=int(ch)
            else:
                b[FILES[f]+str(rank)]=ch; f+=1
    return b
def to_fen(b, stm):
    rows=[]
    for rank in range(7,0,-1):
        row=""; empty=0
        for f in FILES:
            p=b.get(f+str(rank))
            if p: 
                if empty: row+=str(empty); empty=0
                row+=p
            else: empty+=1
        if empty: row+=str(empty)
        rows.append(row)
    return "/".join(rows)+f" {stm} - - 0 1"
def attackers(fen, sq):
    """pieces of the side NOT owning sq that have a legal capture onto sq"""
    b=board(fen); occ=b.get(sq)
    assert occ, sq
    side = 'w' if occ.isupper() else 'b'
    enemy = 'b' if side=='w' else 'w'
    f=to_fen(b, enemy)
    return sorted({m[:2] for m in sf.legal_moves(V,f,[]) if m[2:4]==sq})
def defenders(fen, sq):
    """swap the occupant to the enemy colour, ask its own side for captures onto sq"""
    b=dict(board(fen)); occ=b[sq]
    side = 'w' if occ.isupper() else 'b'
    b[sq] = occ.lower() if occ.isupper() else occ.upper()
    f=to_fen(b, side)
    return sorted({m[:2] for m in sf.legal_moves(V,f,[]) if m[2:4]==sq})
D=pathlib.Path("/Users/tianren/coding/minixiangqi/fx-mutual-chase/fixtures/rules")
TARGETS={"mx-chs-033":["b5"],"mx-chs-034":["f3"],"mx-mix-002":["b5","f3"],"mx-mix-003":["a5"]}
for fid,tgts in TARGETS.items():
    fx=json.loads((D/(fid+".json")).read_text()); s,mv=fx["start_fen"],fx["moves"]
    print("="*72); print(fid)
    fens=[sf.get_fen(V,s,mv[:i]) for i in range(len(mv)+1)]
    for tgt in tgts:
        print(f" target {tgt}:")
        for i,f in enumerate(fens):
            b=board(f)
            # follow the target piece even if the square is only conceptual
            if tgt not in b: print(f"   ply {i}: target square empty!"); continue
            print(f"   ply {i}: piece={b[tgt]} attackers={attackers(f,tgt)} defenders={defenders(f,tgt)}")
    # full attack map: every enemy piece each side attacks
    print(" full attack map (attacker->victim) per ply:")
    for i,f in enumerate(fens):
        b=board(f)
        out={}
        for stm,label in (('w','W'),('b','B')):
            fx2=to_fen(b,stm)
            caps=sorted({(m[:2],m[2:4]) for m in sf.legal_moves(V,fx2,[]) if m[2:4] in b and (b[m[2:4]].isupper() != (stm=='w'))})
            out[label]=[f"{a}x{v}({b[v]})" for a,v in caps]
        print(f"   ply {i}: W:{out['W']}  B:{out['B']}")
