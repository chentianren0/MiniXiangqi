"""Independent Mini Xiangqi model: my own attack generation, no engine."""
FILES="abcdefg"
def parse(fen):
    b={}; rows=fen.split()[0].split("/")
    assert len(rows)==7
    for ri,row in enumerate(rows):
        rank=7-ri; f=0
        for ch in row:
            if ch.isdigit(): f+=int(ch)
            else:
                b[FILES[f]+str(rank)]=ch; f+=1
        assert f==7, (row,f)
    return b, fen.split()[1]
def sq(f,r): return FILES[f]+str(r)
def idx(s): return FILES.index(s[0]), int(s[1])
def onb(f,r): return 0<=f<7 and 1<=r<=7

def attacks(b, s):
    """squares attacked (capture-capable) by piece at s"""
    p=b[s]; f,r=idx(s); up=p.isupper(); t=p.lower(); out=set()
    if t=='r':
        for df,dr in ((1,0),(-1,0),(0,1),(0,-1)):
            nf,nr=f+df,r+dr
            while onb(nf,nr):
                out.add(sq(nf,nr))
                if sq(nf,nr) in b: break
                nf+=df; nr+=dr
    elif t=='n':
        for df,dr,lf,lr in ((1,2,0,1),(-1,2,0,1),(1,-2,0,-1),(-1,-2,0,-1),
                            (2,1,1,0),(2,-1,1,0),(-2,1,-1,0),(-2,-1,-1,0)):
            if sq(f+lf,r+lr) in b if onb(f+lf,r+lr) else True: continue
            if onb(f+df,r+dr): out.add(sq(f+df,r+dr))
    elif t=='c':
        for df,dr in ((1,0),(-1,0),(0,1),(0,-1)):
            nf,nr=f+df,r+dr; screens=0
            while onb(nf,nr):
                if sq(nf,nr) in b:
                    screens+=1
                    if screens==2: out.add(sq(nf,nr)); break
                nf+=df; nr+=dr
    elif t=='k':
        for df,dr in ((1,0),(-1,0),(0,1),(0,-1)):
            if onb(f+df,r+dr): out.add(sq(f+df,r+dr))   # palace filter applied by caller
        # flying general
        for dr in (1,-1):
            nr=r+dr
            while 1<=nr<=7:
                if sq(f,nr) in b:
                    if b[sq(f,nr)].lower()=='k': out.add(sq(f,nr))
                    break
                nr+=dr
    elif t=='p':
        fwd = 1 if up else -1
        for df,dr in ((0,fwd),(1,0),(-1,0)):
            if onb(f+df,r+dr): out.add(sq(f+df,r+dr))
    return out

def attackers_of(b, target, by_white):
    res={}
    for s,p in b.items():
        if p.isupper()!=by_white: continue
        if target in attacks(b,s): res[s]=p
    return res

def apply(b, mv):
    b=dict(b); b[mv[2:4]]=b.pop(mv[0:2]); return b

def report(name, fen, moves, target_desc):
    b,_=parse(fen)
    print("="*72); print(name)
    seq=[b]
    for m in moves:
        b=apply(b,m); seq.append(b)
    return seq
