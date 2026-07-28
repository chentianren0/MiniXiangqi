import math
p=44.0
def pt(x): return x*p
def band(cl,w): return (cl-w/2, cl+w/2)
print("=== (a) FOCUS RING, NEW: 0.92 p square, stroke 0.04 p, corner radius 0.14 p ===")
half=0.92/2; sw=0.04
FOC=(half-sw/2, half+sw/2)
print(f"band at edge midpoints = [{FOC[0]:.5f},{FOC[1]:.5f}] p  (doc claims 0.44 to 0.48)  -> [{pt(FOC[0]):.3f},{pt(FOC[1]):.3f}] pt")
disc_rest=0.40; disc_lift=0.40*1.05; disc_drag=0.40*1.10
print(f"vs disc at rest 0.40      : clearance {FOC[0]-disc_rest:+.5f} p = {pt(FOC[0]-disc_rest):+.3f} pt")
print(f"vs LIFTED disc x1.05 0.42 : clearance {FOC[0]-disc_lift:+.5f} p = {pt(FOC[0]-disc_lift):+.3f} pt   <- was -0.44 pt")
print(f"vs air-gap floor 0.42     : {'PASSES' if FOC[0]>=0.42 else 'FAILS'} by {pt(FOC[0]-0.42):+.3f} pt")
print(f"containment: square half-extent {FOC[1]:.5f} <= 0.50 -> {'OK' if FOC[1]<=0.50 else 'FAIL'}, slack {pt(0.50-FOC[1]):+.3f} pt")
cr=0.14; arc_c=half-cr
print(f"corner radius valid: {cr} <= half-side {half} -> {cr<=half}")
print(f"max radial reach at corners = {math.hypot(arc_c,arc_c)+cr+sw/2:.5f} p (cell corner is at 0.70711 p) -> OK (cell is square)")
CAP=(0.50-0.055,0.50); CHKi=band(0.4325,0.025); CHKo=band(0.4875,0.025)
SELl=tuple(v*1.05 for v in band(0.440,0.030)); HOV=(0.0,0.45)
def ov(a,b):
    o=min(a[1],b[1])-max(a[0],b[0])
    return ('OVERLAP %.3f pt'%pt(o)) if o>0 else ('disjoint %.3f pt'%pt(-o))
for nm,b in [('capture ring',CAP),('check inner',CHKi),('check outer',CHKo),('selection lifted',SELl),('hover fill',HOV)]:
    print(f"  FOC x {nm:17s}: {ov(FOC,b)}")
print(f"  adjacent point: FOC outer {FOC[1]} + capture 0.50 = {FOC[1]+0.50:.5f} -> {'OK' if FOC[1]+0.50<=1.0 else 'COLLIDE'}")

print("\n=== (b) CHECK PULSE BOUND, peak stroke 0.0325 p, growing only into the gap ===")
wr=0.025; wp=0.0325
inner=(0.42, 0.42+wp)          # inner edge pinned, grows outward
outer=(0.50-wp, 0.50)          # outer edge pinned, grows inward
print(f"rest : inner [{0.42:.5f},{0.42+wr:.5f}] outer [{0.50-wr:.5f},{0.50:.5f}] gap {pt(0.50-wr-(0.42+wr)):.4f} pt")
print(f"peak : inner [{inner[0]:.5f},{inner[1]:.5f}] outer [{outer[0]:.5f},{outer[1]:.5f}]")
g=outer[0]-inner[1]
print(f"peak gap = {g:.6f} p = {pt(g):.4f} pt   (doc claims 'at least 0.015 p')  -> {'EXACT' if abs(g-0.015)<1e-12 else 'MISMATCH'}")
print(f"0.42 crossed? {inner[0]<0.42}   0.50 crossed? {outer[1]>0.50}")
print(f"centre-lines shift: inner {0.4325:.5f} -> {(inner[0]+inner[1])/2:.5f} ; outer {0.4875:.5f} -> {(outer[0]+outer[1])/2:.5f}")

print("\n=== (c) AIR-GAP RULE over all 11 markers (occupied points only) ===")
M={'selection ring (rest)':band(0.440,0.030),'selection ring (x1.05)':SELl,
   'capture ring':CAP,'capture ring thickened':(0.43,0.50),
   'check inner (rest)':CHKi,'check inner (pulse peak)':inner,'check outer':CHKo,'check outer (pulse peak)':outer,
   'keyboard focus ring':FOC}
for k,b in M.items():
    print(f"  {k:26s} inner {b[0]:.5f}  {'PASS' if b[0]>=0.42-1e-12 else '*** FAIL ***'}")
print("  legal-destination dot / drag-origin marker / hover fill : EXEMPT (named in the rule)")

print("\n=== (e) BRACKETS: inset 0.03 -> 0.05 ===")
for inset in (0.03,0.05):
    for arm in (0.16,):
        vx=0.50-inset; ae=vx-arm; sw2=0.045
        mx=vx+sw2/2; near=math.hypot(ae,vx)-sw2/2
        print(f" inset {inset}: elbow ({vx:.2f},{vx:.2f}) armend {ae:.2f} maxext {mx:.5f} ({pt(mx):.3f} pt)")
        print(f"   containment {mx:.5f} <= 0.50 -> {'OK' if mx<=0.50 else 'FAIL'}, slack {pt(0.50-mx):+.3f} pt")
        print(f"   adjacent cells' facing arms ink gap = {2*(0.50-mx):.5f} p = {pt(2*(0.50-mx)):.4f} pt")
        print(f"   nearest ink radius {near:.5f} p ; vs capture/check outer 0.50 -> clearance {near-0.50:.5f} p = {pt(near-0.50):.4f} pt")
        print(f"   vs selection lifted {SELl[1]:.5f} -> {pt(near-SELl[1]):.3f} pt ; vs grown dot 0.165 -> {pt(near-0.165):.3f} pt")
        d=math.hypot(2*(0.50-mx),2*(0.50-mx)); print(f"   diagonal-neighbour bracket gap {pt(d):.4f} pt")
print(" arm sweep at inset 0.05 (clearance to the 0.50 ring):")
for arm in (0.16,0.15,0.14,0.13,0.12):
    vx=0.45; ae=vx-arm; near=math.hypot(ae,vx)-0.0225
    print(f"   arm {arm:.2f} -> nearest {near:.5f} p, clearance {pt(near-0.50):.3f} pt, arm length {pt(arm):.2f} pt")

print("\n=== (f) BUTT CAPS on the capture ring's dashes ===")
cl=0.50-0.055/2; w=0.055
dash=cl*math.radians(18); gap=cl*math.radians(12)
print(f"centre-line {cl:.5f} p ; butt caps add nothing")
print(f"visible dash {dash:.6f} p = {pt(dash):.4f} pt ; visible gap {gap:.6f} p = {pt(gap):.4f} pt ; duty {dash/(dash+gap)*100:.1f}% ink")
print(f"12*(18+12)=360 -> closes; butt cap end face is radial, max radius = outer edge {cl+w/2:.5f} p -> containment OK")
print(f"(round caps would have been: dash {pt(dash+w):.3f} pt, gap {pt(gap-w):.3f} pt, duty {(dash+w)/(dash+gap)*100:.1f}%)")
