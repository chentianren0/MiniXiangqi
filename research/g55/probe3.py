import sys
sys.path.insert(0, "/Users/tianren/coding/minixiangqi/discussion-drafts/w-base")
import pyffish as sf
T = "mxq_target"
sf.load_variant_config("[mxq_target:minixiangqi]\nchasingRule = axf\nnMoveRule = 0\npromotedSoldiersChaseable = false\n")
for fen in ["2k4/7/7/2r4/7/2P4/2K4 w - - 0 1",
            "3k3/7/7/7/7/2P4/3K3 w - - 0 1",
            "2k4/7/R6/2r4/7/2P4/2K4 w - - 0 1"]:
    print(fen, "->", sorted(sf.legal_moves(T, fen, [])))
# does the soldier defend a4/a5 in the real 029 position? enumerate white recaptures on a4
print("\n029: after a5a4 c4c5, can anything defend? white rook a4, black rook c5")
print(" black to move set at ply2:", sorted(sf.legal_moves(T,"2k4/7/R6/2r4/7/2P4/2K4 w - - 0 1",["a5a4","c4c5"])))
