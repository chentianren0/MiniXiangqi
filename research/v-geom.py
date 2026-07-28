"""Scratch: recompute every number in board-visual-language-design.fable-partial.md
sections 1, 2.2, 2.3, 2.4, 2.5.  Workspace-only verification evidence."""
import math

P = (44.0, 28.0)


def at(v):
    return f"{v*44:.3f} / {v*28:.3f} pt"


print("=== §1 table ===")
print("disc 0.84p        ", at(0.84), " draft: 37.0 / 23.5")
print("symbol 0.50p      ", at(0.50), " draft: 22.0 / 14.0")
print("board core 7p     ", at(7.0), " draft: 308 / 196")

print("\n=== §1 chain (0.84p disc) ===")
disc_r = 0.42
print("disc edge         ", disc_r)
print("cell boundary     ", 0.50)
print("neighbour disc edge", 1.00 - disc_r)
print("cell corner       ", round(math.sqrt(2) / 2, 4))
band = (1.00 - disc_r) - disc_r
print("working band      ", band, at(band), " draft: 0.16p, 7.0 / 4.5")

print("\n=== §1 claim: 0.86p disc collides with S6 outer edge ===")
d86 = 0.43
print("0.86p disc edge            ", d86)
print("0.86p neighbour disc edge  ", 1.00 - d86)
print("S6 outer edge (0.54+0.02)  ", 0.56)
print("clearance at 0.86p         ", (1.00 - d86) - 0.56, "->", at((1.00 - d86) - 0.56))
print("S6 inner ring inner edge   ", 0.46 - 0.02, "vs disc edge", d86,
      "-> air gap", (0.46 - 0.02) - d86)
print("COLLISION?", (1.00 - d86) - 0.56 < 0)

print("\n=== S1 ring, stroke 0.05p, centre-line 0.4625p ===")
s1_cl, s1_w = 0.4625, 0.05
s1_in, s1_out = s1_cl - s1_w / 2, s1_cl + s1_w / 2
print("inner / outer edge       ", s1_in, s1_out, " draft says 0.44 / 0.485")
print("edges implied by w=0.045 ", s1_cl - 0.045 / 2, s1_cl + 0.045 / 2)
print("air gap to disc edge     ", s1_in - disc_r, at(s1_in - disc_r),
      " (§1 rule demands >= 0.02p)")
print("outer edge under x1.05   ", s1_out * 1.05, " draft: ~0.51p")
print("centre-line under x1.05  ", s1_cl * 1.05, " draft (§2.4): ~0.486p")

print("\n=== S6 double ring ===")
r_in, r_out, w6 = 0.46, 0.54, 0.04
print("inner ring band ", r_in - w6 / 2, r_in + w6 / 2)
print("outer ring band ", r_out - w6 / 2, r_out + w6 / 2)
gap6 = (r_out - w6 / 2) - (r_in + w6 / 2)
print("inter-ring gap  ", gap6, at(gap6), " draft: 0.04p, 1.8 / 1.1")
print("S6 outer edge crosses cell boundary 0.50p?", r_out + w6 / 2 > 0.50)

print("\n=== S1(lifted) + S6-outer, the §2.4 'clear gap' ===")
g = (r_out - w6 / 2) - s1_out * 1.05
print("gap ", g, at(g), " -- §2.3 claims every gap >= ~0.6 pt")

print("\n=== S3 dashed ring ===")
s3_cl, s3_w = 0.47, 0.06
print("band              ", s3_cl - s3_w / 2, s3_cl + s3_w / 2)
print("12 x (18+12)      ", 12 * (18 + 12))
dash = s3_cl * math.radians(18)
gap = s3_cl * math.radians(12)
print("dash arc (centre) ", dash, at(dash), " draft: 6.5 / 4.1")
print("gap  arc (centre) ", gap, at(gap), " draft §2.3: 4.3 / 2.7")
print("round caps add w to dash, subtract w from gap:")
print("  visible dash ", dash + s3_w, at(dash + s3_w))
print("  visible gap  ", gap - s3_w, at(gap - s3_w))
print("thickened to 0.08p (S10): band", s3_cl - 0.04, s3_cl + 0.04,
      "-> outer beyond 0.50p?", s3_cl + 0.04 > 0.50)

print("\n=== S4 brackets: inset 0.03p from cell corner, arm 0.16p, stroke 0.045p ===")
vx = 0.5 - 0.03
inner_end = vx - 0.16
d_centreline = math.hypot(inner_end, vx)
print("corner vertex        ", (vx, vx))
print("arm inner endpoint   ", (inner_end, vx))
print("nearest centre-line r", d_centreline)
print("nearest ink r        ", d_centreline - 0.045 / 2)
print("vs S3 outer 0.50p -> disjoint?", d_centreline - 0.045 / 2 > 0.50,
      "clearance", d_centreline - 0.045 / 2 - 0.50,
      at(d_centreline - 0.045 / 2 - 0.50))
print("vs S2 dot edge 0.11p -> nearest approach",
      d_centreline - 0.045 / 2 - 0.11, "(draft claims > 0.3p)")
print("adjacent-cell bracket arms: centre-lines 0.06p apart, ink gap",
      0.06 - 0.045, at(0.06 - 0.045))

print("\n=== adjacent-cell marker collisions (centres 1.0p apart) ===")
print("neighbour S3 near edge from us:", 1.0 - 0.50)
print("  vs S1 at rest  outer", s1_out, "-> gap", 0.50 - s1_out, at(0.50 - s1_out))
print("  vs S1 lifted   outer", s1_out * 1.05, "-> OVERLAP",
      s1_out * 1.05 - 0.50, at(s1_out * 1.05 - 0.50))
print("  vs S6 outer edge", r_out + w6 / 2, "-> OVERLAP",
      (r_out + w6 / 2) - 0.50, at((r_out + w6 / 2) - 0.50))
print("two adjacent S3 rings: sum of centre-line radii", 2 * s3_cl,
      "outer edges", 2 * (s3_cl + s3_w / 2), "-> tangent?", 2 * (s3_cl + s3_w / 2) == 1.0)

print("\n=== S12 focus square 0.94p, stroke 0.06p ===")
half = 0.94 / 2
print("side at         ", half, " ink band at cardinal", half - 0.03, half + 0.03)
print("S3 band         ", s3_cl - s3_w / 2, s3_cl + s3_w / 2, "-> IDENTICAL band")
print("S6 outer ring crosses square at cos(t)=", half / r_out,
      "-> t =", math.degrees(math.acos(half / r_out)), "deg (8 crossings)")
print("S11 fill half-extent", 0.90 / 2, "vs S12 inner edge", half - 0.03,
      "-> fill overruns by", 0.90 / 2 - (half - 0.03))

print("\n=== S7 crossed circle ===")
print("radius 0.22p vs disc radius 0.42p -> entirely inside the disc face:",
      0.22 < disc_r)

print("\n=== S10 origin ring, 'same Ø' as S2 ===")
print("if 0.22p is OUTER dia: void dia", 0.22 - 2 * 0.045, at(0.22 - 2 * 0.045),
      " draft: 3.6 pt at p=28")
print("if 0.22p is CENTRE-LINE dia: void dia", 0.22 - 0.045,
      at(0.22 - 0.045), " outer dia", 0.22 + 0.045)

print("\n=== §2.3 'every stroke > 1 pt at p=28' ===")
for name, w in [("S1", 0.05), ("S3", 0.06), ("S4", 0.045), ("S6", 0.04),
                ("S7", 0.045), ("S10", 0.045), ("S12", 0.06)]:
    print(f"  {name}: {w*28:.2f} pt", "OK" if w * 28 > 1 else "FAIL")

print("\n=== §2.3 'every distinguishing gap >= ~0.6 pt at p=28' ===")
for name, g in [("dash gap (no caps)", gap), ("dash gap (round caps)", gap - s3_w),
                ("S6 inter-ring", gap6), ("air gap rule 0.02p", 0.02),
                ("S1 actual air gap", s1_in - disc_r),
                ("S1(lift)+S6outer", (r_out - w6 / 2) - s1_out * 1.05),
                ("adjacent S4 arms", 0.06 - 0.045),
                ("S1(rest) to adjacent S3", 0.50 - s1_out)]:
    print(f"  {name:26s} {g:.6f}p = {g*28:.3f} pt",
          "OK" if g * 28 >= 0.6 else "FAIL")
