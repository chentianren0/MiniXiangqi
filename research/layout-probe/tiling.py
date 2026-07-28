IPADS = [
 ("iPad mini (5th gen)", 768, 1024, "26 only"),
 ("iPad mini (6th gen) / mini (A17 Pro)", 744, 1133, "26 + 27"),
 ("iPad (8th gen) / iPad (9th gen)", 810, 1080, "8th: 26 only"),
 ("iPad (10th gen) / iPad (A16) / Air 4th,5th / Air 11\" M2,M3,M4", 820, 1180, "26 + 27"),
 ("iPad Air (3rd gen)", 834, 1112, "26 only"),
 ("iPad Pro 11\" 1st-4th gen", 834, 1194, "1st: 26 only"),
 ("iPad Pro 11\" M4 / M5", 834, 1210, "26 + 27"),
 ("iPad Pro 12.9\" 3rd-6th / Air 13\" M2,M3,M4", 1024, 1366, "3rd: 26 only"),
 ("iPad Pro 13\" M4 / M5", 1032, 1376, "26 + 27"),
]
def cfgs(w,h):
    return {
      "full":        (w,h),
      "half side":   (w/2,h),
      "half top/bot":(w,h/2),
      "third vert":  (w/3,h),
      "third horiz": (w,h/3),
      "quadrant":    (w/2,h/2),
    }
for minW,minH in [(380,500),(372,500),(320,560),(380,600),(320,600),(320,640),(0,0)]:
    print(f"\n### declared minimum {minW} x {minH}")
    names=list(cfgs(1,1).keys())
    print(f"{'device':<62} {'orient':<10} " + " ".join(f"{n:<13}" for n in names))
    for label,pw,ph,note in IPADS:
        for orient,(w,h) in (("portrait",(pw,ph)),("landscape",(ph,pw))):
            c=cfgs(w,h); cells=[]
            for n in names:
                cw,ch=c[n]
                ok = cw>=minW and ch>=minH
                cells.append(f"{cw:.0f}x{ch:.0f}{'' if ok else ' X'}")
            print(f"{label:<62} {orient:<10} " + " ".join(f"{x:<13}" for x in cells))
