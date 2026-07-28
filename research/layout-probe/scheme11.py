#!/usr/bin/env python3
"""Arithmetic model of the state-layers layout scheme.

Inputs: probe8 (out8-se3-P.txt) and probe11 (out11-se3.txt) element measurements,
both taken on an iPhone SE (3rd generation), iOS 27.0, @2x — the binding device.
macOS elements from out-mac2.txt.

Nothing here is asserted; every element height is read from a probe file.
"""
import re, sys
from itertools import product

SZ = ['xS','S','M','L','xL','xxL','xxxL','AX1','AX2','AX3','AX4','AX5']
AXSZ = {'AX1','AX2','AX3','AX4','AX5'}

def load(path, tag='E'):
    rows = {}
    for ln in open(path):
        m = re.match(tag + r'\[(\w+)\] (\w+) idealW=([\d.]+) idealH=([\d.]+)(.*)', ln.strip())
        if not m: continue
        sz, name, iw, ih, rest = m.groups()
        rows[(name, sz)] = {'iw': float(iw), 'ih': float(ih),
                            'w': {int(a): float(b) for a, b in re.findall(r'h@(\d+)=([\d.]+)', rest)}}
    return rows

P8  = load('out8-se3-P.txt')
P11 = load('out11-se3.txt')
MAC = load('out-mac2.txt', 'MACELEM')

EL = dict(P8); EL.update(P11)          # probe11 wins where both measured (they agree)

def h(name, sz, w):
    """height at container width w, rounding DOWN to the largest measured width <= w."""
    r = EL[(name, sz)]
    cands = [x for x in sorted(r['w']) if x <= w]
    return r['w'][cands[-1]] if cands else r['w'][min(r['w'])]

def hmac(name):
    r = MAC[(name, 'L')]
    return r['ih']

# ---------------- board block (accepted formulas, interaction-design.md:153-157) --------
def strip(p):
    s = round(min(20, max(13, 0.32 * p)))
    return round(0.08 * p + 0.887 * s)

def blockH(p, strips):
    return 7 * p + (2 * strip(p) if strips else 0)

CAP = 720.0

def maxpitch(availH, availW, strips):
    lo, hi = 1.0, 400.0
    for _ in range(120):
        mid = (lo + hi) / 2
        if blockH(mid, strips) <= availH and 7 * mid <= availW and 7 * mid <= CAP:
            lo = mid
        else:
            hi = mid
    return lo

GAP = 12.0
def strips_shown(sz): return sz not in AXSZ

def pitch(availH, availW, sz):
    """Strips yield before the board does: shown at non-accessibility sizes only while
    the board still clears its floor with them; hidden otherwise. Returns (p, stripsShown)."""
    if strips_shown(sz):
        p = maxpitch(availH, availW, True)
        if p >= 44.0:
            return p, True
    return maxpitch(availH, availW, False), False

# ---------------- the scheme's states -------------------------------------------------
# stacked resident inventory (elements outside the board block)
STACKED = {
  'play-AI'        : ['statusDisclosureAI', 'controlRowAI'],
  'play-Free'      : ['statusDisclosureFreeFlip', 'controlRow2Free'],
  'claim-retained' : ['statusDisclosureAI', 'controlRowAI'],
  'result-AI'      : ['resultCard'],
  'result-Free'    : ['resultCardFreeTitleIcon'],
  'result-recorded': ['resultCardRecorded'],
  'replay'         : ['replayStatusPlain', 'transport7PlusSpeed'],
  'replay-noSpeed' : ['replayStatusPlain', 'transport7'],
  'prestart-AI'    : ['preStartAI'],
  'prestart-Free'  : ['preStartFree'],
}
# states the scheme deletes from the resident budget entirely
ALERTED  = ['threefold-replaces', 'threefold-alongside', 'memory-notice']
SHEETED  = ['replay-list1', 'replay-list3', 'replay-list5', 'movelist-in-play']
NEVER    = ['result-alongside']

FLOOR_STATES = [s for s in STACKED if not s.startswith('prestart')]

def chrome(state, sz, w):
    els = STACKED[state]
    return sum(h(e, sz, w) for e in els) + GAP * len(els)

# ---------------- window geometry ------------------------------------------------------
def inset(kind, usableRaw):
    """stacked-column horizontal inset: 12 pt compact, 20 pt regular."""
    return 12.0 if kind == 'compact' else 20.0

PHONES = [  # (W, H, topSafe, bottomSafe)
 (375, 667, 20, 0), (375, 812, 50, 34), (390, 844, 47, 34), (393, 852, 59, 34),
 (402, 874, 62, 34), (414, 896, 48, 34), (420, 912, 68, 34), (428, 926, 47, 34),
 (430, 932, 59, 34), (440, 956, 62, 34),
]
TAB_PHONE = 83.0

def phone_box(W, H, topSafe):
    contentH = H - topSafe - TAB_PHONE
    usable = W - 2 * 12.0            # compact everywhere on iPhone
    return usable, contentH

IPADS = [  # (name, portraitW, portraitH, bottomSafe)
 ('mini 6 / A17',      744, 1133, 25),
 ('mini 5',            768, 1024, 0),
 ('iPad 8 / 9',        810, 1080, 0),
 ('iPad 10 / A16 / Air 11',  820, 1180, 25),
 ('Air 3',             834, 1112, 0),
 ('Pro 11 1st-4th',    834, 1194, 25),
 ('Pro 11 M4/M5',      834, 1210, 25),
 ('Pro 12.9 / Air 13', 1024, 1366, 25),
 ('Pro 13 M4/M5',      1032, 1376, 25),
]
BOTTOM_BAR_IPAD = 83.0   # unmeasured; iPhone figure used, conservative (see open items)

def ipad_box(W, H, bottomSafe):
    """scene W x H -> (usableW, contentH, presentation)"""
    top = 32.0
    if W <= 664:
        pres = 'bottom bar'
        contentW, contentH = W, H - top - BOTTOM_BAR_IPAD
    elif W <= 1024:
        pres = 'top tab bar'
        contentW, contentH = W, H - top - 64.0 - bottomSafe
    else:
        pres = 'sidebar'
        contentW, contentH = W - 280.0, H - top - bottomSafe
    kind = 'compact' if contentW < 668 else 'regular'
    usable = contentW - 2 * inset(kind, contentW)
    return usable, contentH, pres

# ---------------- the arrangement rule -------------------------------------------------
PANEL_MIN_IOS = 320.0
PANEL_MIN_MAC = 257.0
GUTTER = 16.0
BOARD_FLOOR_CORE = 308.0
SPLIT_K = 0.85

def split_w(platform):
    return BOARD_FLOOR_CORE + GUTTER + (PANEL_MIN_MAC if platform == 'mac' else PANEL_MIN_IOS)

def arrangement(usableW, contentH, platform='ios'):
    return 'side-by-side' if (usableW >= split_w(platform) and usableW >= SPLIT_K * contentH) else 'stacked'

# ---------------- board sizing ---------------------------------------------------------
def pitch_stacked(state, sz, usableW, contentH):
    availH = contentH - chrome(state, sz, usableW)
    return pitch(availH, usableW, sz)[0], availH

def pitch_sbs(usableW, contentH, sz, platform='ios'):
    pmin = PANEL_MIN_MAC if platform == 'mac' else PANEL_MIN_IOS
    boardBudgetW = usableW - GUTTER - pmin
    p = pitch(contentH, boardBudgetW, sz)[0]
    return p, usableW - GUTTER - 7 * p

# =======================================================================================
if __name__ == '__main__':
    mode = sys.argv[1] if len(sys.argv) > 1 else 'phone'

    if mode == 'phone':
        print("iPhone, portrait, stacked. Max cell pitch; '--' = below the 44 pt floor.")
        print(f"{'screen':>10s} {'state':16s}" + ''.join(f"{s:>7s}" for s in SZ))
        for (W, H, ts, bs) in PHONES:
            u, c = phone_box(W, H, ts)
            for st in FLOOR_STATES:
                cells = []
                for s in SZ:
                    p, a = pitch_stacked(st, s, u, c)
                    cells.append(f"{p:7.1f}" if p >= 44 else "     --")
                print(f"{W}x{H} {st:16s}" + ''.join(cells))
            print()

    if mode == 'se':
        W, H, ts = 375, 667, 20
        u, c = phone_box(W, H, ts)
        print(f"iPhone SE 375x667: usable={u} contentH={c}")
        for st in FLOOR_STATES:
            print(f"-- {st}")
            for s in SZ:
                ch = chrome(st, s, u)
                p, a = pitch_stacked(st, s, u, c)
                req = ch + blockH(44, strips_shown(s))
                print(f"   {s:5s} chrome={ch:7.1f} avail={a:7.1f} req@44={req:7.1f} margin={c-req:+8.1f} p={p:6.2f}")

    if mode == 'arr':
        print("Arrangement per iPad class and orientation (default text).")
        print(f"{'device':26s}{'ori':4s}{'scene':12s}{'pres':12s}{'usableW':>8s}{'contentH':>9s}{'k':>7s}  arrangement")
        for (n, W, H, bs) in IPADS:
            for ori, (w, hh) in (('P', (W, H)), ('L', (H, W))):
                u, c, pres = ipad_box(w, hh, bs)
                print(f"{n:26s}{ori:4s}{str(w)+'x'+str(hh):12s}{pres:12s}{u:8.0f}{c:9.0f}{u/c:7.3f}  {arrangement(u,c)}")

    if mode == 'ipad':
        print("iPad full screen: pitch per state per text size, in the arrangement the rule picks.")
        for (n, W, H, bs) in IPADS:
            for ori, (w, hh) in (('P', (W, H)), ('L', (H, W))):
                u, c, pres = ipad_box(w, hh, bs)
                arr = arrangement(u, c)
                row = []
                for s in SZ:
                    if arr == 'side-by-side':
                        p, lo = pitch_sbs(u, c, s)
                    else:
                        p = min(pitch_stacked(st, s, u, c)[0] for st in FLOOR_STATES)
                    row.append(f"{p:6.1f}" if p >= 44 else "    --")
                print(f"{n:26s}{ori} {arr:13s}" + ''.join(row))

    if mode == 'tile':
        from fractions import Fraction
        CONFIGS = [('full', 1, 1), ('side half', 2, 1), ('top/bottom half', 1, 2),
                   ('vertical third', 3, 1), ('vertical 2/3', Fraction(3,2), 1),
                   ('horizontal third', 1, 3), ('quadrant', 2, 2)]
        tot = {c[0]: [0, 0] for c in CONFIGS}
        fails = []
        for (n, W, H, bs) in IPADS:
            for ori, (w, hh) in (('P', (W, H)), ('L', (H, W))):
                for (cn, dw, dh) in CONFIGS:
                    sw, sh = float(Fraction(w) / dw), float(Fraction(hh) / dh)
                    u, c, pres = ipad_box(sw, sh, bs)
                    arr = arrangement(u, c)
                    if arr == 'side-by-side':
                        p, lo = pitch_sbs(u, c, 'L')
                    else:
                        p = min(pitch_stacked(st, 'L', u, c)[0] for st in FLOOR_STATES)
                    tot[cn][1] += 1
                    if p >= 44: tot[cn][0] += 1
                    else: fails.append((cn, n, ori, round(sw,1), round(sh,1), round(p,1), round(c,1)))
        print("iPad tiling, default text, worst resident state:")
        for cn, (ok, t) in tot.items(): print(f"  {cn:18s} {ok:2d}/{t}")
        print("\nfailures:")
        for x in sorted(fails): print("   ", x)

    if mode == 'mac':
        print("macOS: one text-size column. required content height for p=44 (strips always shown).")
        MSTATES = {
          'play-AI'   : ['turnStatus', 'controlRowAI'],
          'result'    : ['resultCard'],
          'recorded'  : ['resultCardRecorded'],
          'replay'    : ['transport5', 'turnStatus'],
          'prestart'  : ['preStartAI'],
        }
        for st, els in MSTATES.items():
            ch = sum(hmac(e) for e in els) + GAP * len(els)
            print(f"  {st:12s} chrome={ch:6.1f} required(stacked,p=44)={ch + blockH(44, True):7.1f}")
        print("\n side-by-side: the board gets the whole content height; panel carries everything.")
        for C in (450, 500, 512, 516, 550, 582):
            p = maxpitch(C, 10_000, True)
            print(f"   contentH={C}: board block fits p={p:.1f}")

    if mode == 'osc':
        print("Oscillation test. The rule's operands are window geometry only, so one pass is a fixed point.")
        cases = [('macOS content 820x550', 820, 550, 'mac'),
                 ('macOS content 700x550', 700, 550, 'mac'),
                 ('macOS content 640x550', 640, 550, 'mac'),
                 ('macOS content 601x550', 601, 550, 'mac'),
                 ('macOS content 1024x582', 1024, 582, 'mac'),
                 ('macOS content 360x512',  360, 512, 'mac')]
        for nm, W, H, plat in cases:
            u = W - 40.0
            print(f"\n{nm}: usableW={u} contentH={H} SPLIT_W={split_w(plat)} k={u/H:.3f}")
            arr = None
            for i in range(1, 6):
                a = arrangement(u, H, plat)
                print(f"   pass {i}: usableW {u:.0f} >= {split_w(plat):.0f}? {u>=split_w(plat)}   "
                      f"usableW >= {SPLIT_K}*{H} = {SPLIT_K*H:.1f}? {u>=SPLIT_K*H}  -> {a}")
                if arr == a:
                    print(f"   fixed point after pass {i}; the operands never changed.")
                    break
                arr = a
            if arr == 'side-by-side':
                p, lo = pitch_sbs(u, H, 'L', 'mac')
                print(f"   board core {7*p:.1f} at p={p:.1f}; panel {lo:.1f} (min {PANEL_MIN_MAC})")

    if mode == 'macfull':
        MST = {
          'play-AI/Free'  : ['turnStatus', 'controlRowAI'],
          'result'        : ['resultCard'],
          'result-recorded': ['resultCardRecorded'],
          'replay'        : ['transport5', 'turnStatus'],
          'prestart-AI'   : ['preStartAI'],
        }
        print("macOS STACKED (window narrower than the split): required content height for p=44")
        for st, els in MST.items():
            ch = sum(hmac(e) for e in els) + GAP * len(els)
            print(f"  {st:18s} chrome={ch:6.1f}  required={ch + blockH(44, True):7.1f} (strips) "
                  f"{ch + blockH(44, False):7.1f} (strips hidden)")
        print("\nmacOS SIDE BY SIDE: the board takes the whole content height.")
        for C in (420, 450, 480, 500, 512, 516, 542, 550, 582):
            pS = maxpitch(C, 10_000, True); pH = maxpitch(C, 10_000, False)
            print(f"  contentH={C}: p={pS:6.2f} with strips, {pH:6.2f} without")
        print("\n panel non-scrolling minimum height = status + control row + 1 move row + metadata + gaps")
        print(f"   = {hmac('turnStatus')} + {hmac('controlRowAI')} + {hmac('moveListRow')} + "
              f"{hmac('metaTerminal')} + 4*12 = "
              f"{hmac('turnStatus')+hmac('controlRowAI')+hmac('moveListRow')+hmac('metaTerminal')+48}")

    if mode == 'min':
        print("Smallest window/scene the scheme needs, per platform, worst resident state.")
        print("\niPadOS scene (stacked, compact, inset 12, chrome 32 top + 83 bottom bar):")
        for sz in ('L', 'AX1', 'AX3'):
            best = None
            for W in range(320, 620, 1):
                u = W - 24.0
                need = max(chrome(st, sz, u) for st in FLOOR_STATES) + blockH(44, strips_shown(sz))
                if 7 * 44 <= u:
                    H = need + 32 + 83
                    if best is None or H < best[1]: best = (W, H)
            # report at a few widths instead of the minimum-area point
            for W in (360, 372, 384, 392, 400, 420):
                u = W - 24.0
                if 7*44 > u:
                    print(f"   {sz:4s} scene W={W}: usable {u} < 308 — board cannot reach the floor"); continue
                worst = max(FLOOR_STATES, key=lambda st: chrome(st, sz, u))
                need = chrome(worst, sz, u) + blockH(44, strips_shown(sz))
                print(f"   {sz:4s} scene W={W} usable={u:.0f}: worst={worst:16s} content needs {need:6.1f} "
                      f"-> scene H {need+115:6.1f}")
        print("\nmacOS content (stacked):")
        MST = {'play': ['turnStatus','controlRowAI'], 'result': ['resultCard'],
               'recorded': ['resultCardRecorded'], 'replay': ['transport5','turnStatus']}
        for st, els in MST.items():
            ch = sum(hmac(e) for e in els) + GAP*len(els)
            print(f"   {st:10s} needs content height {ch + blockH(44, True):6.1f} (strips) / "
                  f"{ch + blockH(44, False):6.1f} (hidden)")

    if mode == 'permit':
        from fractions import Fraction
        CONFIGS = [('full', 1, 1), ('side half', 2, 1), ('top/bottom half', 1, 2),
                   ('vertical third', 3, 1), ('vertical 2/3', Fraction(3,2), 1),
                   ('horizontal third', 1, 3), ('quadrant', 2, 2)]
        for (mw, mh) in [(360,584),(360,642),(360,648),(384,653),(384,620),(392,653),(360,765)]:
            tot = {c[0]: [0,0] for c in CONFIGS}; n=0
            for (nm, W, H, bs) in IPADS:
                for ori, (w, hh) in (('P',(W,H)), ('L',(H,W))):
                    for (cn, dw, dh) in CONFIGS:
                        sw, sh = float(Fraction(w)/dw), float(Fraction(hh)/dh)
                        tot[cn][1]+=1
                        if sw >= mw and sh >= mh: tot[cn][0]+=1; n+=1
            print(f"minimum {mw}x{mh}: permitted {n}/126  " +
                  "  ".join(f"{c}:{tot[c][0]}" for c,_ ,_ in CONFIGS))

    if mode == 'inbox':
        # every cell inside the declared box: iPad scene >= 384x653, text <= AX3
        from fractions import Fraction
        CONFIGS = [('full',1,1),('side half',2,1),('top/bottom half',1,2),
                   ('vertical third',3,1),('vertical 2/3',Fraction(3,2),1),
                   ('horizontal third',1,3),('quadrant',2,2)]
        MW, MH = 384, 653
        bad = []; n = 0
        for (nm,W,H,bs) in IPADS:
            for ori,(w,hh) in (('P',(W,H)),('L',(H,W))):
                for (cn,dw,dh) in CONFIGS:
                    sw, sh = float(Fraction(w)/dw), float(Fraction(hh)/dh)
                    if sw < MW or sh < MH: continue
                    u, c, pres = ipad_box(sw, sh, bs)
                    arr = arrangement(u, c)
                    for s in SZ:
                        if s in ('AX4','AX5'): continue
                        if arr == 'side-by-side': p,_ = pitch_sbs(u, c, s)
                        else: p = min(pitch_stacked(st, s, u, c)[0] for st in FLOOR_STATES)
                        n += 1
                        if p < 44: bad.append((nm,ori,cn,round(sw),round(sh),s,round(p,1),arr))
        print(f"iPad cells inside the declared box (scene >= {MW}x{MH}, text <= AX3): {n} evaluated, {len(bad)} below the floor")
        for b in bad[:60]: print("   ", b)

    if mode == 'panel':
        print("Side-by-side panel: does the panel hold its non-scrolling contents at every text size?")
        print("panel content = status + metadata + control row + >=1 move row + 4 gaps")
        for pw in (320, 360, 400, 500):
            for s in SZ:
                need = (h('statusDisclosureAI',s,pw) + h('metaTerminal',s,pw)
                        + h('controlRowAI',s,pw) + h('moveListRow',s,pw) + 4*GAP)
                print(f"   panelW={pw} {s:5s} non-scrolling height {need:7.1f}")
            print()
