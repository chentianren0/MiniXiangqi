"""Per-square protection probe + counterfactuals: does each fixture actually discriminate
the rule it claims to pin?  Contract only, no engine."""
import sys, json, pathlib
sys.path.insert(0,'/Users/tianren/coding/minixiangqi/discussion-drafts/v-prot')
import derive
from derive import *
from mxq import *

D = pathlib.Path('/Users/tianren/coding/minixiangqi/fx-protection/fixtures/rules')

def outcome(start, moves):
    boards, stms, keys, chases, checks = adjudicate(start, moves)
    fk=keys[-1]; occ=[i for i,k in enumerate(keys) if k==fk]; sp=occ[-3]
    res={}
    for side in ("w","b"):
        sets=[set(c[2]) for i,c in enumerate(chases) if i>=sp and c[0]==side]
        res[side]= bool(sets) and bool(set.intersection(*sets))
    if res["w"] and not res["b"]: return "black-wins/perpetual-chase"
    if res["b"] and not res["w"]: return "red-wins/perpetual-chase"
    if res["b"] and res["w"]: return "draw/mutual-perpetual-chase"
    return "claimable-draw/threefold-repetition"

ORIG_protected = derive.protected

print("### protection probe: for each shuttle square, who legally defends it (chaser removed)?")
for n in range(5,14):
    fid=f"mx-chs-{n:03d}"; fx=json.loads((D/f"{fid}.json").read_text())
    b0,stm,_,_ = parse_fen(fx['start_fen'])
    print(f"{fid}:")
    boards=[dict(b0)]; b=dict(b0); c=stm
    for i,m in enumerate(fx['moves'][:4]):
        a,t=parse_sq(m[:2]),parse_sq(m[2:]); b=apply_move(b,(a,t)); c="b" if c=="w" else "w"
        if c=="b":  # Red just moved: report protection of every black target the rook attacks
            for vs,vp in b.items():
                if color(vp)=="b" and kind(vp) not in ("K",) and vs in attacks(b,t):
                    ok,defs = ORIG_protected(b, vs, t, verbose=True)
                    print(f"   after {m}: chaser on {sqname(*t)} attacks {vp}{sqname(*vs)} -> protected={ok} defenders={defs}")

print("\n### counterfactuals (each toggle disables exactly the rule the fixture claims to pin)")
def with_protected(fn):
    derive.protected = fn
    return fn

def make(strip_xray=False, no_soldier_def=False, no_king_flying=False,
         king_anywhere=False, cannon_like_rook=False, ignore_pins=False, strict_king=False):
    def f(b, victim_sq, chaser_sq, sk=False, verbose=False):
        vc = color(b[victim_sq])
        post = dict(b); del post[victim_sq]; post[victim_sq]=post.pop(chaser_sq)
        probe = dict(b)
        if not strip_xray: del probe[chaser_sq]
        defs=[]
        for s,p in probe.items():
            if s==victim_sq or color(p)!=vc: continue
            if kind(p)=="P" and no_soldier_def: continue
            att = attacks(probe, s)
            if kind(p)=="C" and cannon_like_rook:
                q=dict(probe); q[s]="R" if color(p)=="w" else "r"; att=attacks(q,s)
            if kind(p)=="K" and king_anywhere:
                f2,r2=s; att=set()
                for df,dr in ((1,0),(-1,0),(0,1),(0,-1)):
                    if onboard(f2+df,r2+dr): att.add((f2+df,r2+dr))
            if victim_sq not in att: continue
            after=dict(post); after[victim_sq]=after.pop(s)
            if kind(p)=="K":
                ok = True if no_king_flying else (not facing_kings(after))
                if strict_king: ok = ok and not in_check(after, vc)
            else:
                ok = True if ignore_pins else ((not in_check(after,vc)) and (not facing_kings(after)))
            if ok: defs.append((sqname(*s),p))
        return (bool(defs),defs) if verbose else bool(defs)
    return f

cases = [
 ("mx-chs-005","pinned defender counted as protecting", dict(ignore_pins=True)),
 ("mx-chs-007","X-ray ignored (chaser NOT removed)",    dict(strip_xray=True)),
 ("mx-chs-008","soldier not allowed to defend",         dict(no_soldier_def=True)),
 ("mx-chs-009","flying-general condition not applied",  dict(no_king_flying=True)),
 ("mx-chs-010","king not allowed to defend at all",     dict(king_anywhere=False, no_soldier_def=False, strict_king=False)),
 ("mx-chs-011","strict king-recapture legality",        dict(strict_king=True)),
 ("mx-chs-012","king defends orthogonally outside palace", dict(king_anywhere=True)),
 ("mx-chs-013","cannon defends like a chariot",         dict(cannon_like_rook=True)),
]
for fid, label, kw in cases:
    fx=json.loads((D/f"{fid}.json").read_text())
    rec=fx['assertions']['game_state']; recs=f"{rec['state']}/{rec['reason']}"
    derive.protected = ORIG_protected
    base = outcome(fx['start_fen'], fx['moves'])
    derive.protected = make(**kw)
    alt = outcome(fx['start_fen'], fx['moves'])
    derive.protected = ORIG_protected
    flag = "DISCRIMINATES" if alt != base else "*** NOT DISCRIMINATING ***"
    print(f"{fid}: recorded={recs}  contract={base}  counterfactual[{label}]={alt}  {flag}")

print("\n### mx-chs-010 redone: disable king defence entirely")
def no_king_def(b, victim_sq, chaser_sq, sk=False, verbose=False):
    vc = color(b[victim_sq])
    post = dict(b); del post[victim_sq]; post[victim_sq]=post.pop(chaser_sq)
    probe = dict(b); del probe[chaser_sq]
    defs=[]
    for s,p in probe.items():
        if s==victim_sq or color(p)!=vc or kind(p)=="K": continue
        if victim_sq not in attacks(probe,s): continue
        after=dict(post); after[victim_sq]=after.pop(s)
        if (not in_check(after,vc)) and (not facing_kings(after)): defs.append((sqname(*s),p))
    return (bool(defs),defs) if verbose else bool(defs)
for fid in ("mx-chs-010","mx-chs-011"):
    fx=json.loads((D/f"{fid}.json").read_text())
    derive.protected = ORIG_protected; base=outcome(fx['start_fen'],fx['moves'])
    derive.protected = no_king_def;    alt=outcome(fx['start_fen'],fx['moves'])
    derive.protected = ORIG_protected
    print(f"{fid}: contract={base}  counterfactual[king never defends]={alt}  {'DISCRIMINATES' if alt!=base else '*** NOT ***'}")
