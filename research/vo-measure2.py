#!/usr/bin/env python3
import sys, random, statistics, collections
sys.path.insert(0, "/Users/tianren/coding/minixiangqi/discussion-drafts/w-base")
import pyffish as sf
V = "minixiangqi"; START = sf.start_fen(V)
random.seed(20260728)

FILES = "abcdefg"
def occ_of(fen):
    o = {}
    for i, row in enumerate(fen.split()[0].split("/")):
        rank = 7 - i; f = 0
        for ch in row:
            if ch.isdigit(): f += int(ch)
            else: o[FILES[f]+str(rank)] = ch; f += 1
    return o

amb = 0; tot = 0
nonempty_ranks = []; pieces_per_rank = []
dup_dest = []           # pairs of same-type pieces sharing a destination
check_frac = 0
capture_frac = []
for game in range(120):
    moves = []
    for ply in range(120):
        lm = sf.legal_moves(V, START, moves)
        if not lm: break
        fen = sf.get_fen(V, START, moves); o = occ_of(fen)
        stm = fen.split()[1]
        # ranks
        cnt = collections.Counter(int(sq[1]) for sq in o)
        nonempty_ranks.append(sum(1 for r in range(1,8) if cnt.get(r,0)>0))
        for r in range(1,8): pieces_per_rank.append(cnt.get(r,0))
        # ambiguity: >=2 movable pieces of same type
        origins = {m[:2] for m in lm}
        types = collections.Counter(o[s].lower() for s in origins)
        tot += 1
        if any(v >= 2 for v in types.values()): amb += 1
        # captures available
        capture_frac.append(sum(1 for m in lm if m[2:] in o)/len(lm))
        # same-type pieces sharing a destination
        bydest = collections.defaultdict(list)
        for m in lm: bydest[m[2:]].append(o[m[:2]].lower())
        dup_dest.append(sum(1 for d,v in bydest.items() if len(v)!=len(set(v))))
        
        moves.append(random.choice(lm))

print("positions:", tot)
print("fraction with >=2 movable pieces of the SAME type:", round(amb/tot, 4))
print("non-empty ranks per position: median", statistics.median(nonempty_ranks),
      "mean", round(statistics.mean(nonempty_ranks),2),
      "max", max(nonempty_ranks))
pr = sorted(pieces_per_rank)
print("pieces per rank: median", statistics.median(pr), "mean", round(statistics.mean(pr),2),
      "p95", pr[int(.95*len(pr))], "max", pr[-1],
      "empty-rank fraction", round(sum(1 for x in pr if x==0)/len(pr),4))
print("destinations reachable by >1 piece of the same type: mean per position",
      round(statistics.mean(dup_dest),3), "max", max(dup_dest))
print("fraction of legal moves that are captures: mean", round(statistics.mean(capture_frac),4))
