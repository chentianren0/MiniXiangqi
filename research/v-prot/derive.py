"""Contract-derived chase adjudication. Reads only docs/xiangqi-rules.md + reconciliation Q1/Q3/Q5/Q6.
No engine call anywhere in this file."""
import sys, json, pathlib
sys.path.insert(0,'/Users/tianren/coding/minixiangqi/discussion-drafts/v-prot')
from mxq import *

CHASERS = {"R","C","N"}          # kings and soldiers never chase (Q6)
TARGET_EXEMPT = {"K","P"}        # kings and soldiers are never chase targets

def facing_kings(b):
    kw, kb = king_sq(b,"w"), king_sq(b,"b")
    if not kw or not kb or kw[0]!=kb[0]: return False
    lo,hi = sorted((kw[1],kb[1]))
    return all((kw[0],rr) not in b for rr in range(lo+1,hi))

def move_legal_in(b, mv, c):
    b2 = apply_move(b, mv)
    return (not in_check(b2,c)) and (not facing_kings(b2))

def protected(b, victim_sq, chaser_sq, strict_king=False, verbose=False):
    """Contract Q1 protection test, evaluated on board b (chaser still on chaser_sq)."""
    vc = color(b[victim_sq])
    post = dict(b); del post[victim_sq]; post[victim_sq] = post.pop(chaser_sq)  # chaser captures
    probe = dict(b); del probe[chaser_sq]                                      # chaser removed, victim stands
    defenders = []
    for s,p in probe.items():
        if s == victim_sq or color(p) != vc: continue
        if victim_sq not in attacks(probe, s): continue
        if kind(p) == "K":
            # accepted interpretation: judged on the flying-generals condition alone
            after = dict(post); after[victim_sq] = after.pop(s)
            ok = not facing_kings(after)
            if strict_king:
                ok = ok and not in_check(after, vc)
        else:
            after = dict(post); after[victim_sq] = after.pop(s)
            ok = (not in_check(after, vc)) and (not facing_kings(after))
        if ok: defenders.append((sqname(*s), p))
    if verbose: return bool(defenders), defenders
    return bool(defenders)

def chased_by(b1, mv, mover_color, strict_king=False):
    """Pieces of the non-mover side that mv puts under a renewed chasing attack."""
    b2 = apply_move(b1, mv)
    them = "b" if mover_color=="w" else "w"
    out = {}
    for vs, vp in b2.items():
        if color(vp) != them or kind(vp) in TARGET_EXEMPT: continue
        for cs, cp in b2.items():
            if color(cp) != mover_color or kind(cp) not in CHASERS: continue
            if vs not in attacks(b2, cs): continue
            # renewal: did this piece attack this victim FROM THIS SQUARE before the move?
            before = None
            if cs in b1 and b1[cs] == cp:
                before = vs in attacks(b1, cs)
            elif cs == mv[1]:
                before = vs in attacks(b1, mv[0]) if False else None
            if before is True: continue          # attack already stood from this square
            # same-type exclusion unless the target is pinned
            if kind(cp) == kind(vp):
                probe = dict(b2); vic = probe.pop(vs)
                if not in_check(probe, them) and not facing_kings(probe): continue
            # value override: horse or cannon attacking a chariot is always a chase
            if kind(cp) in ("N","C") and kind(vp) == "R":
                out.setdefault(vs, []).append((sqname(*cs), cp, "value")); continue
            if not protected(b2, vs, cs, strict_king):
                out.setdefault(vs, []).append((sqname(*cs), cp, "unprotected"))
    return out

def adjudicate(start, moves, strict_king=False, verbose=True):
    b, stm, half, full = parse_fen(start)
    boards=[dict(b)]; stms=[stm]; ids={s:i for i,s in enumerate(sorted(b))}
    idmap=[dict(ids)]; keys=[" ".join(to_fen(b,stm,0,1).split()[:2])]
    chases=[]; checks=[in_check(b,stm)]
    for m in moves:
        a,t = parse_sq(m[:2]), parse_sq(m[2:])
        ch = chased_by(b,(a,t),stm,strict_king)
        # map chased squares to piece identity
        newids = dict(ids)
        if t in newids: del newids[t]
        newids[t] = newids.pop(a)
        chases.append((stm, m, {newids[s]: v for s,v in ch.items()}, {sqname(*s):v for s,v in ch.items()}))
        b = apply_move(b,(a,t)); ids = newids
        stm = "b" if stm=="w" else "w"
        boards.append(dict(b)); stms.append(stm); idmap.append(dict(ids))
        keys.append(" ".join(to_fen(b,stm,0,1).split()[:2]))
        checks.append(in_check(b,stm))
    return boards, stms, keys, chases, checks

def report(fid, start, moves, strict_king=False):
    boards, stms, keys, chases, checks = adjudicate(start, moves, strict_king)
    fk = keys[-1]; occ = [i for i,k in enumerate(keys) if k==fk]
    print(f"  occurrences of the final position: plies {occ} (count {len(occ)})")
    span_start = occ[-3] if len(occ)>=3 else 0
    print(f"  span begins at ply {span_start}")
    for side in ("w","b"):
        sets=[]
        for i,(stm,m,byid,bysq) in enumerate(chases):
            if i < span_start or stm != side: continue
            sets.append((i+1,m,set(byid),bysq))
        if not sets: continue
        common = set.intersection(*[s[2] for s in sets]) if sets else set()
        print(f"  {'Red' if side=='w' else 'Black'} moves in span:")
        for ply,m,ids_,bysq in sets:
            print(f"     ply {ply} {m}: chases {bysq if bysq else '{}'}")
        print(f"     -> same piece chased by EVERY move: {'YES' if common else 'no'} {sorted(common)}")
    # perpetual check
    for side in ("w","b"):
        them = "b" if side=="w" else "w"
        turns = [i for i in range(span_start, len(checks)) if stms[i]==them]
        allchk = all(checks[i] for i in turns) if turns else False
        if allchk: print(f"  {'Red' if side=='w' else 'Black'} perpetually checks")
    return occ
