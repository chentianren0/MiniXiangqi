CASES = [
 ("MUT  mutual perpetual chase (both sides discovered-chase)",
  "2k2r1/7/1cN1R2/7/2r1nC1/7/1R2K2 w - - 0 1", ['c5b3','e3f5','b3c5','f5e3']*2),
 ("MUTa white apparatus only -> unilateral white chase",
  "2k4/7/1cN1R2/7/4n2/7/1R2K2 w - - 0 1",     ['c5b3','e3f5','b3c5','f5e3']*2),
 ("MUTb black apparatus only -> unilateral black chase",
  "2k2r1/7/2N4/7/2r1nC1/7/4K2 w - - 0 1",     ['c5b3','e3f5','b3c5','f5e3']*2),
 ("CTRL horse chases PROTECTED cannon (no value bonus) - expect draw",
  "4k2/3N3/c3r2/7/7/7/3K3 w - - 0 1", ['d6c4','a5b5','c4d6','b5a5']*2),
]
for label, fen, mv in CASES:
    print(f"{label}\n    fen={fen}  -> {verdict(fen,mv)}")
