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

# ---------------- reports ----------------------------------------------------------
def rep_iphone():
    print("=== iPhone portrait, no navigation bar, board-first scheme ===")
    print("content H = H - topSafe - 83 (measured tab container)")
    hdr = f"{'screen':>10s} {'session':11s}" + ''.join(f"{s:>7s}" for s in SZ)
    print(hdr)
    for W,H,top,mg in IPHONE:
        C = H - top - 83.0
        for sess in ('play-AI','play-Free','replay'):
            row = f"{W}x{H}".rjust(10) + ' ' + sess.ljust(11)
            for s in SZ:
                a,p,ah,aw,pw,c = solve(W, C, s, sess, 'ios', mg)
                row += (f"{p:7.1f}" if p >= FLOOR else f"{'  '+'%.1f'%p+'!':>7s}")
            print(row)
    print()

def rep_iphone_states():
    print("=== iPhone SE 375x667 (content 564): per-state pitch, no envelope ===")
    print(f"{'state':20s}" + ''.join(f"{s:>7s}" for s in SZ))
    for st in STATES_STACKED:
        row = st.ljust(20)
        for s in SZ:
            c = chrome(IOS, st, s, 375, False)
            p = maxpitch(564.0-c, 375-32, strips_shown(s,'ios'))
            row += (f"{p:7.1f}" if p>=FLOOR or st.startswith('prestart') else f"{'  %.1f!'%p:>7s}")
        print(row)
    print()
    print("chrome heights, same cells (scene width 375, full-bleed):")
    print(f"{'state':20s}" + ''.join(f"{s:>7s}" for s in SZ))
    for st in STATES_STACKED:
        print(st.ljust(20) + ''.join(f"{chrome(IOS,st,s,375,False):7.1f}" for s in SZ))
    print()

def rep_ipad():
    print("=== iPad: all 126 tiling cells, ordinary play (play-AI envelope) ===")
    for sz in ('L','AX3'):
        print(f"--- text size {sz} ---")
        fails = []
        for name,orient,cfg,sw,sh,hb in ipad_cells():
            lead, vert = ipad_chrome(sw, hb)
            cw = sw - lead
            ch = sh - vert
            a,p,ah,aw,pw,c = solve(cw, ch, sz, 'play-AI', 'ios', 20.0)
            if p < FLOOR:
                fails.append((name,orient,cfg,sw,sh,a,p,ah))
        print(f"  cells failing p>=44: {len(fails)} of 126")
        for f in fails:
            print(f"    {f[0]:20s} {f[1]} {f[2]:10s} scene {f[3]:7.1f}x{f[4]:7.1f} -> {f[5]} p={f[6]:.1f} availH={f[7]:.1f}")
    print()

def rep_ipad_full():
    print("=== iPad full screen: arrangement and pitch, both orientations ===")
    print(f"{'device':20s} {'or':2s} {'sceneW':>7s} {'usableW':>8s} {'contentH':>8s} {'arr':5s} " +
          ''.join(f"{s:>7s}" for s in ('L','xxxL','AX1','AX3','AX5')))
    for name,W,H,hb in IPAD:
        for orient,(sw,sh) in (('P',(W,H)),('L',(H,W))):
            lead,vert = ipad_chrome(sw, hb)
            cw, ch = sw-lead, sh-vert
            row = f"{name:20s} {orient:2s} {sw:7.0f} {cw-40:8.0f} {ch:8.0f} "
            arr = None
            cells = ''
            for s in ('L','xxxL','AX1','AX3','AX5'):
                a,p,ah,aw,pw,c = solve(cw, ch, s, 'play-AI', 'ios', 20.0)
                arr = a
                cells += (f"{p:7.1f}" if p>=FLOOR else f"{'  %.1f!'%p:>7s}")
            print(row + f"{arr:5s} " + cells)
    print()

def rep_mac():
    print("=== macOS (one text-size column) ===")
    for cw, chh, label in ((1024,550,'named worst-case display, no toolbar'),
                           (1024,516,'same display, .unified toolbar'),
                           (820,550,'ROUND-2 OSCILLATION COUNTEREXAMPLE'),
                           (700,550,'round-2 1.4 landscape case'),
                           (621,512,'declared minimum content'),
                           (520,512,'below the side-by-side threshold')):
        a,p,ah,aw,pw,c = solve(cw, chh, 'L', 'play-AI', 'mac', 20.0)
        print(f"  {cw}x{chh:<4d} {label:40s} usableW={cw-40:6.1f} -> {a:5s} p={p:6.2f} core={7*p:6.1f} panel={pw:6.1f} envChrome={c:5.1f}")
    print()
    print("  macOS minimum-content search (side of threshold, every state):")
    for cw in (348, 400, 500, 600, 620, 621, 640, 700, 820, 1024):
        for chh in (460, 480, 500, 512, 550):
            a,p,_,_,pw,c = solve(cw, chh, 'L', 'play-AI', 'mac', 20.0)
            ok = 'ok ' if p>=FLOOR else 'FAIL'
            if chh in (500,512):
                print(f"    {cw}x{chh}: {a:5s} p={p:6.2f} {ok} panel={pw:6.1f}")
    print()

if __name__ == '__main__':
    which = sys.argv[1] if len(sys.argv)>1 else 'all'
    if which in ('all','se'):   rep_iphone_states()
    if which in ('all','ip'):   rep_iphone()
    if which in ('all','pad'):  rep_ipad_full(); rep_ipad()
    if which in ('all','mac'):  rep_mac()
