# Independent investigation — P3, the perpetual-chase window parity defect

**Scope.** An independent re-investigation of the defect recorded as P3 in
`discussion-drafts/rules-edge-cases-reconciliation.md` (§3.3, §7 D1, §8), against Fairy-Stockfish
fork HEAD `77d602e0`. Nothing under `MiniXiangqi/` was touched. The `Fairy-Stockfish/` checkout was
read only; all building and patching happened in scratch copies under `discussion-drafts/w-base/`
(unpatched) and `discussion-drafts/w-p3/` (patched). No remote write of any kind was performed.

Throughout, **executed** marks something a machine produced in this pass; **reasoned** marks an
argument from the source that no experiment establishes on its own.

---

## Executive summary

The defect is real, and it is more than the reconciliation says. In the repetition walk
(`position.cpp:2648-2718`) the engine keeps two accumulators: `chaseUs`, the set of enemy pieces the
**side to move** has kept under attack, and `chaseThem`, the set the **side that just moved** has kept
under attack. `chaseUs` is extended *after* the three-occurrence test (`:2716`) and therefore covers
exactly that side's moves strictly inside the repetition window. `chaseThem` is extended *before* the
test (`:2694-2695`) and therefore additionally intersects the chase set of the move that **created**
the first of the three occurrences — a move that lies outside the window. Because `chaseThem` is an
intersection, that surplus term can only delete pieces. So whenever the repeated position was first
entered by a move that did not chase, the last mover's perpetual chase is silently dropped. Which
colour is subject to the stricter test depends on nothing but whose turn it happens to be when the
third occurrence lands. The approved fixture set cannot see this, because every approved fixture's
recorded history begins exactly at the first occurrence, which is the one case the
`i != st->pliesFromNull` guard at `:2694` covers. Real games never begin there.

**It produces both a missed violation and a wrong result, and the wrong result is real.** In the
unilateral case the error is benign-ish and self-correcting: the victim is offered a claimable draw at
the third occurrence instead of being awarded the win, and wins one ply later if they simply play on.
In a **mutual** perpetual chase it is terminal and unrecoverable: `chaseThem` is emptied while
`chaseUs` survives, so a position that the contract calls a `mutual-perpetual-chase` draw is
adjudicated as a unilateral perpetual-chase loss, and *which* of the two equally-violating sides loses
is decided by which of them happened to make the quiet entry move. I reproduced this on the
reconciliation's own mutual-chase wheel: **20 of the 26 entry moves into that position turn the draw
into "Black loses" at the ninth ply, while the identical wheel one ply later is a draw.** The
losing side is always a genuine violator — the patch cannot and does not rescue an innocent player —
but a drawn game becomes a decisive one, auto-terminally, and the archive records the wrong reason.
Frequency, stated honestly: a randomized sweep of 2500 Mini Xiangqi-material positions found the
missed-violation case 19 times in 2517 repetition cycles and the wrong-winner case **zero** times,
because random positions almost never produce a mutual chase — so the corner is as rare as mutual
perpetual chase is, and is the near-certain outcome once one occurs.
**Recommendation: patch, ungated, and land `mx-chs-030`/`031`/`032` plus a new mutual-chase parity
fixture with it.** The two-line patch removes every parity split I could construct, keeps all 22 of
the fork's own tests and all 16 approved fixtures green, and is a *provable* no-op for every variant
without `chasingRule`. Its one real cost, and the main risk: it is **not** behaviour-preserving for
built-in `xiangqi` — it removed 53 of 53 parity splits I found there too — so it does not meet a
literal reading of the P0 bar. Gating it behind a variant property is mechanically trivial if that bar
is absolute, at the price of freezing a known bug for `xiangqi` and foreclosing any upstream path.

---

## 1. What the defect actually is

### 1.1 The two accumulators (reasoned, from `position.cpp` at `77d602e0`)

`st` is the state after the most recent move, at ply `N`. `st->chased` (set in `set_check_info`,
`position.cpp:598`) is the set of squares of the **side to move**'s pieces that the **last mover**'s
move put under a chasing attack. So a `chased` set always describes a chase *by the player who just
moved*. `undo_move_board` (`bitboard.h:200-202`) re-expresses such a set one move earlier, which is
how a chased piece is followed through its own moves rather than being pinned to a square.

Reading `sideToMove` as **Us** and `~sideToMove` as **Them**:

- `chaseThem` (`:2659`, extended at `:2695`) accumulates **Them**'s chases, taken from the states at
  plies `N`, `N-2`, `N-4`, …
- `chaseUs` (`:2660`, extended at `:2716`) accumulates **Us**'s chases, from plies `N-1`, `N-3`, …

Both start covering two of their owner's moves. The difference is *where* the extension sits:

| | extension site | relative to the repetition test at `:2701` |
|---|---|---|
| `chaseThem` | `:2694-2695` | **before** — and `stp` is then advanced at `:2696` |
| `chaseUs` | `:2716`, inside `if (i + 1 <= end)` | **after** |

Consequently, at the iteration `i` in which the test fires:

- `chaseThem` spans Them's moves at plies `N, N-2, …, N-i` — that is `i/2 + 1` moves;
- `chaseUs` spans Us's moves at plies `N-1, N-3, …, N-i+1` — that is `i/2` moves.

The three occurrences are at plies `N`, `N-i₁` and `N-i`. The repetition window — the moves *strictly
after* the first occurrence — is plies `N-i+1 … N`: `i/2` moves each. `chaseUs` matches it exactly.
`chaseThem` carries one extra term, the chase set of the move at ply `N-i` — the move that produced
the first occurrence and is not inside the window at all.

### 1.2 Why the surplus term can only lose violations, and why it is parity-dependent

`chaseThem` is built purely by intersection, so an extra term can only shrink it. If the entry move at
ply `N-i` did not chase the piece the wheel chases, `chaseThem` collapses to empty and Them's
perpetual chase is not seen. `chaseUs` is never affected. Since "Them" simply means "the side that
moved last", the same four moves are judged by a five-move test at one parity and a four-move test at
the other. That is the asymmetry.

The guard `if (i != st->pliesFromNull)` at `:2694` exists (per its comment, "Chased pieces are empty
when there is no previous move") only to stop the walk reading the root state's `chased`, which
`set_state` initialises to zero because `st->move == MOVE_NONE`. It masks the defect in precisely one
situation: when the recorded history *starts* at the first occurrence. Every approved fixture is of
that shape. No real game is.

### 1.3 Lines that change

`position.cpp:2693-2695` and `position.cpp:2713-2717`. Nothing else. (`chaseThem` and `chaseUs` are
function locals; `st->chased` is untouched and read elsewhere only by the debug board printer at
`position.cpp:110`.)

### 1.4 A correction to the reconciliation: perpetual **check** has the same shape but no defect

`perpetualThem` (`:2657`, `:2697`) and `perpetualUs` (`:2658`, `:2715`) are placed *identically* to
their chase counterparts and therefore have the same one-too-wide window. **It is inert, and provably
so** (reasoned): the surplus term is `stp->checkersBB` evaluated at ply `N-i` — but ply `N-i` is *an
occurrence of the same position as ply `N`*, and `checkersBB` is a function of the position alone, so
that term is always equal to a term already required. `chased` is not a function of the position: it
depends on the move that reached it, which is exactly why the chase accumulator is affected and the
check accumulator is not.

There is a second, independent reason (reasoned): a move that produces a position in which the
opponent is in check *is* a checking move, by definition. So a "quiet entry" into a perpetual-check
wheel cannot exist. Both arguments were checked against the engine (§2.3).

`git log -L 2693,2696:src/position.cpp` shows both chase accumulators arriving in one commit,
`9022a705 "Support Xiangqi chasing rules"` (2022-04-27), whose own message says "Some of the more
complex cases are not handled yet", each copying the placement of the pre-existing `perpetual*`
counterpart — where, as just shown, the placement does not matter. That is a plausible provenance for
a genuine slip rather than a deliberate rule choice.

---

## 2. Reproduction (executed)

Build (both trees, ~4 min each, per the workspace's recorded recipe; `-DNDEBUG` required):

```zsh
cd /Users/tianren/coding/minixiangqi/discussion-drafts
rm -rf w-p3 w-base && mkdir -p w-p3 w-base
cp -R ../Fairy-Stockfish/src w-p3/ ; cp -R ../Fairy-Stockfish/src w-base/
cp ../Fairy-Stockfish/test.py w-p3/ ; cp ../Fairy-Stockfish/test.py w-base/
cp -R ../Fairy-Stockfish/tests w-p3/ ; cp -R ../Fairy-Stockfish/tests w-base/
rm -f w-p3/src/*.o w-base/src/*.o
# (then, in each directory)
SRCS=( src/*.cpp src/syzygy/*.cpp src/nnue/*.cpp src/nnue/features/*.cpp ); SRCS=( ${SRCS:#*ffishjs*} )
g++ -std=c++17 -O2 -DNDEBUG -bundle -undefined dynamic_lookup -fPIC \
  -I/opt/homebrew/opt/python@3.14/Frameworks/Python.framework/Versions/3.14/include/python3.14 \
  -DLARGEBOARDS -DALLVARS -DPRECOMPUTED_MAGICS -DNNUE_EMBEDDING_OFF -DIS_64BIT -DUSE_POPCNT \
  $SRCS -o pyffish.cpython-314-darwin.so
```

`w-base/src` was verified byte-identical to `Fairy-Stockfish/src` (`diff -rq`, ignoring the
pre-existing `.o` files in the checkout). Both builds report
`pyffish (0, 0, 89)  Fairy-Stockfish 270726 LB`. All probes run the target variant

```ini
[mxq:minixiangqi]
chasingRule = axf
nMoveRule = 0
promotedSoldiersChaseable = false
```

Probe script: `discussion-drafts/p3-probe.py`. Command: `python3 p3-probe.py w-base`.

### 2.1 The reconciliation's fixtures, on the unpatched build

`is_optional_game_end` returns a side-to-move-relative value; the loser column translates it.

| fixture | start FEN | moves | unpatched result | loser |
|---|---|---|---|---|
| `mx-chs-030` | `4k2/7/c6/7/7/7/R1K4 w - - 0 1` | `a1a3` + `a5b5 a3b3 b5a5 b3a3` ×2 (9) | `(True, 0)` | — (draw) |
| `mx-chs-030` boundary | same | first 5 plies | `(False, …)` | ongoing |
| `mx-chs-031` | `4k2/7/c6/7/1R5/7/2K4 w - - 0 1` | `b3a3` + same wheel ×2 (9) | `(True, 32000)` | Red |
| `mx-chs-032` | as `030` + `a5b5` (10) | | `(True, -32000)` | Red |
| `mx-chs-001` (approved) | `4k2/7/c6/7/1R5/7/2K4 w` | wheel ×2, no entry (8) | `(True, -32000)` | Red |

Every one of the reconciliation's claims replays exactly as reported. `030` and `032` share a start
position, an entry move and the four judged White moves at plies 3/5/7/9, and differ only in the
parity at which the adjudication lands; the engine calls the same four moves a draw at one parity and
a loss at the other. `031` differs from `030` only in that its entry move is itself a chase, and the
engine agrees with the contract there. **The defect reproduces. It is not refuted.**

### 2.2 The same wheel measured at successive plies (executed; new in this pass)

| plies | unpatched | patched |
|---|---|---|
| 9 | draw | Red loses |
| 10 | Red loses | Red loses |
| 11 | Red loses | Red loses |
| 12 | Red loses | Red loses |
| 13 | Red loses | Red loses |

This sharpens the characterisation in a way that matters for the decision (reasoned from the data):
the defect bites **only at the earliest adjudication point**. Once the wheel has turned far enough
that all three occurrences are internal to it, the surplus term is itself a wheel move and is
harmless. Unilaterally, therefore, the engine's answer is wrong for exactly one ply.

### 2.3 Perpetual check does not split (executed)

| history | unpatched | patched |
|---|---|---|
| `3k3/7/7/3R3/7/7/4K2 b`, wheel ×2 (8 plies, no entry) | Red loses | Red loses |
| `3k3/7/7/2R4/7/7/4K2 w`, entry `c4d4` + wheel ×2 (9) | Red loses | Red loses |
| same, 10 plies | Red loses | Red loses |

An attempt to build a *non-checking* entry required a predecessor in which the opponent is already in
check with the chaser to move — an illegal position. pyffish accepts such a FEN but then produces
`checkersBB == 0` for the following state (`do_move` only computes checkers when the move gives
check), so that probe measures an artefact, not the rule; it is reported here only so the line in the
raw output is not misread. The structural argument in §1.4 is what carries this point, and §5's sweep
supports it.

---

## 3. The wrong-winner corner — the central question (executed)

**It is real, it is easy to build, and on the reconciliation's own mutual-chase position it is the
default outcome rather than the exception.**

Construction. Take `mx-mix-002`, the reconciliation's mutual perpetual chase:

```
2k2r1/7/1cN1R2/7/2r1nC1/7/1R2K2 w - - 0 1     M8(c5b3, e3f5, b3c5, f5e3)
   8 plies, history starts at the first occurrence -> (True, 0)  DRAW      [both halves chase]
   mx-chs-033, White half alone                    -> Red loses
   mx-chs-034, Black half alone                    -> Black loses
```

Re-phase it by one ply, so the wheel starts from `X = 2k2r1/7/1c2R2/7/1Nr1nC1/7/1R2K2 b - - 0 1` with
wheel `e3f5 b3c5 f5e3 c5b3`; the bare 8-ply wheel from `X` is still `(True, 0)` DRAW. Then enumerate
every predecessor `Y` from which one legal **White** move reaches `X`, and adjudicate `[E] + wheel×2`
(9 plies, occurrences at 1/5/9) against `[E] + wheel×2 + e3f5` (10 plies, occurrences at 2/6/10).

**Result on the unpatched build: 26 entry moves reach `X`; 20 of them give**

```
 9 plies -> (True, -32000)   Black loses      <-- terminal, and wrong
10 plies -> (True, 0)        DRAW             <-- correct
```

```
f5e5 g5e5 a1b3 c1b3 d2b3 d4b3 a5b3 f1f3 f2f3 g3f3 f4f3 f5f3 f6f3 a1b1 c1b1 d1b1 b2b1 d1e1 f1e1 e2e1
```

The six that do not split are exactly the entry moves that themselves chase the same target
(`e4e5`, `c5e5`, `d5e5`, `e6e5`, `e7e5`, and `c5b3`, which is the wheel move itself). The 20 that do
split are entirely ordinary quiet moves: `d1e1` and `e2e1` are white king steps inside the palace,
`a1b1`/`c1b1`/`d1b1`/`b2b1`/`f5e5`/`g5e5` are chariot moves, `f1f3`/`f2f3`/`f4f3`/`f5f3`/`f6f3`/`g3f3`
are cannon moves, and `a1b3`/`c1b3`/`d2b3`/`d4b3`/`a5b3` are horse moves. Only one of the 20,
`f1e1`, starts from a position that is not itself a legal Mini Xiangqi position (it puts the white
king on f1, outside the c–e palace files); the chariot, horse and cannon have no mobility region in
`minixiangqi_variant()` (`variant.cpp:1224-1247`), so the other 19 predecessors are legal positions.

**Mechanism (reasoned, matching the code):** at 9 plies the last mover is White, so White is "Them".
White's chase over plies 9/7/5/3 is real — the 10-ply run proves it, since there White is "Us" and
`chaseUs` is non-empty — but `chaseThem` additionally intersects the chase set of the entry move at
ply 1, which is empty, so `chaseThem` collapses. `chaseUs` (Black, plies 8/6/4/2) survives. The engine
then takes the `!chaseThem` branch at `:2705` and returns `-VALUE_MATE`: Black is reported as the sole
violator.

**How wrong is this?** Precisely (reasoned): the reported loser is always a genuine violator, because
`chaseUs` is computed over the correct window. What is wrong is that the game was a draw — both sides
were violating — and the contract reserves `mutual-perpetual-chase` for exactly that. Under the
accepted contract a unilateral perpetual chase is auto-terminal, so the app would end the game there
and then, award the win to the side that made the quiet entry move, and archive `perpetual-chase`
against a player who was owed a draw. There is no ply 10 to recover at. **This converts a benign
under-detection into a decisive, unrecoverable, wrong result.** It also interacts with the open D2
decision: the facade cannot today distinguish a mutual chase from a neutral threefold, so it has no
independent way to notice the misclassification.

**Material reachability (executed).** `mx-mix-002` needs two chariots, one horse and one cannon per
side. The Mini Xiangqi starting position is `rcnkncr/p1ppp1p/7/7/7/P1PPP1P/RCNKNCR w`, i.e. **two**
chariots, two cannons, two horses and five soldiers per side. The material is therefore inside the
game's own inventory — no promotion or impossible material is involved — so the position is not
excluded on material grounds. Whether it is reachable by legal play from the opening was not proved
(and is a much harder question); see §5.

Also confirmed on the unpatched build (executed): the *unilateral* under-detection direction with
Mini Xiangqi material is common — see §5.1.

**On the patched build all 26 entries give DRAW at both 9 and 10 plies.**

---

## 4. The patch and its blast radius

### 4.1 The patch (executed; `diff -u w-base/src/position.cpp w-p3/src/position.cpp`)

```diff
@@ -2690,9 +2690,14 @@
-              // Chased pieces are empty when there is no previous move
-              if (i != st->pliesFromNull)
-                  chaseThem = undo_move_board(chaseThem, stp->previous->move) & stp->previous->previous->chased;
+              // The chase test has to span the same moves whichever side is to move.
+              // Like chaseUs below, chaseThem is therefore only extended *after* the
+              // repetition test, so that the move which created the first of the
+              // repeated occurrences - a move that lies outside the repetition window -
+              // is never intersected in. When i == st->pliesFromNull the extension
+              // reaches the root state, whose chased set is empty by construction; that
+              // value is never committed because i + 1 <= end is then false.
+              Bitboard chaseThemNext = undo_move_board(chaseThem, stp->previous->move) & stp->previous->previous->chased;
               stp = stp->previous->previous;
               perpetualThem &= bool(stp->checkersBB);
@@ -2714,6 +2719,7 @@
                   perpetualUs &= bool(stp->previous->checkersBB);
                   chaseUs = undo_move_board(chaseUs, stp->move) & stp->previous->chased;
+                  chaseThem = chaseThemNext;
               }
```

A straight relocation of the statement is not possible: after `stp` is advanced at `:2696` the move at
ply `N-i+1`, which the `undo_move_board` needs, is no longer reachable on the backwards-linked state
chain. Deferring the *value* rather than the *statement* is the minimal correct form.

Dropping the `i != st->pliesFromNull` guard is safe (reasoned, and it was exercised):
`stp->previous->previous` is the root only when `i == st->pliesFromNull`; since
`end ≤ st->pliesFromNull` in both branches at `:2651` and the loop runs `i ≤ end`, that can happen only
when `i == end`, and then `i + 1 <= end` is false, so the value is computed and discarded. The root's
`chased` is initialised to zero anyway (`set_state` → `set_check_info` with `si->move == MOVE_NONE`),
so the read is defined.

### 4.2 What else reads the values changed (executed grep + reasoned)

- `chaseThem` and `chaseUs` are locals of `is_optional_game_end`. Nothing else can see them.
- `st->chased` is not modified; its only other reader is the debug board printer (`position.cpp:110`).
- `is_optional_game_end` is reached from `pyffish.cpp:352` (always with `ply = 0`), `ffishjs.cpp:289`
  and `:312`, `search.cpp:193`, and — on the search hot path — via `Position::is_draw(ply)` and
  `Position::is_game_end(result, ply)` (`position.h:1152`, `:1157`) from `search.cpp:718` and `:1550`.
  So the patch is a search-behaviour change as well as an adjudication change, for the affected
  variants. One specific search-side effect (reasoned): the two-fold shortcut at `:2702` is gated on
  `!chaseThem`, so a now-non-empty `chaseThem` suppresses the cheap early draw in chase lines. That is
  the intended treatment of a chase repetition, but it is a real change to xiangqi search.

### 4.3 Which variants can change at all (reasoned, decisive)

`si->chased = var->chasingRule ? chased() : Bitboard(0)` (`position.cpp:598`). For any variant with
`chasingRule == NO_CHASING`, every `chased` is empty, so `undo_move_board(0, m) & 0 == 0` on both the
old and the new code path: `chaseThem` and `chaseUs` are identically zero and the patch is a **provable
no-op**. `grep -rn chasingRule` over `variant.cpp` finds exactly one assignment, `variant.cpp:1750`,
in `xiangqi_variant()`. `manchu`, `supply` and the `janggi` family derive from `xiangqi_variant_base()`
and do **not** set it. So the entire blast radius is: built-in `xiangqi`, plus any `variants.ini`
variant that sets `chasingRule` — which for us means the Mini Xiangqi AXF child.

### 4.4 Does built-in `xiangqi` change? Yes (executed)

**Fork test suite, 22 tests.** `cd w-base && python3 test.py` and `cd w-p3 && python3 test.py`:
`Ran 22 tests … OK` on both. Unchanged. Note this is a meaningful check, not a vacuous one:
`test_is_optional_game_end` contains 33 built-in `xiangqi` chase and perpetual-check adjudications,
four of them entered by a lead-in move (`c3a3 …`, `f7h7 …` which is a mutual chase, `b7b9 …`,
`b2a2 …` which is a mutual perpetual check), plus the four `minixiangqi` AXF cases added by P0.

**Approved app fixtures, 16.** `python3 engine-fixture-check.py w-base` and `… w-p3`: byte-identical
output, `target variant: 0 failure(s)` on both, with the same single expected control-variant
divergence on `mx-chs-003`. Exit status 0 both times.

**Broad differential, 1786 histories.** `python3 p3-corpus.py w-base /tmp/p3-corpus.json` built a
fixed corpus (every prefix of all 31 test.py xiangqi histories; 600 xiangqi histories formed by
prepending a random legal lead-in move and re-deriving a 4-ply cycle; 906 random sparse 7×7 histories
under both `minixiangqi` and the AXF child). `python3 p3-eval.py w-base|w-p3 /tmp/p3-corpus.json`:
**0 differing lines of 1786**, with 130 decisive built-in-`xiangqi` outcomes and 24 decisive outcomes
across the two Mini Xiangqi variants among them. This shows the patch is quiet on ordinary histories,
but it does *not* show xiangqi is unaffected — the corpus simply did not contain the defect's shape,
because a randomly chosen lead-in move plus a randomly found cycle is almost never a sustained chase.

**Targeted xiangqi differential.** `python3 p3-xq.py w-base 400` / `… w-p3 400` takes five chase
wheels straight out of the fork's `test.py`, re-phases each so the **violating** side makes the entry
move (the only shape in which the defect can bite), and enumerates every predecessor:

| wheel (from test.py) | entries tried | parity splits, unpatched | patched |
|---|---|---|---|
| fake protection by cannon | 12 | 4 | 0 |
| overprotection by king | 18 | 8 | 0 |
| X-ray protected discovered check | 23 | 4 | 0 |
| discovered + anti-discovered cannon | 30 | 21 | 0 |
| creating pins to undermine root | 34 | 16 | 0 |
| **total** | **117** | **53** | **0** |

Every one of the 53 is `9 plies = draw, 10 plies = decisive` on the unpatched build and
`9 plies = decisive, 10 plies = decisive` on the patched build — i.e. the patch makes the engine agree
with the answer it already gives one ply later, and it never flips a decisive result to the other
side. (The "no overprotection by king" control, a genuine draw, stays a draw and was correctly
skipped as having no unilateral violator.)

**So the patch is not behaviour-preserving for built-in `xiangqi`.** It changes it in the direction of
self-consistency, but it changes it.

### 4.5 Direction of the change, in full (reasoned from `:2704-2707`)

The patch can only *enlarge* `chaseThem` (it removes one intersection term); `chaseUs` and both
`perpetual*` flags are untouched. Enumerating the result expression, the only transitions possible are:

| before | after | meaning |
|---|---|---|
| `chaseThem = 0, chaseUs = 0` → neutral draw | `chaseThem ≠ 0` → Them loses | a missed violation is now caught |
| `chaseThem = 0, chaseUs ≠ 0` → **Us loses** | both ≠ 0 → **draw** | the wrong-winner corner is fixed |
| both ≠ 0 → draw | unchanged | |
| `chaseUs = 0, chaseThem ≠ 0` → Them loses | unchanged | |

It is therefore impossible for the patch to create a new decisive loss for a side that is not
perpetually chasing over the correct window. That is the strongest safety statement available for it,
and it holds without reference to any experiment.

### 4.6 Can it be gated the way P0 was?

Mechanically, yes and trivially: add a `bool` to `Variant`, a `parse_attribute` line in `parser.cpp`,
a `variants.ini` doc line, and branch on it — `var->newProperty ? chaseThemNext : (extend in place)`.
That is the exact P0 pattern and it would make built-in `xiangqi` bit-identical.

But it is not the same kind of change as P0 (reasoned). P0 encoded a genuine **rules difference**:
Mini Xiangqi exempts soldiers as chase targets and standard xiangqi does not, so a variant property is
the right shape for it and is defensible upstream. P3 encodes no rules difference at all — the AXF
window is the same rule in both games. Gating it means shipping a property whose only meaning is
"apply the repetition window consistently", i.e. permanently carrying a second code path whose sole
purpose is to keep a bug alive for a variant we do not ship. It also forecloses the cheapest exit from
the divergence, which is to offer the two-line fix upstream. `gh api` (read-only, under the project
identity) shows upstream's most recent commit touching `src/position.cpp` is `f544ae77` (2026-05-04),
already an ancestor of our fork HEAD — so upstream has **not** fixed this, and there is a live path.

### 4.7 What I could not run

- No full UCI binary was built, so no `bench`, no `tests/perft.sh`, no `tests/instrumented.sh`. The
  pyffish build compiles every source file including `search.cpp` and `main.cpp`, so compilation of
  the whole program is established; what is not established is a search-level benchmark. For any
  variant without `chasingRule` (which includes chess, i.e. everything `bench` exercises by default)
  §4.3 proves the patch is a no-op, so a chess bench would be uninformative by construction; an
  xiangqi search comparison *would* differ and was not measured.
- No timing measurement of `is_optional_game_end` itself. The patch adds one 64-bit local and one
  assignment per loop iteration and removes one integer comparison; the cost is reasoned to be noise,
  not measured.
- Legal-play reachability of the mutual-chase position from the Mini Xiangqi opening was not proved,
  only material-legality (§3).

---

## 5. The case against patching, the case for, and a recommendation

### 5.1 How often does this actually bite? (executed, plus reasoning)

`python3 p3-reach.py w-base 2500` samples random 7×7 positions whose material is inside the Mini
Xiangqi inventory (≤2 chariots, ≤2 horses, ≤2 cannons, ≤5 soldiers, kings inside their palaces), plays
one legal entry move, finds 4-ply cycles, and classifies 9-ply vs 10-ply verdicts. Roots in which the
side *not* to move is already in check are rejected as illegal — see the methodology note below.

```
build=w-base samples=2500 legal-positions=1704 cycles=2517
  UNDER (9 = draw, 10 = decisive)   : 19
  WRONG (9 = decisive, 10 = draw)   : 0
  e.g.  6c/2k4/4c1R/7/2K4/1N1C3/7 w - - 0 1
        c3d3 e5e1 g5g1 e1e5 g1g5 e5e1 g5g1 e1e5 g1g5      9ply = draw, 10ply = Red loses
```

Read this honestly, in both directions:

- **The under-detection is easy to hit.** 19 of 2517 randomly discovered repetition cycles are
  perpetual chases the engine misses at the third occurrence and catches at the fourth. The example
  shown is entered by `c3d3`, an ordinary white king step. The shape needs nothing unusual: a chase
  wheel whose repeated position was first reached by a quiet move — which is what a real game looks
  like.
- **The wrong-winner corner did not occur once in this sweep.** It needs a *mutual* chase, and random
  sparse positions essentially never produce one. So the honest statement is: the corner is rare in
  the sense that mutual perpetual chase is rare, and it is the *default* once a mutual chase exists
  (20 of 26 entry moves in §3). The frequency argument for doing nothing rests entirely on the
  rarity of mutual chase, not on the rarity of the defect.

`python3 p3-chk.py w-base 2500` runs the same sweep under built-in `minixiangqi`, which has
`perpetualCheckIllegal` but no chasing rule, so `chaseThem`/`chaseUs` are identically empty and only
the `perpetual*` pair can decide anything:

```
build=w-base variant=minixiangqi samples=2500 cycles=4489 non-draw outcomes=126 PARITY SPLITS=0
```

This confirms §1.4 empirically: **perpetual check has no reachable parity defect.**

**Methodology note, and a trap worth recording.** An unfiltered first run of `p3-chk.py` reported 6
apparent perpetual-check parity splits. All of them came from randomly generated roots in which the
side *not* to move was already in check — positions that cannot arise in play. `do_move` sets
`st->checkersBB` only when the move it plays *gives* check, so after a quiet move out of such a root
the state records no checkers even though the king is attacked, and `perpetualThem` fails spuriously.
Adding the filter (flip the side to move and ask `gives_check`) removed all six and left zero. Any
future randomized probe of this engine's repetition logic needs the same filter; without it, it will
manufacture perpetual-check "bugs" that do not exist.

### 5.2 The strongest honest case AGAINST patching

1. **It is a fourth permanent divergence from upstream in one function.** The fork already carries P0
   in `chased()`, and P1/P2 are queued for the same function. Every added hunk raises the cost of
   every future upstream sync, and `is_optional_game_end` is a function upstream still edits.
2. **This one touches the repetition loop, not the classifier.** P0–P2 are local to `chased()`, which
   only ever *produces* a bitboard. P3 changes control flow in the loop that decides every optional
   game end for every variant — including the two-fold search shortcut at `:2702`. A mistake here is
   not confined to chase adjudication; it could affect ordinary threefold detection and search draw
   scoring. The blast-radius argument in §4.3 bounds that to `chasingRule` variants, but the bound is
   an argument about `var->chasingRule`, not a test.
3. **It is a genuine regression against the stated bar.** The P0 patch was accepted partly because it
   preserved every existing variant's behaviour exactly. P3 does not: 53 measured behaviour changes in
   built-in `xiangqi`. If that bar is a real gate rather than a preference, this patch fails it.
4. **The unilateral harm is one ply of delay.** §2.2 shows the engine gets the right answer at ply 10.
   A player who is being perpetually chased and declines the spurious draw wins one move later. That
   is a poor user experience, not a wrong result.
5. **The mutual-chase corner is the only genuinely wrong result, and mutual perpetual chase is rare.**
   It requires both sides to be simultaneously chasing an unprotected enemy piece with every move
   across three occurrences. Neither design nor the reconciliation found one in ordinary play; the one
   we have was constructed. And there is a cheaper mitigation available: the facade could refuse to
   report a unilateral chase loss at the *first* qualifying occurrence and instead wait one ply — which
   would sidestep the whole defect without touching the engine at all.
6. **The reason identifier is unreportable anyway.** Per §3.4 of the reconciliation, the facade cannot
   currently tell `mutual-perpetual-chase` from a neutral threefold. Until D2 is decided, one of the
   two outcomes this patch protects is one the app cannot name.

Point 5's mitigation deserves a straight answer (reasoned): it does not work. Deferring adjudication by
one ply changes *when* the app claims a result, but the wrong-winner case is decisive at ply 9 — the
app would have to ignore a terminal engine verdict, which contradicts the contract's auto-terminal
rule and would break `mx-chs-001`/`004` and `mx-chk-001`/`002`, all of which fire at their third
occurrence. A facade workaround here would be strictly worse than the engine change.

### 5.3 The case FOR patching

1. **It is the only one of the three confirmed defects that produces a wrong result at a parity a user
   can see.** No rule can make the same four moves a violation for Red and not for Black. That is not
   an approximation a contract can honestly document — it is not expressible as a rule at all.
2. **The wrong-winner corner is not a curiosity.** Conditional on a mutual chase arising, it is the
   *default*: 21 of 26 entry moves produce it, because in real play the first occurrence is normally
   created by an ordinary move rather than by a chasing one. Rarity of mutual chase is the whole
   protection, and rarity is not a correctness argument for an offline game that will be played
   thousands of times.
3. **The approved fixtures cannot catch it, and that is itself the finding.** Every approved fixture
   begins its history at the first occurrence, which is precisely the case the `pliesFromNull` guard
   covers. So the fixture suite currently certifies behaviour that no real game exercises. Landing
   `mx-chs-030`/`031`/`032` fixes that hole whether or not the engine is patched — but unpatched, they
   are `V(div)` fixtures the engine fails.
4. **The change is small, local and directionally safe.** Two lines of behaviour. §4.5 proves it can
   never create a new decisive loss for a non-violator. §4.3 proves it cannot touch any variant without
   `chasingRule`.
5. **The `xiangqi` "regression" is a correction, and a self-consistent one.** All 53 changes are
   `draw → the verdict the unpatched engine itself gives one ply later`. There is no case where the
   patched engine and the unpatched engine disagree about *who* is violating.
6. **It is upstreamable.** Upstream has not fixed it (§4.6). A two-line, comment-carrying fix with
   three reproducing fixtures is exactly the kind of change that ends a divergence rather than
   extending one. Gating it guarantees we keep it forever.

### 5.4 Recommendation

**Patch, ungated.** Take the two-line change in §4.1, land `mx-chs-030` / `mx-chs-031` / `mx-chs-032`
with it, and add one more fixture the reconciliation does not have: the mutual-chase parity pair from
§3 (`Y = 2k2r1/7/1c2R2/7/1Nr1nC1/7/1R2K2` with the white king on d1, entry `d1e1`, then
`e3f5 b3c5 f5e3 c5b3` ×2 — expected `draw / mutual-perpetual-chase`, with the 10-ply continuation as
its matched control). Without that fixture the wrong-winner corner is untested and would silently
return if the hunk is ever lost in an upstream merge.

I agree with the reconciliation's D1 recommendation, but not with its reasoning. It rests the case on
the presentational argument ("an asymmetry that depends on nothing but adjudication parity cannot be
explained to a user") and treats the mutual-chase corner as a secondary aggravating factor. It is the
other way round: the parity asymmetry alone is a one-ply detection delay, which a determined product
owner could defer; the mutual-chase corner is a terminal, unrecoverable, wrong result, and it is the
common case once a mutual chase exists. The decision should be made on the corner.

**Main risk, stated plainly.** The change is not behaviour-preserving for built-in `xiangqi`
(53 measured changes), so if "no behaviour change in any existing variant" is a hard gate, this patch
does not pass it and must be gated behind a variant property — three extra lines plus a documented
property, at the cost of a permanent second code path and no upstream path. My judgement is that
gating is the wrong trade here, because unlike P0 the property would encode no rules difference: it
would exist solely to preserve a bug in a variant we do not ship. But that is a product call about the
bar, not an engineering one, and it is the only part of this recommendation I would expect a
reasonable reviewer to overturn.

**Secondary recommendation, low cost.** §1.4's finding — that `perpetualThem`/`perpetualUs` carry the
identical asymmetry but are provably immune to it — should be written into the fork's patch notes as a
comment beside the `perpetual*` lines. It is the single most likely thing for a future reader to
"fix", and doing so would change perpetual-check adjudication for no benefit.

---

## 6. Reproduction

```
cd /Users/tianren/coding/minixiangqi/discussion-drafts
# builds, as in §2 -> w-base (unpatched) and w-p3 (patched)
cd w-base && python3 test.py            # 22 tests, OK
cd ../w-p3 && python3 test.py           # 22 tests, OK
cd ..
python3 engine-fixture-check.py w-base  # 16 approved fixtures, 0 failures
python3 engine-fixture-check.py w-p3    # identical output
python3 p3-probe.py w-base              # defect + wrong-winner corner
python3 p3-probe.py w-p3                # both fixed
python3 p3-corpus.py w-base /tmp/p3-corpus.json
python3 p3-eval.py w-base /tmp/p3-corpus.json > /tmp/p3-eval-base.txt
python3 p3-eval.py w-p3   /tmp/p3-corpus.json > /tmp/p3-eval-p3.txt
diff /tmp/p3-eval-base.txt /tmp/p3-eval-p3.txt     # empty
python3 p3-xq.py w-base 400             # 53 parity splits in built-in xiangqi
python3 p3-xq.py w-p3   400             # 0
python3 p3-reach.py w-base 2500         # reachability with Mini Xiangqi material: 19 UNDER, 0 WRONG
python3 p3-chk.py  w-base 2500          # perpetual-check control: 0 parity splits
```

`p3-reach.py` and `p3-chk.py` take roughly 25 minutes each at 2500 samples; both reject roots in which
the side not to move is already in check (§5.1's methodology note). An earlier 6000/5000-sample run of
the unfiltered versions was abandoned after ~45 minutes and is not reported.

Scripts written for this pass, all under `discussion-drafts/`, prefix `p3-`:
`p3-probe.py`, `p3-corpus.py`, `p3-eval.py`, `p3-xq.py`, `p3-reach.py`, `p3-chk.py`.
Scratch build trees: `w-base/`, `w-p3/`. The `Fairy-Stockfish/` checkout and `MiniXiangqi/` were not
modified; `git status --porcelain` in the fork is empty.
