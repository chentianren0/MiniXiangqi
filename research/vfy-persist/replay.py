#!/usr/bin/env python3
"""Independent replay of the fx-persistence fixtures. Written from scratch."""
import json, pathlib, sys, collections

sys.path.insert(0, "/Users/tianren/coding/minixiangqi/discussion-drafts/w-base")
import pyffish as sf

MATE = 32000
TARGET = "mxq_target"
INI = """
[mxq_target:minixiangqi]
chasingRule = axf
nMoveRule = 0
promotedSoldiersChaseable = false
"""
sf.load_variant_config(INI)
print("engine:", sf.info())

FX = pathlib.Path("/Users/tianren/coding/minixiangqi/fx-persistence/fixtures/rules")

def key(fen):
    p = fen.split()
    return (p[0], p[1])

def opt(start, moves):
    e, v = sf.is_optional_game_end(TARGET, start, list(moves))
    return (e, v if e else None)

for fid in sys.argv[1:] or ["mx-chs-020","mx-chs-021","mx-chs-022","mx-chs-023","mx-chs-024","mx-chs-025"]:
    fx = json.loads((FX / f"{fid}.json").read_text())
    start, moves = fx["start_fen"], fx["moves"]
    a = fx["assertions"]
    print("="*70)
    print(fid, "|", fx["title"])
    # 1. legality + per-ply trace
    fens = [sf.get_fen(TARGET, start, [])]
    ok = True
    for i, m in enumerate(moves):
        legal = sf.legal_moves(TARGET, start, moves[:i])
        if m not in legal:
            print(f"  ILLEGAL move {i} {m}"); ok = False; break
        fens.append(sf.get_fen(TARGET, start, moves[:i+1]))
    if not ok: continue
    print(f"  all {len(moves)} moves legal")
    # 2. result fen / in_check
    final = fens[-1]
    print(f"  result_fen engine={final!r}")
    print(f"             asserted={a['result_fen']!r}  {'MATCH' if final==a['result_fen'] else 'MISMATCH'}")
    ic = sf.gives_check(TARGET, start, moves)
    print(f"  in_check engine={ic} asserted={a['in_check']}  {'MATCH' if ic==a['in_check'] else 'MISMATCH'}")
    # 3. occurrence plies of the FINAL position
    k = key(final)
    occ = [i for i, f in enumerate(fens) if key(f) == k]
    print(f"  final-position occurrence plies: {occ} -> count {len(occ)}; asserted at_occurrence={a['game_state'].get('at_occurrence')}")
    # 4. optional-end scan over every prefix
    print("  prefix scan (ply: ended,value):")
    row = []
    for n in range(len(moves)+1):
        e, v = opt(start, moves[:n])
        row.append(f"{n}:{'-' if not e else v}")
    print("    " + "  ".join(row))
    # 5. earliest MATE-valued (automatic terminal) prefix
    mates = [n for n in range(len(moves)+1) if (lambda ev: ev[0] and abs(ev[1])==MATE)(opt(start,moves[:n]))]
    print(f"  automatic-terminal (|value|=MATE) prefixes: {mates}")
    zeros = [n for n in range(len(moves)+1) if (lambda ev: ev[0] and ev[1]==0)(opt(start,moves[:n]))]
    print(f"  claimable-draw (value 0) prefixes:          {zeros}")
    # 6. final state vs assertion
    e, v = opt(start, moves)
    gs = a["game_state"]
    stm_red = final.split()[1] == "w"
    if gs["state"] in ("claimable-draw","draw"): want = 0
    else: want = MATE if ((gs["state"]=="red-wins")==stm_red) else -MATE
    print(f"  engine final: ended={e} value={v}; expected value for {gs['state']}/{gs['reason']} = {want}  {'MATCH' if (e and v==want) else 'MISMATCH'}")
    # 7. boundary
    b = fx.get("boundary")
    if b:
        eb, vb = opt(start, moves[:b["prefix_len"]])
        pf = sf.get_fen(TARGET, start, moves[:b["prefix_len"]])
        pocc = [i for i, f in enumerate(fens[:b["prefix_len"]+1]) if key(f) == key(pf)]
        print(f"  boundary prefix_len={b['prefix_len']}: fen={pf!r} ended={eb} value={vb}")
        print(f"    occurrences of THAT position up to the prefix: {pocc}")
        print(f"    expect note: {b['expect']!r}")
