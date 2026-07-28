import sys, json, pathlib
sys.path.insert(0,'/Users/tianren/coding/minixiangqi/discussion-drafts/v-prot')
import derive
from derive import *
from mxq import *
D = pathlib.Path('/Users/tianren/coding/minixiangqi/fx-protection/fixtures/rules')
print("### start-position sanity")
for n in range(5,14):
    fid=f"mx-chs-{n:03d}"; fx=json.loads((D/f"{fid}.json").read_text())
    b,stm,_,_=parse_fen(fx['start_fen'])
    other = "b" if stm=="w" else "w"
    kw,kb = king_sq(b,"w"), king_sq(b,"b")
    kings_ok = kw is not None and kb is not None and in_palace("w",*kw) and in_palace("b",*kb)
    facing = derive.facing_kings(b)
    print(f"{fid}: pieces={len(b)} stm={stm} kings_in_palace={kings_ok} "
          f"side-not-to-move-in-check={in_check(b,other)} stm-in-check={in_check(b,stm)} facing_kings={facing} "
          f"in_check_asserted={fx['assertions']['in_check']}")

print("\n### mx-chs-007 robustness: drop the same-type (rook-vs-rook) exclusion")
orig = derive.CHASERS
import derive as dv
def chased_no_sametype(b1, mv, mover_color, strict_king=False):
    b2 = apply_move(b1, mv); them = "b" if mover_color=="w" else "w"; out={}
    for vs,vp in b2.items():
        if color(vp)!=them or kind(vp) in dv.TARGET_EXEMPT: continue
        for cs,cp in b2.items():
            if color(cp)!=mover_color or kind(cp) not in dv.CHASERS: continue
            if vs not in attacks(b2,cs): continue
            if cs in b1 and b1[cs]==cp and vs in attacks(b1,cs): continue
            if kind(cp) in ("N","C") and kind(vp)=="R":
                out.setdefault(vs,[]).append((sqname(*cs),cp,"value")); continue
            if not dv.protected(b2,vs,cs): out.setdefault(vs,[]).append((sqname(*cs),cp,"unprotected"))
    return out
fx=json.loads((D/"mx-chs-007.json").read_text())
for fn,label in ((dv.chased_by,"contract (same-type exclusion on)"),(chased_no_sametype,"same-type exclusion OFF")):
    dv.chased_by = fn
    boards,stms,keys,chases,checks = adjudicate(fx['start_fen'], fx['moves'])
    sets=[set(c[2]) for i,c in enumerate(chases) if c[0]=="w"]
    print(f"  {label}: per-Red-move chase sets {[c[3] for c in chases if c[0]=='w']}")
    print(f"     sustained on one piece: {bool(set.intersection(*sets))}")
    dv.chased_by = chased_by
