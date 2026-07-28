#!/usr/bin/env python3
"""Layout-shape decision, iPad tiling, macOS window range."""
from budget8 import load, loadmac, blockH, maxpitch, chromeH, strips_shown, SZ
from table8 import IPAD, IPHONE, ios, mac, SIDEBAR_W, TABBAR_IPAD_TOP, GUTTER
from fractions import Fraction

SIDEBAR_FROM = 1025.0   # measured: sidebarAdaptable presents as a sidebar at >= 1025 pt
TOPTAB_FROM  = 668.0    # measured: top tab bar from ~668 pt; below that, a bottom bar
BOTTOMBAR    = 83.0     # measured on iPhone; iPad narrow-window value unconfirmed
MARGIN       = 20.0     # measured iPad root-view layoutMargins
MARGIN_PHONE = 16.0

def container(width):
    """(leadingInset, topInset_extra, bottomInset_extra) for the adaptive container"""
    if width >= SIDEBAR_FROM: return (SIDEBAR_W, 0.0, 0.0)
    if width >= TOPTAB_FROM:  return (0.0, TABBAR_IPAD_TOP, 0.0)
    return (0.0, 0.0, BOTTOMBAR)

def scene_content(W, H, topSafe, botSafe):
    lead, topx, botx = container(W)
    cw = W - lead
    ch = H - topSafe - topx - max(botSafe, botx if botx else botSafe)
    if botx: ch = H - topSafe - botx      # bottom bar contains the indicator (measured on iPhone)
    return cw, ch

def usable(cw, phone=False):
    return cw - 2*(MARGIN_PHONE if phone else MARGIN)

def reading_A(uw, ch, sz, rows, panel_min, state='play-AI'):
    """board first: board = min(height-bound, width-bound, 720); side-by-side iff leftover >= panel"""
    # height available if side by side: full content height (status+controls live in the panel)
    p = maxpitch(ch, uw, strips_shown(sz), 720.0)
    core = 7*p
    left = uw - core - GUTTER
    return left >= panel_min, core, left

def reading_B(uw, ch, sz, rows, panel_min):
    """panel first: side by side iff uw - panel - gutter >= 308 (board at its floor)"""
    left = uw - panel_min - GUTTER
    return left >= 308.0, left

if __name__ == '__main__':
    print("## Layout-shape decision, full screen, default text, panel minimum 320 / 280 / 264\n")
    print(f"{'device / orientation':34s}{'sceneW':>7s}{'contW':>7s}{'usableW':>8s}{'contH':>7s}  " +
          "  ".join(f"{'A@'+str(p):>10s}" for p in (320,280,264)) + "  " +
          "  ".join(f"{'B@'+str(p):>10s}" for p in (320,280,264)))
    for (lab, W, H, top, bot, m, hb, src) in IPAD:
        for ori, (sw, sh) in (("portrait",(W,H)), ("landscape",(H,W))):
            cw, ch = scene_content(sw, sh, top, bot)
            uw = usable(cw)
            a = []
            for pm in (320,280,264):
                ok, core, left = reading_A(uw, ch, 'L', ios, pm)
                a.append(f"{'SIDE' if ok else 'stack':>5s}{left:5.0f}")
            b = []
            for pm in (320,280,264):
                ok, left = reading_B(uw, ch, 'L', ios, pm)
                b.append(f"{'SIDE' if ok else 'stack':>5s}{left:5.0f}")
            print(f"{lab+' '+ori:34s}{sw:7.0f}{cw:7.0f}{uw:8.0f}{ch:7.0f}  " + "  ".join(a) + "  " + "  ".join(b))

    print("\n## iPad tiling configurations — scene sizes and whether ordinary play holds p>=44 at L")
    print("(exact fractions of the screen, inter-window gaps ignored: optimistic)")
    CONF = [("full", 1, 1), ("half side", Fraction(1,2), 1), ("half top/bottom", 1, Fraction(1,2)),
            ("third vertical", Fraction(1,3), 1), ("two-thirds vertical", Fraction(2,3), 1),
            ("third horizontal", 1, Fraction(1,3)), ("quadrant", Fraction(1,2), Fraction(1,2))]
    print(f"{'device / orientation':34s}{'conf':22s}{'sceneW':>7s}{'sceneH':>7s}{'contH':>7s}{'usableW':>8s}{'maxP':>7s}  holds44")
    fails = 0; total = 0
    for (lab, W, H, top, bot, m, hb, src) in IPAD:
        for ori, (sw, sh) in (("portrait",(W,H)), ("landscape",(H,W))):
            for cname, fw, fh in CONF:
                w2 = float(sw*fw); h2 = float(sh*fh)
                cw, ch = scene_content(w2, h2, top, bot)
                uw = usable(cw)
                chrome = chromeH(ios, 'play-AI', 'L', uw)
                p = maxpitch(ch - chrome, uw, True, 720.0)
                total += 1
                ok = p >= 44
                if not ok: fails += 1
                if cname != 'full' or True:
                    print(f"{lab+' '+ori:34s}{cname:22s}{w2:7.0f}{h2:7.0f}{ch:7.0f}{uw:8.0f}{p:7.1f}  {'yes' if ok else 'NO'}")
    print(f"\n{fails} of {total} device-orientation x configuration cells cannot hold p=44 for ordinary play at default text.")
