#!/usr/bin/env python3
"""The constraint table: every (device x orientation x state x text size) cell."""
import re, sys
from budget8 import load, loadmac, h, blockH, maxpitch, strip, STATES, GAP, strips_shown, SZ, chromeH

ios = load('out8-se3-P.txt')
mac = loadmac('out-mac2.txt')

# ---- device table: (label, portraitW, portraitH, topInsetPortrait, bottomSafe, margin) ----
# topInset = window safe-area top (status bar). Tab container adds 83 (iPhone, bottom) or
# 64 (iPad, top). bottomSafe = home indicator.
IPHONE = [
    # label, W, H, topInset, bottomSafe, margin, source
    ("375x667  SE 2/3",          375, 667, 20, 0,  16, "measured"),
    ("375x812  11 Pro/12/13 mini",375, 812, 50, 34, 16, "measured"),
    ("390x844  12/13/14/16e/17e", 390, 844, 47, 34, 16, "layout-budget"),
    ("393x852  14 Pro/15/16",     393, 852, 59, 34, 16, "layout-budget"),
    ("402x874  16 Pro/17/17 Pro", 402, 874, 62, 34, 16, "layout-budget"),
    ("414x896  11 / 11 Pro Max",  414, 896, 48, 34, 20, "layout-budget"),
    ("420x912  Air",              420, 912, 68, 34, 20, "layout-budget"),
    ("428x926  12/13 Pro Max,14+",428, 926, 47, 34, 20, "layout-budget"),
    ("430x932  14 Pro Max/15+/16+",430,932, 59, 34, 20, "layout-budget"),
    ("440x956  16 Pro Max/17 PM", 440, 956, 62, 34, 20, "measured"),
]
# iPad: (label, portraitW, portraitH, topSafe, bottomSafe, margin, homeButton)
IPAD = [
    ("744x1133 mini 6 / mini A17", 744, 1133, 32, 25, 20, False, "measured"),
    ("768x1024 mini 5",            768, 1024, 32, 0,  20, True,  "transferred"),
    ("810x1080 iPad 8 / 9",        810, 1080, 32, 0,  20, True,  "measured"),
    ("820x1180 iPad 10/A16/Air11", 820, 1180, 32, 25, 20, False, "measured"),
    ("834x1112 Air 3",             834, 1112, 32, 0,  20, True,  "transferred"),
    ("834x1194 Pro 11 1st-4th",    834, 1194, 32, 25, 20, False, "transferred"),
    ("834x1210 Pro 11 M4/M5",      834, 1210, 32, 25, 20, False, "transferred"),
    ("1024x1366 Pro 12.9/Air 13",  1024,1366, 32, 25, 20, False, "transferred"),
    ("1032x1376 Pro 13 M4/M5",     1032,1376, 32, 25, 20, False, "measured"),
]

TABBAR_PHONE = 83.0     # measured: contribution to the bottom safe area, every iPhone
TABBAR_IPAD_TOP = 64.0  # measured: top tab bar, iPad, regular width
SIDEBAR_W = 280.0       # measured: sidebarAdaptable leading inset when it presents as a sidebar

PANEL_MIN = 320.0       # derived, layout-budget 4.1 (untruncated terminal metadata line)
GUTTER = 16.0

def iphone_content(dev, navbar=False):
    _, W, H, top, bot, m, _ = dev
    ch = H - top - TABBAR_PHONE - (54.0 if navbar else 0.0)
    return W - 2*m, ch

def ipad_content_portrait(dev, navbar=False):
    _, W, H, top, bot, m, hb, _ = dev
    ch = H - top - TABBAR_IPAD_TOP - bot - (0.0 if navbar else 0.0)
    return W - 2*m, ch

def ipad_content_landscape(dev, sidebar=True):
    _, W, H, top, bot, m, hb, _ = dev
    LW, LH = H, W                     # landscape: swap
    if sidebar:
        avail_w = LW - SIDEBAR_W
        ch = LH - top - bot           # measured: no top tab bar when the sidebar shows
    else:
        avail_w = LW
        ch = LH - top - TABBAR_IPAD_TOP - bot
    return avail_w - 2*m, ch

def maxp(rows, state, sz, contentH, usableW, cap=720.0):
    ch = chromeH(rows, state, sz, usableW)
    availH = contentH - ch
    p = maxpitch(availH, usableW, strips_shown(sz), cap)
    return p, availH, ch

def holds(rows, state, sz, contentH, usableW):
    p, availH, ch = maxp(rows, state, sz, contentH, usableW)
    return p >= 44.0, p, availH

STATE_ORDER = ['play-AI','play-Free','result-replaces','result-alongside','threefold-replaces',
               'replay-transport','replay-speed','replay-list1','replay-list3','prestart-AI']

def grid(title, devlist, contentfn, rows=ios):
    print("\n### " + title)
    hdr = f"{'device':30s}{'usableW':>9s}{'contentH':>9s}  " + "  ".join(f"{s:>4s}" for s in SZ)
    for st in STATE_ORDER:
        print(f"\n-- state: {st}")
        print(hdr)
        for dev in devlist:
            uw, chh = contentfn(dev)
            cells = []
            for s in SZ:
                ok, p, _ = holds(rows, st, s, chh, uw)
                cells.append(f"{p:4.0f}" if ok else " -- ")
            print(f"{dev[0]:30s}{uw:9.0f}{chh:9.0f}  " + "  ".join(cells))

if __name__ == '__main__':
    what = sys.argv[1] if len(sys.argv) > 1 else 'all'
    if what in ('all','iphone'):
        grid("iPhone portrait, no navigation bar (max pitch; -- = below 44)", IPHONE, lambda d: iphone_content(d, False))
    if what in ('all','iphonenav'):
        grid("iPhone portrait, WITH an inline navigation bar", IPHONE, lambda d: iphone_content(d, True))
    if what in ('all','ipadp'):
        grid("iPad portrait, full screen, top tab bar", IPAD, ipad_content_portrait)
    if what in ('all','ipadl'):
        grid("iPad landscape, full screen, sidebar (measured 280 pt)", IPAD, lambda d: ipad_content_landscape(d, True))
    if what in ('all','ipadlt'):
        grid("iPad landscape, full screen, top tab bar (user switched away from the sidebar)", IPAD, lambda d: ipad_content_landscape(d, False))
