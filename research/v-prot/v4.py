import json, pathlib, sys
sys.path.insert(0,'/Users/tianren/coding/minixiangqi/discussion-drafts/v-prot')
from derive import *
D = pathlib.Path('/Users/tianren/coding/minixiangqi/fx-protection/fixtures/rules')
for n in range(5,14):
    fid=f"mx-chs-{n:03d}"
    fx=json.loads((D/f"{fid}.json").read_text())
    gs=fx['assertions']['game_state']
    print(f"=== {fid}  {fx['start_fen']}   recorded: {gs['state']}/{gs['reason']}@{gs['at_occurrence']}")
    report(fid, fx['start_fen'], fx['moves'])
    print()
