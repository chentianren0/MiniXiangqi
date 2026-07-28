import sys
sys.path.insert(0, "/Users/tianren/coding/minixiangqi/discussion-drafts/w-base")
import pyffish as sf
T = "mxq_target"
sf.load_variant_config("[mxq_target:minixiangqi]\nchasingRule = axf\nnMoveRule = 0\npromotedSoldiersChaseable = false\n")
def g(tag, fen, mv):
    ok = all(mv[i] in sf.legal_moves(T, fen, mv[:i]) for i in range(len(mv)))
    print(f"  {tag:52s} legal={ok}  {sf.is_optional_game_end(T, fen, mv)}  stm={sf.get_fen(T,fen,mv).split()[1]}")

M28 = ["d4d3","b3b4","d3d4","b4b3"]*2
print("028 controls (pinned-attacker):")
g("028 as filed (rook pinned by d7)", "3rk2/7/7/3R3/1c5/7/3K3 w - - 0 1", M28)
g("control: black rook d7 -> e7 area, pin removed", "4k2/7/7/3R3/1c5/7/3K3 w - - 0 1", M28)
g("control: white king d1 -> c1, pin removed", "3rk2/7/7/3R3/1c5/7/2K4 w - - 0 1", M28)

M29 = ["a5a4","c4c5","a4a5","c5c4"]*2
print("\n029 controls (flying-general false pin):")
g("029 as filed (kings both on c-file, soldier c2)", "2k4/7/R6/2r4/7/2P4/2K4 w - - 0 1", M29)
g("control: white king d1, kings off a shared file", "2k4/7/R6/2r4/7/2P4/3K3 w - - 0 1", M29)
g("control: no white soldier (true flying-gen pin)", "2k4/7/R6/2r4/7/7/2K4 w - - 0 1", M29)
