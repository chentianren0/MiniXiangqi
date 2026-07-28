import json, pathlib, sys
sys.path.insert(0, '/Users/tianren/coding/minixiangqi/discussion-drafts/w-base')
import pyffish as sf
print('engine:', sf.info())
INI = """
[mxq_target:minixiangqi]
chasingRule = axf
nMoveRule = 0
promotedSoldiersChaseable = false

[mxq_control:minixiangqi]
chasingRule = axf
nMoveRule = 0
"""
sf.load_variant_config(INI)
FX = pathlib.Path('/Users/tianren/coding/minixiangqi/fx-perpetual-check/fixtures/rules')
MATE = 32000
for fid in ('mx-chk-003','mx-chk-004','mx-mix-001'):
    fx = json.loads((FX/f'{fid}.json').read_text())
    print('='*78); print(fid, fx['assertions']['game_state'])
    for v in ('mxq_target','mxq_control','minixiangqi'):
        start, moves = fx['start_fen'], fx['moves']
        bad = []
        for i in range(len(moves)):
            if moves[i] not in sf.legal_moves(v, start, moves[:i]): bad.append((i,moves[i]))
        fen = sf.get_fen(v, start, moves)
        chk = sf.gives_check(v, start, moves)
        flags = ''.join('T' if sf.gives_check(v,start,moves[:i]) else 'f' for i in range(9))
        rows = []
        for n in (4, 8):
            e, val = sf.is_optional_game_end(v, start, moves[:n])
            rows.append(f'@{n}=({e}, {val if e else "-"})')
        print(f'  [{v:12s}] illegal={bad} fen_ok={fen==fx["assertions"]["result_fen"]} '
              f'in_check={chk}(want {fx["assertions"]["in_check"]}) flags={flags} ' + ' '.join(rows))
        print(f'                 fen={fen}')
