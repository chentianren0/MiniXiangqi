# Review — PR #28 `design/play-controls`

One pass. Line numbers are on the branch.

## Findings

**1. `testing.md:61` — "with no fourth control in any state" is false as written.**
Replay's accepted transport is already five controls (`interaction-design.md:376` — jump to beginning, one back, play/pause, one forward, jump to end), plus session speeds (`:381`), plus 翻转棋盘. The gate fails on the first replay screen a tester opens. The clause also collides with `testing.md:65` and `interaction-design.md:513`: the stacked layout must reach the move list on demand, and how that disclosure is presented is still an open question (`:533`). Scope the clause to the play-control cluster during play, not "any state".

**2. `interaction-design.md:272` settles an explicitly open question, and this was not on the owner's decision list.**
`:290` still reads "The placement of the persistent **可判和** affordance remains open below and is not settled by this", and the Need-to-discuss item at `:535` still calls it "the retained draw-claim affordance". Line 272 settles exactly that placement. The document now says both "open" and "settled" about the same thing, in accepted-status prose (`:7`). Related: `:370` — accepted and unamended — says the claim "is exposed through a non-blocking **可判和** affordance", while the new gate `testing.md:62` requires "no separate 可判和 element appearing". Either amend `:290`, `:370`, and `:535` in this PR, or drop the claim-state paragraph.

**3. "becomes enabled and marked" (`:272`, `testing.md:62`) is not executable.**
The mark is never defined. Every other marker in this document carries exact geometry and ink. A tester cannot verify "marked".

**4. `确认认输？` breaks the accepted confirmation-title pattern.**
Both accepted titles name the action or object plainly — **删除这盘棋？**, **开始新对局？** — and neither prefixes 确认. This would be the only 确认-prefixed title in the contract. The message **认输后本局将记为你落败。** is fine: it follows the shape of **删除后无法恢复。** and states the material consequence. (Minor: 本局 is a fourth spelling for "this game" beside 这盘对局, 当前对局, 这盘棋.)

**5. `:502` — "a disc approaches 80 points" is arithmetically wrong.**
At the 720 pt cap the pitch is 102.86 pt, and the accepted disc is Ø `0.80 p` (`:135`) = **82.3 pt**. It passes 80, it does not approach it. The pitch figure ("about 103 points") is correct.

**6. `:269` — "it is the mode the accepted orientation behaviour gives a flip control".**
Replay gets one too (`:215`, `:378`), as the very next bullet says.

## Checked and correct

Free Play cannot resign (`product.md:40`); confirming records a human loss and immutable History (`game-data.md:107`, `:51` — outcome is the win for the side opposite `human_side`); resignation not folded into the result card (`:360`); HvAI human side at bottom with no flip control, Free Play flip control, replay flip control (`:213`–`:215`, `:378`); 悔棋 and 判和 in both play modes (`product.md:39`, `:56`); 720 pt → pitch ≈ 103 pt; the board-cap gate is executable; the resign gate's "absent in Free Play and replay" matches `product.md:40`.

## Verdict

**DO NOT MERGE.** Findings 1 and 2 are contract-level and both are cheap to fix.
