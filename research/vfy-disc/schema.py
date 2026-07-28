import json, pathlib, sys
D = pathlib.Path("/Users/tianren/coding/minixiangqi/fx-discovery/fixtures/rules")
NEW = ["mx-chs-026","mx-chs-027","mx-mix-004"]
APPROVED = [p.stem for p in sorted(D.glob("mx-*.json")) if p.stem not in NEW]
print("approved count:", len(APPROVED), APPROVED)

def keys(o): return list(o.keys())
ref = json.loads((D/"mx-chs-001.json").read_text())
print("ref top keys:", keys(ref))
print("ref assert keys:", keys(ref["assertions"]))
print("ref gs keys:", keys(ref["assertions"]["game_state"]))
print("ref boundary keys:", keys(ref["boundary"]))
print()
for n in NEW:
    p = D/(n+".json")
    raw = p.read_text()
    o = json.loads(raw)
    rt = json.dumps(o, indent=2, ensure_ascii=False) + "\n"
    print(n)
    print("  byte-exact indent2 roundtrip:", rt == raw)
    print("  top keys match ref:", keys(o) == keys(ref), keys(o))
    print("  assert keys match ref:", keys(o["assertions"]) == keys(ref["assertions"]), keys(o["assertions"]))
    print("  gs keys:", keys(o["assertions"]["game_state"]))
    print("  boundary keys:", keys(o["boundary"]))
    print("  id==stem:", o["id"]==p.stem, " area==idseg:", o["area"]==p.stem.split("-")[1])
    print("  variant:", o["variant"], " nullfields:", o["assertions"]["legal_moves"], o["assertions"]["rejected_moves"], o["assertions"]["applied"])
    print("  state/reason/occ:", o["assertions"]["game_state"])
    print("  trailing newline:", raw.endswith("\n"), " no CRLF:", "\r" not in raw)
    print("  moves len:", len(o["moves"]))
