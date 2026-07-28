import json, pathlib, sys
sys.path.insert(0, '/Users/tianren/coding/minixiangqi/discussion-drafts/vfy-chk')
import indep_rules as R

FX = pathlib.Path('/Users/tianren/coding/minixiangqi/fx-perpetual-check/fixtures/rules')
for fid in ('mx-chk-003','mx-chk-004','mx-mix-001'):
    fx = json.loads((FX/f'{fid}.json').read_text())
    print('='*78); print(fid, '|', fx['title'])
    st = R.parse_fen(fx['start_fen'])
    # position identity per contract line 38: placement + side to move only
    def key(s): return R.make_fen(*s).rsplit(' ', 2)[0]
    seen = {}
    trace = []
    states = [st]
    for m in fx['moves']:
        states.append(R.step(states[-1], m))
    for i, s in enumerate(states):
        k = key(s)
        seen.setdefault(k, []).append(i)
        stm = s[1]
        opp = 'b' if stm == 'w' else 'w'
        ic_stm = R.in_check(s[0], stm)
        # who just moved delivered the check? at ply i (i>0) the mover was opp
        trace.append((i, stm, ic_stm, k))
    print('  per-ply: ply/stm/in_check(stm)/occurrence#')
    for i, stm, ic, k in trace:
        occ = seen[k].index(i)+1
        mv = fx['moves'][i-1] if i else '-'
        print(f'   ply {i}  after {mv:5s} stm={stm} in_check={str(ic):5s} occ#{occ}  {k}')
    print('  check flags string:', ''.join('T' if t[2] else 'f' for t in trace))
    tgt = key(states[0])
    print('  target position occurrences at plies:', seen[tgt], '-> ply8 is occurrence', seen[tgt].index(8)+1)
    print('  distinct positions:', len(seen), '  any other position repeated 3x?',
          [p for p,v in seen.items() if len(v)>=3 and p!=tgt])
    # attribution: which side's moves deliver check
    red_checks = [i for i in range(1,9) if i%2==1 and trace[i][2]]   # after red move, black to move in check
    blk_checks = [i for i in range(1,9) if i%2==0 and trace[i][2]]
    print('  plies where RED\'s move left Black in check :', red_checks)
    print('  plies where BLACK\'s move left Red in check :', blk_checks)
    # chase probe: non-king enemy pieces attacked at each ply, per contract (kings & soldiers excluded as targets)
    for i, s in enumerate(states):
        b = s[0]
        for side in ('w','b'):
            opp = 'b' if side=='w' else 'w'
            att = R.attacks(b, side)
            tgts = sorted(R.name(*t) + b[t] for t in att if t in b and R.side_of(b[t])==opp and b[t].lower() not in 'kp')
            if tgts: print(f'    ply {i}: {side} attacks non-king/non-soldier {tgts}')
