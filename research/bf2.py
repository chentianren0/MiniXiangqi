#!/usr/bin/env python3
"""Board-first layout scheme: arithmetic over the measured probe8/macprobe2 data.

Reads discussion-drafts/layout-probe/out8-se3-P.txt (iOS, all 12 Dynamic Type steps,
15 widths) and out-mac2.txt (macOS).  Writes nothing outside discussion-drafts/.
"""
import re, sys, os
from itertools import product

PROBE = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'layout-probe')
SZ = ['xS','S','M','L','xL','xxL','xxxL','AX1','AX2','AX3','AX4','AX5']
AXSZ = ['AX1','AX2','AX3','AX4','AX5']
WIDTHS = [264,280,308,320,328,343,359,375,388,398,404,424,686,712,720]

def load(path, tag):
    rows = {}
    for ln in open(path):
        m = re.match(tag + r'\[(\w+)\] (\w+) idealW=([\d.]+) idealH=([\d.]+)(.*)', ln.strip())
        if not m: continue
        sz, name, iw, ih, rest = m.groups()
        ws = {int(a): float(b) for a, b in re.findall(r'h@(\d+)=([\d.]+)', rest)}
        rows[(name, sz)] = {'iw': float(iw), 'ih': float(ih), 'w': ws}
    return rows

IOS = load(os.path.join(PROBE, 'out8-se3-P.txt'), 'E')
MAC = load(os.path.join(PROBE, 'out-mac2.txt'), 'MACELEM')

def h(rows, name, sz, w):
    """Height at layout width w; round DOWN to the largest measured width <= w
    (conservative: a narrower measurement is never shorter)."""
    r = rows[(name, sz)]
    if w >= r['iw']: return r['ih']          # measured ideal width fits -> no wrap
    c = [x for x in WIDTHS if x <= w]
    return r['w'][max(c)] if c else r['w'][WIDTHS[0]]

def iw(rows, name, sz):
    return rows[(name, sz)]['iw']

# ---------------- board block (accepted formulas, interaction-design.md:153-154) ----
def strip(p):
    s = round(min(20.0, max(13.0, 0.32*p)))
    return round(0.08*p + 0.887*s)

def block(p, strips):
    return 7.0*p + (2.0*strip(p) if strips else 0.0)

def maxpitch(availH, availW, strips, cap=720.0):
    lo, hi = 0.5, 400.0
    for _ in range(300):
        mid = (lo+hi)/2
        if block(mid, strips) <= availH and 7*mid <= availW and 7*mid <= cap:
            lo = mid
        else:
            hi = mid
    return lo

def strips_shown(sz, plat):
    if plat == 'mac':          # macOS honours no Dynamic Type; strips always shown
        return True
    return sz not in AXSZ

# ---------------- scheme constants ------------------------------------------------
GAP        = 12.0     # inter-element gap (same assumption the constraint table uses)
GUTTER     = 16.0     # board <-> panel
PANEL_IOS  = 320.0    # terminal metadata line, untruncated, at default text
PANEL_MAC  = 257.0
FLOOR      = 44.0
CORE_FLOOR = 7*FLOOR  # 308

def side_by_side(usableW, plat):
    """THE ARRANGEMENT PREDICATE.  Operands: usable width, and three constants.
    Contains no term that depends on the board's final size, the chrome, the
    text size, or the arrangement.  Monotone non-decreasing in usableW."""
    panel = PANEL_MAC if plat == 'mac' else PANEL_IOS
    return usableW >= CORE_FLOOR + GUTTER + panel

# ---------------- resident chrome, per state, under the scheme --------------------
# Under the scheme:
#   * the threefold notice is a system alert           -> 0 resident height
#   * the move list is a user-summoned sheet in stacked-> 0 resident height
#   * the result card REPLACES the turn status         -> card only
#   * resident chrome spans the SCENE width (full-bleed bars); only the board
#     block carries the layout margin.
STATES_STACKED = {
  'play-AI':            [('turnStatus',1), ('controlRowAI',1)],
  'play-Free':          [('turnStatus',1), ('controlRowFree',1)],
  'claim-retained':     [('turnStatus',1), ('controlRowAI',1)],
  'result-replaces':    [('resultCard',1)],
  'result-recorded':    [('resultCardRecorded',1)],
  'threefold-alert':    [('turnStatus',1), ('controlRowAI',1)],   # alert overlays play
  'replay-transport':   [('turnStatus',1), ('transport6',1)],
  'replay-t7':          [('turnStatus',1), ('transport7',1)],
  'replay-speed':       [('turnStatus',1), ('transportPlusSpeed',1)],
  'prestart-AI':        [('preStartAI',1)],
  'prestart-Free':      [('preStartFree',1)],
}
# In side by side every one of these sits in the panel; the board's vertical
# budget is the whole content height.
STATES_SBS = {k: [] for k in STATES_STACKED}

# session envelopes: the set of states one scene can enter without a geometry event
ENV = {
  'play-AI':   ['play-AI', 'claim-retained', 'threefold-alert', 'result-replaces', 'result-recorded'],
  'play-Free': ['play-Free', 'claim-retained', 'threefold-alert', 'result-replaces', 'result-recorded'],
  'replay':    ['replay-transport', 'replay-t7', 'replay-speed'],
  'prestart-AI':   ['prestart-AI'],
  'prestart-Free': ['prestart-Free'],
}

def chrome(rows, state, sz, sceneW, sbs):
    if sbs: return 0.0
    tot, n = 0.0, 0
    for name, c in STATES_STACKED[state]:
        tot += c*h(rows, name, sz, sceneW); n += c
    return tot + n*GAP

def envelope_chrome(rows, session, sz, sceneW, sbs):
    return max(chrome(rows, s, sz, sceneW, sbs) for s in ENV[session])

# ---------------- the scheme -------------------------------------------------------
def solve(sceneW, contentH, sz, session, plat, margin):
    """Returns (arrangement, pitch, availH, availW, panelW, envelope chrome)."""
    rows = MAC if plat == 'mac' else IOS
    usableW = sceneW - 2*margin
    sbs = side_by_side(usableW, plat)
    C = envelope_chrome(rows, session, sz, sceneW, sbs)
    if sbs:
        panelmin = PANEL_MAC if plat == 'mac' else PANEL_IOS
        availW = usableW - GUTTER - panelmin
        availH = contentH - C
    else:
        availW = usableW
        availH = contentH - C
    p = maxpitch(availH, availW, strips_shown(sz, plat))
    panelW = (usableW - GUTTER - 7*p) if sbs else 0.0
    return ('side' if sbs else 'stack'), p, availH, availW, panelW, C

# ---------------- device inventories ----------------------------------------------
IPHONE = [  # (W, H, topSafe, margin)
  (375, 667, 20, 16), (375, 812, 50, 16), (390, 844, 47, 16), (393, 852, 59, 16),
  (402, 874, 62, 16), (414, 896, 48, 20), (420, 912, 68, 20), (428, 926, 47, 20),
  (430, 932, 59, 20), (440, 956, 62, 20),
]
IPAD = [  # (name, Wportrait, Hportrait, homeButton)
  ('mini 6 / A17',      744, 1133, False),
  ('mini 5',            768, 1024, True),
  ('iPad 8 / 9',        810, 1080, True),
  ('iPad 10/A16/Air11', 820, 1180, False),
  ('Air 3',             834, 1112, True),
  ('Pro 11 1st-4th',    834, 1194, False),
  ('Pro 11 M4/M5',      834, 1210, False),
  ('Pro 12.9/Air 13',  1024, 1366, False),
  ('Pro 13 M4/M5',     1032, 1376, False),
]

def ipad_chrome(sceneW, homeButton):
    """measured: >=1025 sidebar (lead 280, top 32); 668-1024 top tab bar (+64);
    <=664 bottom bar (47 + indicator).  Bottom safe 25 (0 on home-button iPads)."""
    bottomSafe = 0.0 if homeButton else 25.0
    if sceneW >= 1025:
        return 280.0, 32.0 + bottomSafe
    if sceneW >= 668:
        return 0.0, 32.0 + 64.0 + bottomSafe
    return 0.0, 32.0 + 47.0 + bottomSafe     # narrow window: bottom bar (see open q.)

def ipad_cells():
    out = []
    for name, W, H, hb in IPAD:
        for orient, (sw, sh) in (('P', (W, H)), ('L', (H, W))):
            for cfg, (fw, fh) in (
                ('full',       (1.0, 1.0)),
                ('side half',  (0.5, 1.0)),
                ('t/b half',   (1.0, 0.5)),
                ('vert 1/3',   (1/3, 1.0)),
                ('vert 2/3',   (2/3, 1.0)),
                ('horiz 1/3',  (1.0, 1/3)),
                ('quadrant',   (0.5, 0.5)),
            ):
                out.append((name, orient, cfg, sw*fw, sh*fh, hb))
    return out


# ================= SCHEME v2 ======================================================
# Arrangement predicate: TWO operands, both pure functions of the scene rectangle.
def arrange(sceneW, sceneH, usableW, plat):
    """side by side  iff  (wide enough for board floor + gutter + panel floor)
                     and  (the scene is not taller than it is wide).
    Neither operand mentions the board's final size, the chrome, the state,
    the text size, or the arrangement.  Monotone in each operand."""
    panel = PANEL_MAC if plat == 'mac' else PANEL_IOS
    return (usableW >= CORE_FLOOR + GUTTER + panel) and (sceneW >= sceneH)

def solve2(sceneW, sceneH, contentW, contentH, sz, session, plat, margin, yield_strips=True):
    rows = MAC if plat == 'mac' else IOS
    usableW = contentW - 2*margin
    sbs = arrange(sceneW, sceneH, usableW, plat)
    C = envelope_chrome(rows, session, sz, contentW, sbs)
    panelmin = PANEL_MAC if plat == 'mac' else PANEL_IOS
    availW = (usableW - GUTTER - panelmin) if sbs else usableW
    availH = contentH - C
    strips = strips_shown(sz, plat)
    p = maxpitch(availH, availW, strips)
    if yield_strips and strips and p < FLOOR:
        p2 = maxpitch(availH, availW, False)
        if p2 >= FLOOR:
            p, strips = p2, False
    panelW = (usableW - GUTTER - 7*p) if sbs else 0.0
    return ('side' if sbs else 'stack'), p, availH, availW, panelW, C, strips

def ipad_solve(sceneW, sceneH, sz, session, hb, yield_strips=True):
    lead, vert = ipad_chrome(sceneW, hb)
    return solve2(sceneW, sceneH, sceneW-lead, sceneH-vert, sz, session, 'ios', 20.0, yield_strips)

# ---- report A: iPad full screen ---------------------------------------------------
def A():
    print("=== A. iPad full screen: arrangement + pitch, both orientations, 5 text sizes ===")
    print(f"{'device':20s} {'or':2s} {'scene':>11s} {'usableW':>7s} {'contH':>6s} {'arr':5s} " +
          ''.join(f"{s:>8s}" for s in ('L','xxxL','AX1','AX3','AX5')))
    for name,W,H,hb in IPAD:
        for orient,(sw,sh) in (('P',(W,H)),('L',(H,W))):
            lead,vert = ipad_chrome(sw,hb)
            cells=''; arr=''
            for s in ('L','xxxL','AX1','AX3','AX5'):
                a,p,ah,aw,pw,c,st = ipad_solve(sw,sh,s,'play-AI',hb); arr=a
                cells += f"{p:8.1f}" if p>=FLOOR else f"{'%.1f!'%p:>8s}"
            print(f"{name:20s} {orient:2s} {('%dx%d'%(sw,sh)):>11s} {sw-lead-40:7.0f} {sh-vert:6.0f} {arr:5s} " + cells)
    print()

# ---- report B: all 126 tiling cells ----------------------------------------------
CFG = [('full',1.0,1.0),('side half',0.5,1.0),('t/b half',1.0,0.5),('vert 1/3',1/3,1.0),
       ('vert 2/3',2/3,1.0),('horiz 1/3',1.0,1/3),('quadrant',0.5,0.5)]
def B(sizes=('L','AX3'), yield_strips=True, verbose=True):
    for sz in sizes:
        rowsum = {c[0]:[0,0] for c in CFG}
        fails=[]
        for name,W,H,hb in IPAD:
            for orient,(sw0,sh0) in (('P',(W,H)),('L',(H,W))):
                for cfg,fw,fh in CFG:
                    sw,sh = sw0*fw, sh0*fh
                    a,p,ah,aw,pw,c,st = ipad_solve(sw,sh,sz,'play-AI',hb,yield_strips)
                    rowsum[cfg][1]+=1
                    if p>=FLOOR: rowsum[cfg][0]+=1
                    else: fails.append((name,orient,cfg,sw,sh,a,p,ah))
        tot=sum(v[0] for v in rowsum.values())
        print(f"--- {sz}, strips-yield={yield_strips}: {tot}/126 cells hold p>=44 ---")
        for cfg,_,_ in CFG:
            print(f"    {cfg:10s} {rowsum[cfg][0]:2d}/18")
        if verbose:
            for f in fails:
                print(f"      FAIL {f[0]:20s} {f[1]} {f[2]:10s} {f[3]:7.1f}x{f[4]:7.1f} {f[5]:5s} p={f[6]:5.1f} availH={f[7]:6.1f}")
        print()

# ---- report C: macOS + the round-2 oscillation counterexample ---------------------
def C():
    print("=== C. macOS ===")
    for cw,ch,label in ((1024,550,'named worst case, no toolbar'),
                        (1024,516,'named worst case, .unified toolbar'),
                        (820,550,'ROUND-2 OSCILLATION COUNTEREXAMPLE'),
                        (819,550,'one point narrower'),
                        (700,550,'round-2 1.4 "landscape stacks" case'),
                        (621,512,'declared minimum content, at the side-by-side edge'),
                        (620,512,'one point below the edge'),
                        (550,700,'portrait Mac window'),
                        (348,512,'narrowest sensible content')):
        for sess in ('play-AI',):
            a,p,ah,aw,pw,c,st = solve2(cw,ch,cw,ch,'L',sess,'mac',20.0)
            ok = 'ok' if p>=FLOOR else 'FAIL'
            print(f"  {cw}x{ch:<4d} {label:38s} usableW={cw-40:5.0f} -> {a:5s} p={p:6.2f} core={7*p:6.1f} "
                  f"panel={pw:6.1f} envC={c:5.1f} strips={st} {ok}")
    print()
    print("  macOS: minimum content height per state (side by side and stacked), p=44")
    for st in STATES_STACKED:
        if (STATES_STACKED[st][0][0],'L') not in MAC: continue
        try: need = chrome(MAC, st, 'L', 400, False) + block(44,True)
        except KeyError: continue
        print(f"    {st:20s} stacked needs {need:6.1f}   side-by-side needs {block(44,True):6.1f}")
    print()

# ---- report D: iPhone, all 10 classes x 12 sizes x 3 sessions --------------------
def D():
    print("=== D. iPhone portrait (no navigation bar) ===")
    print(f"{'screen':>10s} {'session':11s}" + ''.join(f"{s:>7s}" for s in SZ))
    for W,H,top,mg in IPHONE:
        Cn = H - top - 83.0
        for sess in ('play-AI','play-Free','replay','prestart-AI'):
            row=f"{W}x{H}".rjust(10)+' '+sess.ljust(11)
            for s in SZ:
                a,p,ah,aw,pw,c,stp = solve2(W,H,W,Cn,s,sess,'ios',mg)
                bad = p<FLOOR and not sess.startswith('prestart')
                row += f"{'%.1f!'%p:>7s}" if bad else f"{p:7.1f}"
            print(row)
    print()

# ---- report E: iPadOS declared scene minimum -------------------------------------
def E():
    print("=== E. iPadOS scene minimum: what each candidate permits, and what it holds ===")
    for sw,sh in ((360,584),(360,600),(360,620),(360,642),(375,600),(400,600),(320,600)):
        # narrow scene -> bottom bar; assume 83 (iPhone-measured) conservatively
        vert = 32+83
        cw,chh = sw, sh-vert
        line=f"  scene {sw}x{sh} (content {cw}x{chh}): "
        for s in ('L','xxxL','AX1','AX3'):
            a,p,ah,aw,pw,c,st = solve2(sw,sh,cw,chh,s,'play-AI','ios',20.0)
            line += f"{s}={p:.1f}{'' if p>=FLOOR else '!'} "
        # tiling permitted
        n=0
        for name,W,H,hb in IPAD:
            for orient,(sw0,sh0) in (('P',(W,H)),('L',(H,W))):
                for cfg,fw,fh in CFG:
                    if sw0*fw>=sw and sh0*fh>=sh: n+=1
        print(line+f" | tiling cells permitted {n}/126")
    print()

if __name__=='__main__':
    import sys
    w = sys.argv[1] if len(sys.argv)>1 else 'all'
    if w in ('all','A'): A()
    if w in ('all','B'): B()
    if w in ('all','C'): C()
    if w in ('all','D'): D()
    if w in ('all','E'): E()
