#!/usr/bin/env python3
"""Vertical-budget arithmetic for the Mini Xiangqi stacked layout.

Every input below is either measured (see out-*.txt / out3-*.txt in this
directory) or taken from an accepted/proposed contract line, and is labelled.
"""

# ---- measured chrome (iOS 27.0 simulator, Xcode 27A5228h) -------------------
# screen height, top safe-area inset, tab-bar contribution to bottom safe area
IPHONES = [
    # (label, w, h, topSafe, tabBottom, devices)
    ("375x667", 375, 667, 20, 83, "iPhone SE (2nd gen), iPhone SE (3rd gen)"),
    ("375x812", 375, 812, 50, 83, "iPhone 11 Pro, 12 mini, 13 mini"),
    ("390x844", 390, 844, 47, 83, "iPhone 12, 12 Pro, 13, 13 Pro, 14, 16e, 17e"),
    ("393x852", 393, 852, 59, 83, "iPhone 14 Pro, 15, 15 Pro, 16"),
    ("402x874", 402, 874, 62, 83, "iPhone 16 Pro, 17, 17 Pro"),
    ("414x896", 414, 896, 48, 83, "iPhone 11, 11 Pro Max"),
    ("420x912", 420, 912, 68, 83, "iPhone Air"),
    ("428x926", 428, 926, 47, 83, "iPhone 12 Pro Max, 13 Pro Max, 14 Plus"),
    ("430x932", 430, 932, 59, 83, "iPhone 14 Pro Max, 15 Plus, 15 Pro Max, 16 Plus"),
    ("440x956", 440, 956, 62, 83, "iPhone 16 Pro Max, 17 Pro Max"),
]

NAVBAR = 54.0        # measured, inline title
TABBAR = 83.0        # measured, contribution to the content's bottom safe area

# ---- board block (design/frame-motion-glass) --------------------------------
def board_block(p, strips=True):
    core = 7 * p
    if not strips:
        return core, core
    s = min(max(0.32 * p, 13), 20)
    strip = 0.08 * p + 0.887 * s
    return core, core + 2 * strip

# ---- measured element heights (accepted copy, iPhone SE, iOS 27.0) ---------
# key: (element, dynamic-type label) -> height at 375 pt wide
H = {
    ("turnStatus", "L"): 36.5,   ("turnStatus", "AX5"): 141.5,
    ("controlRow", "L"): 66.5,   ("controlRow", "AX5"): 171.5,
    ("resultCard", "L"): 127.0,  ("resultCard", "AX5"): 313.0,
    ("repetition", "L"): 95.0,   ("repetition", "AX5"): 429.0,
    ("transport",  "L"): 65.5,   ("transport",  "AX5"): 93.5,
    ("transportSpeed", "L"): 104.5, ("transportSpeed", "AX5"): 132.5,
    ("moveRow",    "L"): 32.5,   ("moveRow",    "AX5"): 261.5,
}
GAP = 12.0   # one standard inter-element gap; elements already carry 8 pt padding

def content_height(h, topSafe, navbar=True):
    return h - topSafe - TABBAR - (NAVBAR if navbar else 0)

STATES = {
    # name: (list of element keys stacked with the board, number of gaps)
    "play (status + controls)":      (["turnStatus", "controlRow"], 2),
    "result card (card replaces controls)": (["turnStatus", "resultCard"], 2),
    "result card (card + controls)": (["turnStatus", "controlRow", "resultCard"], 3),
    "threefold notice (replaces controls)": (["turnStatus", "repetition"], 2),
    "replay (transport + speed + 3 move rows)": (["turnStatus", "transportSpeed", "moveRow", "moveRow", "moveRow"], 3),
    "replay (transport only + 1 move row)": (["transport", "moveRow"], 2),
}

def chrome_sum(keys, gaps, dts):
    return sum(H[(k, dts)] for k in keys) + gaps * GAP

def report(navbar, dts, strips):
    print(f"\n=== navbar={navbar}  dynamicType={dts}  numeral strips={'shown' if strips else 'hidden'} ===")
    core44, block44 = board_block(44, strips)
    print(f"board core at p=44: {core44:.0f};  board block: {block44:.1f}")
    hdr = f"{'screen':<9} {'content':>8} " + " ".join(f"{n[:22]:>24}" for n in STATES)
    print(hdr)
    for label, w, h, top, tb, devs in IPHONES:
        ch = content_height(h, top, navbar)
        cells = []
        for name, (keys, gaps) in STATES.items():
            cs = chrome_sum(keys, gaps, dts)
            avail = ch - cs
            # largest p such that block(p) <= avail
            lo, hi = 1.0, 200.0
            for _ in range(60):
                mid = (lo + hi) / 2
                if board_block(mid, strips)[1] <= avail:
                    lo = mid
                else:
                    hi = mid
            slack = avail - block44
            cells.append(f"{slack:+8.1f}/p={lo:5.1f}" + ("  " if slack >= 0 else " X"))
        print(f"{label:<9} {ch:8.0f} " + " ".join(f"{c:>24}" for c in cells))

if __name__ == "__main__":
    for navbar in (True, False):
        report(navbar, "L", True)
    report(False, "L", False)
    report(False, "AX5", False)
    report(True, "AX5", False)
