import sys
sys.path.insert(0, "/Users/tianren/coding/minixiangqi/discussion-drafts/w-base")
import pyffish as sf
T = "mxq_target"
sf.load_variant_config("""
[mxq_target:minixiangqi]
chasingRule = axf
nMoveRule = 0
promotedSoldiersChaseable = false
""")

def lm(tag, fen, moves=[]):
    print(f"{tag}: fen={sf.get_fen(T,fen,moves)}\n   legal={sorted(sf.legal_moves(T,fen,moves))}")

print("--- 028: is the white rook absolutely pinned? (Rxb3 / Rxb4 must be absent)")
lm("028 ply0", "3rk2/7/7/3R3/1c5/7/3K3 w - - 0 1")
lm("028 ply2", "3rk2/7/7/3R3/1c5/7/3K3 w - - 0 1", ["d4d3","b3b4"])

print("\n--- 029: is the black rook free? (must have moves off the c-file)")
lm("029 ply1", "2k4/7/R6/2r4/7/2P4/2K4 w - - 0 1", ["a5a4"])
print("   white soldier c2 attack set: verify it does not defend a4/a5")
lm("029 soldier probe (white to move, rook removed)", "2k4/7/7/2r4/7/2P4/2K4 w - - 0 1")

print("\n--- 030/031: the bare wheel with no entry move is a perpetual chase")
W = ["a5b5","a3b3","b5a5","b3a3"]
for n in (4,8):
    print("   bare wheel from a3, %d plies:" % n,
          sf.is_optional_game_end(T, "4k2/7/c6/7/R6/7/2K4 b - - 0 1", W[:0]+ (W*2)[:n]))

print("\n--- boundary prefixes must not be ended")
cases = [
  ("028", "3rk2/7/7/3R3/1c5/7/3K3 w - - 0 1", ["d4d3","b3b4","d3d4","b4b3"]*2, 4),
  ("029", "2k4/7/R6/2r4/7/2P4/2K4 w - - 0 1", ["a5a4","c4c5","a4a5","c5c4"]*2, 4),
  ("030", "4k2/7/c6/7/7/7/R1K4 w - - 0 1", ["a1a3"]+W*2, 5),
  ("031", "4k2/7/c6/7/1R5/7/2K4 w - - 0 1", ["b3a3"]+W*2, 5),
  ("032", "4k2/7/c6/7/7/7/R1K4 w - - 0 1", ["a1a3"]+W*2+["a5b5"], 6),
]
for name, fen, mv, pl in cases:
    pref = mv[:pl]
    f = sf.get_fen(T, fen, pref)
    print(f"   {name} prefix_len={pl}: {sf.is_optional_game_end(T, fen, pref)}  fen={f}")
