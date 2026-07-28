#!/usr/bin/env python3
"""Measure Mini Xiangqi position shape for the VoiceOver model:
branching factor, movable-piece count, per-piece destination counts, occupancy.
Random playouts from the frozen start FEN."""
import sys, random, statistics
sys.path.insert(0, "/Users/tianren/coding/minixiangqi/discussion-drafts/w-base")
import pyffish as sf

V = "minixiangqi"
START = sf.start_fen(V)
print("start_fen:", START)

random.seed(20260728)
branch = []          # legal moves per position
movable = []         # distinct origin squares with >=1 legal move
perpiece = []        # destinations per movable piece
occupied = []        # pieces on board
maxpiece = 0
maxpiece_ex = None
positions = 0

for game in range(400):
    moves = []
    for ply in range(120):
        lm = sf.legal_moves(V, START, moves)
        if not lm:
            break
        fen = sf.get_fen(V, START, moves)
        board = fen.split()[0]
        occupied.append(sum(1 for c in board if c.isalpha()))
        branch.append(len(lm))
        d = {}
        for m in lm:
            d.setdefault(m[:2], []).append(m[2:])
        movable.append(len(d))
        for org, dst in d.items():
            perpiece.append(len(dst))
            if len(dst) > maxpiece:
                maxpiece = len(dst); maxpiece_ex = (fen, org, sorted(dst))
        positions += 1
        moves.append(random.choice(lm))

def st(name, xs):
    xs = sorted(xs)
    print(f"{name:22s} n={len(xs):6d} min={xs[0]:3d} p25={xs[len(xs)//4]:3d} "
          f"median={statistics.median(xs):6.1f} mean={statistics.mean(xs):6.2f} "
          f"p75={xs[3*len(xs)//4]:3d} p95={xs[int(.95*len(xs))]:3d} max={xs[-1]:3d}")

print("positions sampled:", positions)
st("legal moves/position", branch)
st("movable pieces", movable)
st("destinations/piece", perpiece)
st("pieces on board", occupied)
print("max destinations for one piece:", maxpiece)
print("  example:", maxpiece_ex)
# start position specifics
lm0 = sf.legal_moves(V, START, [])
d0 = {}
for m in lm0:
    d0.setdefault(m[:2], []).append(m[2:])
print("start: legal moves =", len(lm0), " movable pieces =", len(d0))
print("start: per-piece:", {k: len(v) for k, v in sorted(d0.items())})
