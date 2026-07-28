import json, pathlib, sys
sys.path.insert(0, '/Users/tianren/coding/minixiangqi/discussion-drafts/vfy-chk')
import indep_rules as R

FX = pathlib.Path('/Users/tianren/coding/minixiangqi/fx-perpetual-check/fixtures/rules')
bad = 0
for p in sorted(FX.glob('mx-*.json')):
    fx = json.loads(p.read_text())
    st = R.parse_fen(fx['start_fen'])
    errs = []
    for i, m in enumerate(fx['moves']):
        lm = R.legal_moves(st[0], st[1])
        if m not in lm: errs.append(f'ply{i} {m} illegal (model)')
        st = R.step(st, m)
    a = fx['assertions']
    got_fen = R.make_fen(*st)
    if got_fen != a['result_fen']: errs.append(f'result_fen model={got_fen}')
    ic = R.in_check(st[0], st[1])
    if ic != a['in_check']: errs.append(f'in_check model={ic}')
    if a['legal_moves'] is not None:
        lm = R.legal_moves(st[0], st[1])
        if sorted(lm) != sorted(a['legal_moves']): errs.append(f'legal_moves model={sorted(lm)}')
    for rj in a['rejected_moves'] or []:
        if rj in R.legal_moves(st[0], st[1]): errs.append(f'rejected {rj} was legal in model')
    for pr in a['applied'] or []:
        s2 = R.step(st, pr['move'])
        if R.make_fen(*s2) != pr['result_fen']: errs.append(f"probe {pr['move']} model={R.make_fen(*s2)}")
        if R.in_check(s2[0], s2[1]) != pr['in_check']: errs.append(f"probe {pr['move']} check model={R.in_check(s2[0],s2[1])}")
    print(f"{'FAIL' if errs else 'ok  '} {fx['id']}")
    for e in errs: print('     ', e); bad += 1
print('\nmodel disagreements:', bad)
