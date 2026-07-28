"""Independent Mini Xiangqi model, written from MiniXiangqi/docs/xiangqi-rules.md.
No engine is consulted anywhere in this file."""
FILES = "abcdefg"

def sqname(f, r): return FILES[f] + str(r + 1)
def parse_sq(s): return (FILES.index(s[0]), int(s[1]) - 1)

def parse_fen(fen):
    parts = fen.split()
    rows = parts[0].split("/")
    assert len(rows) == 7, fen
    b = {}
    for i, row in enumerate(rows):
        r = 6 - i           # rows[0] is rank 7
        f = 0
        for ch in row:
            if ch.isdigit():
                f += int(ch)
            else:
                b[(f, r)] = ch
                f += 1
        assert f == 7, (fen, row)
    return b, parts[1], int(parts[4]), int(parts[5])

def to_fen(b, stm, half, full):
    rows = []
    for r in range(6, -1, -1):
        row, gap = "", 0
        for f in range(7):
            p = b.get((f, r))
            if p is None:
                gap += 1
            else:
                if gap: row += str(gap); gap = 0
                row += p
        if gap: row += str(gap)
        rows.append(row)
    return "/".join(rows) + f" {stm} - - {half} {full}"

def color(p): return "w" if p.isupper() else "b"
def kind(p): return p.upper()
def onboard(f, r): return 0 <= f < 7 and 0 <= r < 7
def in_palace(c, f, r):
    return 2 <= f <= 4 and (0 <= r <= 2 if c == "w" else 4 <= r <= 6)

HORSE = [(1,2),(2,1),(2,-1),(1,-2),(-1,-2),(-2,-1),(-2,1),(-1,2)]
def horse_leg(df, dr):
    return (df // abs(df) if abs(df) == 2 else 0, dr // abs(dr) if abs(dr) == 2 else 0)

def attacks(b, sq):
    """Squares this piece could capture on (pseudo-legal, king safety ignored)."""
    p = b[sq]; c = color(p); k = kind(p); f, r = sq
    out = set()
    if k == "K":
        for df, dr in ((1,0),(-1,0),(0,1),(0,-1)):
            nf, nr = f+df, r+dr
            if onboard(nf,nr) and in_palace(c,nf,nr): out.add((nf,nr))
        # flying generals: first piece up/down the file, if it is the enemy king
        for dr in (1,-1):
            nr = r+dr
            while onboard(f,nr):
                if (f,nr) in b:
                    q = b[(f,nr)]
                    if kind(q)=="K" and color(q)!=c: out.add((f,nr))
                    break
                nr += dr
    elif k == "R":
        for df,dr in ((1,0),(-1,0),(0,1),(0,-1)):
            nf,nr = f+df, r+dr
            while onboard(nf,nr):
                out.add((nf,nr))
                if (nf,nr) in b: break
                nf,nr = nf+df, nr+dr
    elif k == "C":
        for df,dr in ((1,0),(-1,0),(0,1),(0,-1)):
            nf,nr = f+df, r+dr; screens = 0
            while onboard(nf,nr):
                if (nf,nr) in b:
                    screens += 1
                    if screens == 2:
                        out.add((nf,nr)); break
                nf,nr = nf+df, nr+dr
    elif k == "N":
        for df,dr in HORSE:
            nf,nr = f+df, r+dr
            if not onboard(nf,nr): continue
            lf,lr = horse_leg(df,dr)
            if (f+lf, r+lr) in b: continue
            out.add((nf,nr))
    elif k == "P":
        fwd = 1 if c == "w" else -1
        for df,dr in ((0,fwd),(1,0),(-1,0)):
            nf,nr = f+df, r+dr
            if onboard(nf,nr): out.add((nf,nr))
    return out

def attackers_to(b, target, by_color, skip=frozenset()):
    return {s for s,p in b.items()
            if color(p) == by_color and s not in skip and target in attacks(b, s)}

def king_sq(b, c):
    for s,p in b.items():
        if kind(p)=="K" and color(p)==c: return s
    return None

def in_check(b, c):
    ks = king_sq(b, c)
    if ks is None: return False
    return bool(attackers_to(b, ks, "b" if c=="w" else "w"))

def pseudo_moves(b, c):
    out = []
    for s,p in list(b.items()):
        if color(p) != c: continue
        k = kind(p); f,r = s
        if k == "C":
            # non-capturing slides
            for df,dr in ((1,0),(-1,0),(0,1),(0,-1)):
                nf,nr = f+df, r+dr
                while onboard(nf,nr) and (nf,nr) not in b:
                    out.append((s,(nf,nr))); nf,nr = nf+df, nr+dr
            for t in attacks(b, s):
                if t in b and color(b[t]) != c: out.append((s,t))
        else:
            for t in attacks(b, s):
                if t in b and color(b[t]) == c: continue
                if k == "K" and t in b and kind(b[t])=="K": continue  # flying-general capture not a move
                out.append((s,t))
    return out

def apply_move(b, mv):
    b2 = dict(b); b2[mv[1]] = b2.pop(mv[0]); return b2

def legal_moves(b, c):
    out = []
    for mv in pseudo_moves(b, c):
        b2 = apply_move(b, mv)
        if in_check(b2, c): continue
        # flying generals: kings facing on otherwise empty file
        kw, kb = king_sq(b2,"w"), king_sq(b2,"b")
        if kw and kb and kw[0]==kb[0]:
            lo,hi = sorted((kw[1],kb[1]))
            if all((kw[0],rr) not in b2 for rr in range(lo+1,hi)): continue
        out.append(mv)
    return out

def legal_move_strs(b, c):
    return sorted(sqname(*a)+sqname(*t) for a,t in legal_moves(b,c))
