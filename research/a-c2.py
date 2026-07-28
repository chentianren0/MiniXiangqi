def rep(fen, cyc, n=2):
    return list(cyc) * n

CASES = [
 # --- Q1 protection ---
 ("P1  pinned defender (rook e5 pinned by Re1)",
  "4k2/7/c3r2/7/1R5/7/2K1R2 w - - 0 1",
  ['b3a3','a5b5','a3b3','b5a5']*2),
 ("P1c control: same, no pinner (= mx-chs-002)",
  "4k2/7/c3r2/7/1R5/7/2K4 w - - 0 1",
  ['b3a3','a5b5','a3b3','b5a5']*2),
 ("P2  king sole defender, recapture sq OUTSIDE palace (b5, k on c5)",
  "7/7/1ck4/R6/7/7/3K3 w - - 0 1",
  ['a4a5','b5b4','a5a4','b4b5']*2),
 ("P3  king sole defender, recapture sq INSIDE palace (d5, k on d6)",
  "7/3k3/3c3/2R4/7/7/2K4 w - - 0 1",
  ['c4c5','d5d4','c5c4','d4d5']*2),
 ("P4  king sole defender but recapture illegal by flying general (wK d1)",
  "7/2kc3/6R/7/7/7/3K3 w - - 0 1",
  ['g5g6','d6d5','g6g5','d5d6']*2),
 ("P4c control: same but wK on e1 (recapture legal)",
  "7/2kc3/6R/7/7/7/4K2 w - - 0 1",
  ['g5g6','d6d5','g6g5','d5d6']*2),
 ("P5  horse chases PROTECTED rook (value rule)",
  "4k2/3N3/r3r2/7/7/7/3K3 w - - 0 1",
  ['d6c4','a5b5','c4d6','b5a5']*2),
 ("P6  soldier as chaser vs unprotected cannon",
  "4k2/7/1c5/2P4/7/7/3K3 w - - 0 1",
  ['c4b4','b5c5','b4c4','c5b5']*2),
 ("P7  king as chaser vs unprotected cannon",
  "4k2/7/7/7/2c4/3K3/7 w - - 0 1",
  ['d2c2','c3d3','c2d2','d3c3']*2),
]
for label, fen, mv in CASES:
    stm = fen.split()[1]
    print(f"{label}\n    fen={fen}  (stm={stm})  -> {verdict(fen,mv)}")
