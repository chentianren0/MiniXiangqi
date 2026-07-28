V, N = "minixiangqiaxf", "minixiangqiaxfnochk"
# sanity: unilateral perpetual check must vanish under the no-check child
chk = ("3k3/7/7/3R3/7/7/4K2 b - - 0 1", ['d7c7','d4c4','c7d7','c4d4']*2)
print("chk-001 axf   :", pyffish.is_optional_game_end(V, chk[0], chk[1]))
print("chk-001 nochk :", pyffish.is_optional_game_end(N, chk[0], chk[1]))
mut = ("2k2r1/7/1cN1R2/7/2r1nC1/7/1R2K2 w - - 0 1", ['c5b3','e3f5','b3c5','f5e3']*2)
print("mutual chase axf:", pyffish.is_optional_game_end(V, mut[0], mut[1]))
