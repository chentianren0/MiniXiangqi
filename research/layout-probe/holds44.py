# Largest Dynamic Type size at which the 44 pt pitch floor holds, per device per state.
# Element heights measured at 375 pt width (probe3, iOS 27.0). Strips hidden at AX sizes
# per design/frame-motion-glass; shown at L..xxxL.
H = {
 "L":   dict(turn=36.5, ctrl=66.5, card=127.0, rep=95.0, tr=65.5, trs=104.5, row=32.5),
 "xxxL":dict(turn=43.5, ctrl=73.5, card=148.5, rep=138.0, tr=72.0, trs=111.0, row=68.5),
 "AX1": dict(turn=49.5, ctrl=79.5, card=166.5, rep=155.0, tr=71.5, trs=110.5, row=79.5),
 "AX3": dict(turn=64.0, ctrl=142.0, card=206.0, rep=246.0, tr=81.5, trs=120.5, row=156.0),
 "AX5": dict(turn=141.5, ctrl=171.5, card=313.0, rep=429.0, tr=93.5, trs=132.5, row=261.5),
}
ORDER=["L","xxxL","AX1","AX3","AX5"]
BLOCK={"L":340.0,"xxxL":340.0,"AX1":308.0,"AX3":308.0,"AX5":308.0}  # strips hidden at AX sizes
GAP=12.0
STATES={
 "play":            lambda e:(e["turn"]+e["ctrl"], 2),
 "result card":     lambda e:(e["turn"]+e["card"], 2),
 "threefold notice":lambda e:(e["turn"]+e["rep"], 2),
 "replay min (transport + 1 row)": lambda e:(e["turn"]+e["tr"]+e["row"], 3),
 "replay full (transport+speed+3 rows)": lambda e:(e["turn"]+e["trs"]+3*e["row"], 4),
}
IPHONES=[("375x667",667,20,"SE 2nd/3rd gen"),("375x812",812,50,"11 Pro, 12 mini, 13 mini"),
 ("390x844",844,47,"12,12P,13,13P,14,16e,17e"),("393x852",852,59,"14P,15,15P,16"),
 ("402x874",874,62,"16P,17,17P"),("414x896",896,48,"11, 11PM"),("420x912",912,68,"Air"),
 ("428x926",926,47,"12PM,13PM,14+"),("430x932",932,59,"14PM,15+,15PM,16+"),("440x956",956,62,"16PM,17PM")]
TAB=83.0; NAV=54.0
for nav in (True,False):
    print(f"\n### navigation bar on the board page: {'yes' if nav else 'no'}  (tab bar always 83)")
    print(f"{'screen':<9}{'content':>8}  " + "".join(f"{s[:30]:<34}" for s in STATES))
    for lbl,h,top,devs in IPHONES:
        ch=h-top-TAB-(NAV if nav else 0)
        cells=[]
        for sname,fn in STATES.items():
            best="none"
            for dts in ORDER:
                e=H[dts]; s,g=fn(e)
                if BLOCK[dts]+s+g*GAP <= ch: best=dts
                else: break
            # slack at L
            e=H["L"]; s,g=fn(e); slackL=ch-(BLOCK["L"]+s+g*GAP)
            cells.append(f"holds to {best:<5} (L slack {slackL:+7.1f})")
        print(f"{lbl:<9}{ch:8.0f}  " + "".join(f"{c:<34}" for c in cells))
