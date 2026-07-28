import sys
sys.path.insert(0, "/Users/tianren/coding/minixiangqi/discussion-drafts/w-base")
import pyffish as sf
sf.load_variant_config("""
[mxq_target:minixiangqi]
chasingRule = axf
nMoveRule = 0
promotedSoldiersChaseable = false
""")
V = "mxq_target"

def flip(fen):
    p = fen.split()
    p[1] = "b" if p[1] == "w" else "w"
    return " ".join(p)

def grid(fen):
    g = {}
    for i, r in enumerate(fen.split()[0].split("/")):
        rank, f = 7 - i, 0
        for ch in r:
            if ch.isdigit():
                f += int(ch)
            else:
                g["abcdefg"[f] + str(rank)] = ch
                f += 1
    return g

def set_sq(fen, sq, piece):
    g = grid(fen)
    g[sq] = piece
    rows = []
    for rank in range(7, 0, -1):
        row, empty = "", 0
        for f in "abcdefg":
            ch = g.get(f + str(rank))
            if ch is None:
                empty += 1
            else:
                if empty: row += str(empty); empty = 0
                row += ch
        if empty: row += str(empty)
        rows.append(row)
    p = fen.split()
    p[0] = "/".join(rows)
    return " ".join(p)

def attackers_of(fen, sq, by_side):
    """Which pieces of by_side ('w'/'b') can move onto sq (capturing what's there)."""
    p = fen.split(); p[1] = by_side
    f2 = " ".join(p)
    return sorted(m for m in sf.legal_moves(V, f2, []) if m[2:4] == sq)

def defenders_of(fen, sq):
    """Owner-side defenders: swap the piece on sq for an enemy piece of the same type,
    then ask whether the owner can capture it there."""
    g = grid(fen)
    pc = g[sq]
    owner = "w" if pc.isupper() else "b"
    enemy_pc = pc.lower() if pc.isupper() else pc.upper()
    f2 = set_sq(fen, sq, enemy_pc)
    return owner, attackers_of(f2, sq, owner)

CASES = [
 ("mx-chs-033", "2k4/7/1cN1R2/7/4n2/7/1R2K2 w - - 0 1", ["c5b3","e3f5","b3c5","f5e3"]*2, [("b5","w"),("f3","w")]),
 ("mx-chs-034", "2k2r1/7/2N4/7/2r1nC1/7/4K2 w - - 0 1", ["c5b3","e3f5","b3c5","f5e3"]*2, [("f3","b"),("b5","b")]),
 ("mx-mix-002", "2k2r1/7/1cN1R2/7/2r1nC1/7/1R2K2 w - - 0 1", ["c5b3","e3f5","b3c5","f5e3"]*2, [("b5","w"),("f3","b")]),
 ("mx-mix-003", "3k3/7/c6/R6/7/7/4K2 w - - 0 1", ["a4d4","d7c7","d4a4","c7d7"]*2, [("a5","w")]),
]

for name, start, moves, targets in CASES:
    print("="*66)
    print(name)
    for sq, by in targets:
        print(f"  target {sq}, attacked by side {by}:")
        for i in range(len(moves)+1):
            fen = sf.get_fen(V, start, moves[:i])
            g = grid(fen)
            if sq not in g:
                print(f"    ply {i}: square empty"); continue
            att = attackers_of(fen, sq, by)
            owner, dfs = defenders_of(fen, sq)
            mv = moves[i-1] if i else "(start)"
            print(f"    ply {i:>1} after {mv:<6} piece={g[sq]} attackers={att} defenders={dfs}")
