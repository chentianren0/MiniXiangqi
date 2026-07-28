"""Deterministic adjudication/movegen walk over every variant, for A/B comparison.

Usage: python3 v-hash-diff.py <dir-containing-pyffish.so>
Prints a stable digest line per variant plus a global digest.
"""
import sys, os, hashlib, random

sys.path.insert(0, os.path.abspath(sys.argv[1]))
import pyffish as sf

PLIES = 60
GAMES = 3

out = []
for v in sorted(sf.variants()):
    try:
        start = sf.start_fen(v)
    except Exception as e:
        out.append("%s START-ERR %s" % (v, e))
        continue
    lines = []
    for g in range(GAMES):
        seed = int(hashlib.sha256(("%s|%d" % (v, g)).encode()).hexdigest()[:8], 16)
        rng = random.Random(seed)
        moves = []
        for ply in range(PLIES):
            try:
                legal = sf.legal_moves(v, start, moves)
            except Exception as e:
                lines.append("legal-err %s" % e)
                break
            try:
                res = sf.game_result(v, start, moves)
            except Exception as e:
                res = "gr-err:%s" % e
            try:
                opt = sf.is_optional_game_end(v, start, moves)
                opt = (opt[0], opt[1] if opt[0] else None)
            except Exception as e:
                opt = "oge-err:%s" % e
            try:
                imm = sf.is_immediate_game_end(v, start, moves)
                imm = (imm[0], imm[1] if imm[0] else None)
            except Exception as e:
                imm = "ige-err:%s" % e
            try:
                fen = sf.get_fen(v, start, moves)
            except Exception as e:
                fen = "fen-err:%s" % e
            lines.append("%d|%s|%s|%s|%s|%s" % (
                ply, ",".join(sorted(legal)), res, opt, imm, fen))
            if not legal:
                break
            moves.append(rng.choice(sorted(legal)))
    d = hashlib.sha256("\n".join(lines).encode()).hexdigest()[:32]
    out.append("%-28s %s" % (v, d))

text = "\n".join(out)
print(text)
print("GLOBAL %s" % hashlib.sha256(text.encode()).hexdigest())
print("variants %d" % len(out))
