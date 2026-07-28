#!/usr/bin/env python3
"""Constraint-table arithmetic over the probe8 measurements."""
import re, sys, json
from fractions import Fraction

SZ = ['xS','S','M','L','xL','xxL','xxxL','AX1','AX2','AX3','AX4','AX5']

def load(path):
    rows = {}
    for ln in open(path):
        m = re.match(r'E\[(\w+)\] (\w+) idealW=([\d.]+) idealH=([\d.]+)(.*)', ln.strip())
        if not m: continue
        sz, name, iw, ih, rest = m.groups()
        ws = {int(a): float(b) for a, b in re.findall(r'h@(\d+)=([\d.]+)', rest)}
        rows[(name, sz)] = {'iw': float(iw), 'ih': float(ih), 'w': ws}
    return rows

def loadmac(path):
    rows = {}
    for ln in open(path):
        m = re.match(r'MACELEM\[(\w+)\] (\w+) idealW=([\d.]+) idealH=([\d.]+)(.*)', ln.strip())
        if not m: continue
        sz, name, iw, ih, rest = m.groups()
        ws = {int(a): float(b) for a, b in re.findall(r'h@(\d+)=([\d.]+)', rest)}
        rows[(name, sz)] = {'iw': float(iw), 'ih': float(ih), 'w': ws}
    return rows

WIDTHS = [264,280,308,320,328,343,359,375,388,398,404,424,686,712,720]
def h(rows, name, sz, w):
    """height of element at content width w (nearest measured width, rounding DOWN
    to the largest measured width <= w, which is conservative)."""
    r = rows[(name, sz)]
    cands = [x for x in WIDTHS if x <= w]
    if not cands: return r['w'][WIDTHS[0]]
    return r['w'][max(cands)]

# ---------- board block ----------
def strip(p):
    s = round(min(20, max(13, 0.32*p)))
    return round(0.08*p + 0.887*s)

def blockH(p, strips=True):
    return 7*p + (2*strip(p) if strips else 0)

def maxpitch(availH, availW, strips=True, cap=720.0):
    """largest p such that blockH(p)<=availH and 7p<=availW and 7p<=cap"""
    lo, hi = 1.0, 400.0
    for _ in range(200):
        mid = (lo+hi)/2
        if blockH(mid, strips) <= availH and 7*mid <= availW and 7*mid <= cap:
            lo = mid
        else:
            hi = mid
    return lo

GAP = 12.0

def strips_shown(sz):
    return sz in ('xS','S','M','L','xL','xxL','xxxL')

# ---------- states ----------
# each state: list of (element name, count) that sit outside the board block
STATES = {
  'play-AI':              [('turnStatus',1), ('controlRowAI',1)],
  'play-Free':            [('turnStatus',1), ('controlRowFree',1)],
  'result-replaces':      [('turnStatus',1), ('resultCard',1)],
  'result-alongside':     [('turnStatus',1), ('controlRowAI',1), ('resultCard',1)],
  'result-recorded':      [('turnStatus',1), ('resultCardRecorded',1)],
  'threefold-replaces':   [('turnStatus',1), ('repetitionNotice',1)],
  'threefold-alongside':  [('turnStatus',1), ('controlRowAI',1), ('repetitionNotice',1)],
  'claim-retained':       [('turnStatus',1), ('controlRowAI',1)],   # 可判和 carried by 判和
  'replay-transport':     [('turnStatus',1), ('transport6',1)],
  'replay-t7':            [('turnStatus',1), ('transport7',1)],
  'replay-speed':         [('turnStatus',1), ('transportPlusSpeed',1)],
  'replay-list1':         [('turnStatus',1), ('transportPlusSpeed',1), ('moveListRow',1)],
  'replay-list3':         [('turnStatus',1), ('transportPlusSpeed',1), ('moveListRow',3)],
  'replay-list5':         [('turnStatus',1), ('transportPlusSpeed',1), ('moveListRow',5)],
  'prestart-AI':          [('preStartAI',1)],
  'prestart-Free':        [('preStartFree',1)],
}

def chromeH(rows, state, sz, w):
    items = STATES[state]
    tot = 0.0
    n = 0
    for name, c in items:
        tot += c*h(rows, name, sz, w)
        n += c
    return tot + n*GAP    # one gap per element, separating it from the board block

def required(rows, state, sz, w, p=44.0):
    return chromeH(rows, state, sz, w) + blockH(p, strips_shown(sz))

def maxp_for(rows, state, sz, contentH, contentW, marginX=16.0):
    availW = contentW - 2*marginX
    availH = contentH - chromeH(rows, state, sz, availW)
    return maxpitch(availH, availW, strips_shown(sz)), availH

if __name__ == '__main__':
    ios = load('out8-se3-P.txt')
    mac = loadmac('out-mac2.txt')
    mode = sys.argv[1] if len(sys.argv) > 1 else 'req'

    if mode == 'req':
        # minimum content height needed for p=44, per state per text size, at width 343
        print("iOS: content height required for p>=44, width 343 (SE)")
        print(f"{'state':22s}" + ''.join(f"{s:>8s}" for s in SZ))
        for st in STATES:
            print(f"{st:22s}" + ''.join(f"{required(ios,st,s,343):8.1f}" for s in SZ))
        print()
        print("macOS: content height required for p>=44, width 343")
        print(f"{'state':22s}" + ''.join(f"{s:>8s}" for s in SZ))
        for st in STATES:
            try:
                print(f"{st:22s}" + ''.join(f"{required(mac,st,s,343):8.1f}" for s in SZ))
            except KeyError as e:
                print(f"{st:22s} missing {e}")
