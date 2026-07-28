import math
p=44.0
def pt(x): return x*p
def R(lo,hi): return (lo,hi)
def band(cl,w): return (cl-w/2, cl+w/2)

print("=== PRIMITIVES (units of p; pt at p=44) ===")
disc_r=0.40; disc_lift=disc_r*1.05; disc_drag=disc_r*1.10
print(f"disc r 0.40 -> {pt(0.40):.3f} pt ; diam 0.80 -> {pt(0.80):.3f} pt")
print(f"lifted disc edge x1.05 = {disc_lift:.5f} p ; dragged x1.10 = {disc_drag:.5f} p")
print(f"symbol 0.50 p = {pt(0.50):.3f} pt ; core 7p = {pt(7):.3f} pt")
print(f"marker band 0.42..0.50 -> {pt(0.42):.4f} .. {pt(0.50):.4f} pt")

M={}
M['SEL_rest']=band(0.440,0.030)
M['SEL_lift']=tuple(v*1.05 for v in band(0.440,0.030))
M['SEL_drag']=tuple(v*1.10 for v in band(0.440,0.030))
M['CAP']=(0.50-0.055,0.50); M['CAP_cl']=0.50-0.055/2
M['CAP_thick']=(0.50-0.07,0.50)
M['CHK_in']=band(0.4325,0.025)
M['CHK_out']=band(0.4875,0.025)
M['DOT']=(0.0,0.11); M['DOT_grown']=(0.0,0.165)
M['ORIG']=(0.11-0.045/2,0.11+0.045/2)
M['HOV']=(0.0,0.45)         # square half-extent
M['FOC']=band(0.44,0.06)    # square, at edge midpoints
for k in sorted(M):
    if k.endswith('_cl'): continue
    lo,hi=M[k]
    print(f"{k:10s} band [{lo:.5f},{hi:.5f}] p  = [{pt(lo):.3f},{pt(hi):.3f}] pt")

print("\n=== RULE A: CONTAINMENT (circular outer <= 0.50 p) ===")
for k in ['SEL_rest','SEL_lift','SEL_drag','CAP','CAP_thick','CHK_in','CHK_out','DOT_grown','ORIG']:
    hi=M[k][1]; ok = hi<=0.50+1e-12
    print(f"{k:10s} outer {hi:.6f} p  {'OK' if ok else '*** VIOLATION ***'}  slack {pt(0.50-hi):+.4f} pt")
print("square markers: HOV half-extent 0.45 <= 0.50 OK ; FOC half-extent 0.44+0.03=0.47 <= 0.50 OK")
print(f"max permissible uniform lift for SEL: 0.50/0.455 = {0.50/0.455:.6f}")

print("\n=== RULE B: AIR GAP (inner edge >= 0.42 p; disc 0.40, lifted 0.42) ===")
for k in ['SEL_rest','SEL_lift','CAP','CAP_thick','CHK_in','CHK_out','FOC','HOV','DOT','ORIG']:
    lo=M[k][0]; ok = lo>=0.42-1e-12
    print(f"{k:10s} inner {lo:.5f} p  {'OK' if ok else '*** BELOW 0.42 ***'} ; gap to rest disc {pt(lo-0.40):+.4f} pt ; gap to LIFTED disc {pt(lo-disc_lift):+.4f} pt")

print("\n=== BRACKETS ===")
inset=0.03; arm=0.16; sw=0.045
vx=0.50-inset  # elbow 0.47
armend=vx-arm  # 0.31
maxext=vx+sw/2
print(f"elbow ({vx},{vx}); arm end {armend}; ink max extent {maxext:.5f} p = {pt(maxext):.4f} pt (cell half = 0.50)")
near=math.hypot(armend,vx)-sw/2
print(f"nearest bracket ink radius = {near:.5f} p = {pt(near):.3f} pt")
gap_adj=2*(0.50-maxext)
print(f"adjacent cells' facing bracket arms ink gap = {gap_adj:.5f} p = {pt(gap_adj):.4f} pt   (at p=28 would be {gap_adj*28:.3f} pt)")
print(f"bracket vs CAP outer 0.50: clearance {near-0.50:.5f} p = {pt(near-0.50):.4f} pt")
print(f"bracket vs CHK outer 0.50: clearance {pt(near-0.50):.4f} pt")
print(f"bracket vs SEL_lift outer {M['SEL_lift'][1]:.5f}: clearance {pt(near-M['SEL_lift'][1]):.4f} pt")
print(f"bracket vs DOT_grown 0.165: clearance {pt(near-0.165):.4f} pt")
# diagonal neighbour brackets
d=math.sqrt(2)*(0.50-maxext)*1  # along diagonal
print(f"diagonal-neighbour bracket elbow gap along diagonal = {math.hypot(2*(0.50-maxext),2*(0.50-maxext)):.5f} p = {pt(math.hypot(2*(0.50-maxext),2*(0.50-maxext))):.4f} pt")

print("\n=== CHECK RING PAIR ===")
g=M['CHK_out'][0]-M['CHK_in'][1]
print(f"inter-ring gap = {g:.5f} p = {pt(g):.4f} pt   (PR body claims 1.32 pt)")
print(f"inner ring inner edge {M['CHK_in'][0]:.5f} == 0.42 exactly -> air gap = {pt(M['CHK_in'][0]-0.40):.4f} pt (the stated minimum 0.02p)")
for w in [0.030,0.035,0.040,0.050]:
    bi=band(0.4325,w); bo=band(0.4875,w)
    print(f"  pulse stroke {w:.3f}: inner ring [{bi[0]:.4f},{bi[1]:.4f}] (inner {'OK' if bi[0]>=0.42 else 'BREAKS 0.42'}), outer ring [{bo[0]:.4f},{bo[1]:.4f}] (outer {'OK' if bo[1]<=0.50 else 'BREAKS 0.50'}), gap {pt(bo[0]-bi[1]):+.3f} pt")

print("\n=== DASH GEOMETRY (capture ring) ===")
print(f"12*(18+12) = {12*(18+12)} degrees -> closes: {12*(18+12)==360}")
cl=M['CAP_cl']; w=0.055
dash=cl*math.radians(18); gap=cl*math.radians(12)
print(f"centre-line radius {cl:.5f} p = {pt(cl):.4f} pt")
print(f"nominal dash arc {dash:.6f} p = {pt(dash):.4f} pt ; nominal gap arc {gap:.6f} p = {pt(gap):.4f} pt")
print(f"ROUND CAPS add w/2 each end: visible dash {dash+w:.6f} p = {pt(dash+w):.4f} pt ; visible gap {gap-w:.6f} p = {pt(gap-w):.4f} pt")
print(f"duty cycle nominal {dash/(dash+gap)*100:.1f}% ink -> with caps {(dash+w)/(dash+gap)*100:.1f}% ink")
print(f"cap max radial reach = cl + w/2 = {cl+w/2:.5f} p (== outer edge 0.50) OK")

print("\n=== SAME-POINT PAIRS (ink overlap?) ===")
def ov(a,b):
    lo=max(a[0],b[0]); hi=min(a[1],b[1]); return hi-lo
pairs=[('SEL_lift','DOT_grown'),('SEL_lift','CAP'),('SEL_lift','CHK_out'),('SEL_lift','CHK_in'),
       ('CAP','CHK_in'),('CAP','CHK_out'),('CAP','DOT_grown'),
       ('FOC','SEL_lift'),('FOC','CAP'),('FOC','CHK_in'),('FOC','CHK_out'),('FOC','HOV'),
       ('HOV','CAP'),('HOV','CHK_in'),('HOV','CHK_out'),('HOV','SEL_lift'),('DOT_grown','ORIG')]
for a,b in pairs:
    o=ov(M[a],M[b])
    print(f"{a:10s} x {b:10s}: {'OVERLAP '+format(pt(o),'.3f')+' pt' if o>0 else 'disjoint by '+format(pt(-o),'.3f')+' pt'}")

print("\n=== ADJACENT-POINT WORST CASES (centres 1.0 p apart) ===")
outer={'SEL_rest':M['SEL_rest'][1],'SEL_lift':M['SEL_lift'][1],'SEL_drag':M['SEL_drag'][1],
       'CAP':0.50,'CHK_out':0.50,'FOC':0.47,'HOV':0.45,'BRK':maxext,'DOT_grown':0.165}
ks=list(outer)
for i in range(len(ks)):
    for j in range(i,len(ks)):
        a,b=ks[i],ks[j]; s=outer[a]+outer[b]
        if s>1.0-1e-12:
            print(f"  {a} + {b}: sum {s:.5f} p -> {'OVERLAP '+format(pt(s-1),'.4f')+' pt' if s>1+1e-12 else 'exactly tangent'}")
print("  (all other adjacent pairs clear)")
