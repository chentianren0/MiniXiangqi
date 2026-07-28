import json, os, sys, collections
d="/Users/tianren/coding/minixiangqi/fx-mutual-chase/fixtures/rules"
files=sorted(f for f in os.listdir(d) if f.endswith(".json"))
new={"mx-chs-033.json","mx-chs-034.json","mx-mix-002.json","mx-mix-003.json"}
shapes=collections.defaultdict(list)
for f in files:
    p=os.path.join(d,f)
    raw=open(p,encoding="utf-8").read()
    obj=json.loads(raw, object_pairs_hook=collections.OrderedDict)
    canon=json.dumps(obj,indent=2,ensure_ascii=False)+"\n"
    byte_ok = (canon==raw)
    top=tuple(obj.keys())
    a=obj["assertions"]
    ak=tuple(a.keys())
    gs=a.get("game_state")
    gk=tuple(gs.keys()) if isinstance(gs,dict) else None
    bk=tuple(obj["boundary"].keys()) if obj.get("boundary") else None
    shapes[(top,ak,gk,bk)].append(f)
    if f in new:
        print(f, "byte_canonical=",byte_ok)
        print("   top:",top)
        print("   assertions:",ak)
        print("   game_state:",gk,"boundary:",bk)
        print("   id/file match:", obj["id"]+".json"==f, "| area:",obj["area"], "| variant:",obj["variant"])
print("\n--- distinct shapes across all", len(files),"files:")
for k,v in shapes.items():
    print(len(v), v)
    print("   ",k)
