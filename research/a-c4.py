CASES = [
 ("I2  6-ply cycle, every white move chases (wK e1, bK d7)",
  "3k3/7/c6/7/2R4/7/4K2 w - - 0 1", ['c3a3','a5b5','a3b3','b5c5','b3c3','c5a5']*2),
 ("I2b same 6-ply cycle, only 2 of 3 white moves chase (white soldier c4 blocks)",
  "3k3/7/c6/2P4/2R4/7/4K2 w - - 0 1", ['c3a3','a5b5','a3b3','b5c5','b3c3','c5a5']*2),
 ("SYM rook chases rook (mutual attack, equal value)",
  "4k2/7/r6/7/1R5/7/2K4 w - - 0 1", ['b3a3','a5b5','a3b3','b5a5']*2),
 ("SYMp rook chases a PINNED rook (mutual attack but recapture illegal)",
  "4k2/7/r6/7/1R5/7/2K1R2 w - - 0 1", ['b3a3','a5b5','a3b3','b5a5']*2),
 ("VAL cannon chases unprotected rook",
  "4k2/7/r6/7/1C5/7/2K4 w - - 0 1", ['b3a3','a5b5','a3b3','b5a5']*2),
 ("VALp cannon chases PROTECTED rook (rook e5 defends a5/b5)",
  "4k2/7/r3r2/7/1C5/7/2K4 w - - 0 1", ['b3a3','a5b5','a3b3','b5a5']*2),
 ("EQ  rook chases protected cannon of unequal type but protected (control=chs-002)",
  "4k2/7/c3r2/7/1R5/7/2K4 w - - 0 1", ['b3a3','a5b5','a3b3','b5a5']*2),
]
for label, fen, mv in CASES:
    print(f"{label}\n    fen={fen}  (stm={fen.split()[1]})  -> {verdict(fen,mv)}")
