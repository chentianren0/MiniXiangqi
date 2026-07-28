import json, pathlib, collections
D = pathlib.Path('/Users/tianren/coding/minixiangqi/fx-protection/fixtures/rules')
files = sorted(D.glob('mx-*.json'))
APPROVED = {"mx-chk-001","mx-chk-002","mx-chs-001","mx-chs-002","mx-chs-003","mx-chs-004",
            "mx-end-001","mx-end-002","mx-end-003","mx-move-001","mx-move-002","mx-move-003",
            "mx-move-004","mx-move-005","mx-move-006","mx-rep-001"}
ids = []
probs = []
for p in files:
    raw = p.read_bytes()
    text = raw.decode('utf-8')
    obj = json.loads(text, object_pairs_hook=collections.OrderedDict)
    fid = obj['id']
    ids.append(fid)
    tag = "APPROVED" if fid in APPROVED else "NEW"
    # serialization round trip
    ser = json.dumps(obj, indent=2, ensure_ascii=False) + "\n"
    ser_ok = ser == text
    # byte checks
    byte_ok = (b'\r' not in raw) and (b'\t' not in raw) and raw.endswith(b'\n') and not raw.endswith(b'\n\n')
    # key order
    top = list(obj.keys())
    asrt = list(obj['assertions'].keys())
    gs = list(obj['assertions']['game_state'].keys())
    bd = list(obj['boundary'].keys()) if obj.get('boundary') else None
    stem_ok = fid == p.stem
    area_ok = obj['area'] == fid.split('-')[1]
    var_ok = obj['variant'] == 'minixiangqi'
    print(f"{tag:8} {fid} ser={ser_ok} bytes={byte_ok} stem={stem_ok} area={area_ok} var={var_ok}")
    print(f"         top={top}")
    print(f"         asrt={asrt} gs={gs} bd={bd}")
    if not (ser_ok and byte_ok and stem_ok and area_ok and var_ok):
        probs.append(fid)
dupes = [k for k,v in collections.Counter(ids).items() if v>1]
print("\nduplicate ids:", dupes)
print("problem files:", probs)
