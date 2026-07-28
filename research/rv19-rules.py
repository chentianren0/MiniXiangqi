import sys, random, collections
sys.path.insert(0,'r-scratch')
import pyffish as sf
V='minixiangqi'; START='rcnkncr/p1ppp1p/7/7/7/P1PPP1P/RCNKNCR w - - 0 1'
def board_map(fen):
    rows=fen.split()[0].split('/'); m={}
    for ri,row in enumerate(rows):
        rank=7-ri; f=0
        for ch in row:
            if ch.isdigit(): f+=int(ch)
            else:
                m['abcdefg'[f]+str(rank)]=ch; f+=1
    return m
def stm(fen): return fen.split()[1]
def gen_sq(fen,side):
    m=board_map(fen); t='K' if side=='w' else 'k'
    for s,p in m.items():
        if p==t: return s
    return None
def in_check(fen): return sf.gives_check(V,fen,[])  # side to move in check?
random.seed(7)
viol_a=viol_b=viol_c=0; n=0; checks=0
# random walk over many games
for game in range(300):
    fen=START; hist=[]
    for ply in range(60):
        moves=sf.legal_moves(V,fen,[])
        if not moves: break
        # A: is any legal move a capture of a general?
        m=board_map(fen); side=stm(fen)
        enemy_gen='k' if side=='w' else 'K'
        for mv in moves:
            if m.get(mv[2:4])==enemy_gen:
                viol_a+=1; print('*** GENERAL CAPTURABLE:',fen,mv)
        mv=random.choice(moves)
        prev=fen
        fen=sf.get_fen(V,fen,[mv]); n+=1
        if sf.gives_check(V,prev,[mv]):
            checks+=1
            # B: side to move is now in check. Is the checked general on either cell of the last move?
            cs=stm(fen); g=gen_sq(fen,cs)
            if g in (mv[0:2],mv[2:4]):
                viol_b+=1; print('*** BRACKET/CHECK COLLISION:',fen,mv,g)
            # C: is the *other* side (the mover) also in check?  (two generals in check)
            # build a null-ish test: flip side to move
            parts=fen.split(); parts[1]= 'w' if parts[1]=='b' else 'b'
            try:
                if sf.gives_check(V,' '.join(parts),[]):
                    viol_c+=1; print('*** BOTH IN CHECK:',fen)
            except Exception: pass
print(f'positions {n}, check events {checks}')
print(f'violations: general-capturable={viol_a}  brackets-on-checked-general={viol_b}  both-in-check={viol_c}')
print()
print('--- flying generals (mx-end-003 style) ---')
f='3k3/7/7/3R3/7/7/3K3 w - - 0 1'
print(f, sorted(sf.legal_moves(V,f,[])))
print('--- illegal position: general IS generated as a capture target ---')
f2='3k3/7/7/7/3R3/7/3K3 w - - 0 1'
mv=sf.legal_moves(V,f2,[]); print(f2,'-> d3d7 in legal moves:', 'd3d7' in mv)
print('--- can the two generals face / capture each other? ---')
f3='3k3/7/7/7/7/7/3K3 w - - 0 1'
print(f3, sorted(sf.legal_moves(V,f3,[])))
