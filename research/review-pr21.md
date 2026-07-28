# Pre-merge review — PR #21 `design/engine-packaging`

Independent adversarial review standing in for human review. Read-only: nothing in `MiniXiangqi/`,
`wt-engine/` or `Fairy-Stockfish/` was modified, and nothing was written to GitHub.

Sources read: the full diff (`git diff main...design/engine-packaging`), the PR body, the resulting
`docs/engine-integration.md` and `docs/testing.md`, and the accepted contracts `architecture.md`,
`core-interface.md`, `interaction-design.md`, `game-data.md`, `xiangqi-rules.md`, `product.md`.
Engine claims were verified directly against `/Users/tianren/coding/minixiangqi/Fairy-Stockfish`
at `77d602e0`, and the fork change set against
`discussion-drafts/rules-edge-cases-reconciliation.md` §3, §7, §8.

**Verdict: DO NOT MERGE.** Seven blocking findings. The most serious is §3.1: the variant-packaging
section states the inverse of what the engine does, and shipping it as written produces an AI silently
running on classical evaluation — the exact outcome the same PR's "no fallback" section forbids.

---

## 1. The backgrounding decision's consequences

### 1.1 The stated safety mechanism is the wrong one — **blocking**

> "A result that arrives from a search cancelled this way is rejected by the existing revision check
> rather than trusted."

and the matching gate in `testing.md`:

> "…and that a result from the cancelled search is rejected by the revision check rather than applied."

Backgrounding cancels a search but performs **no accepted mutation**, so `position_revision` is
unchanged. The late result's `(game_id, position_revision)` therefore still **matches** and the
revision check does **not** reject it. `core-interface.md` says this explicitly and says why the
usual argument does not apply here:

> "Because every accepted mutation bumps the revision, an un-cancelled in-flight search is neutralized
> by staleness; cancellation is a promptness optimization, not a correctness requirement."

Backgrounding is the one accepted cancellation trigger in the whole contract that is *not*
accompanied by a mutation (`architecture.md` lists Undo, game completion, active-game replacement,
leaving the relevant state, and backgrounding — the first four all mutate). So for this case
cancellation *is* the correctness requirement, and the contract asserts the opposite. Worse, on
foreground return the app requests a **new** search from the same unchanged position: an implementer
who trusts the quoted sentence gets two live tickets whose revisions both match, and the stale-result
ladder never fires.

The `testing.md` gate as written is therefore also unimplementable — a test that backgrounds, injects
a late result and asserts "rejected by the revision check" will either fail or pass vacuously.

**Correction.** Replace the bullet with: "A result that arrives from a search cancelled this way is
rejected by the cancellation rung of the delivery ladder in [core-interface.md](core-interface.md).
The revision check does not cover this case, because backgrounding cancels without any accepted
mutation and therefore does not bump `position_revision`; the re-requested search on return carries a
new ticket and the prior ticket's result is never delivered as `MXQ_SEARCH_MOVE`." Rewrite the
`testing.md` gate to match, and add a gate that a late result from a pre-background ticket is
rejected **while the position revision is identical**.

### 1.2 Re-preparation failure lands the user in a state the interaction contract does not define — **blocking**

> "Re-preparation can fail, most plausibly because memory conditions changed while the app was away.
> It uses the same insufficient-memory path as any other preparation, and the game remains saved and
> resumable with the AI unavailable."

`interaction-design.md`'s accepted notice is scoped to a game that has not started:

> "Before an AI engine is initialized, the app calculates the accepted Hash budget. A budget below 256
> MiB does not start the AI opponent."
> Title: **无法启动 AI 对手** … Actions: **取消** and **重试**.
> "**取消** dismisses the notice without creating or changing an active game. In pre-start setup, the
> in-memory draft remains while the user stays on that page."
> "Any active game being resumed remains saved and unchanged while the AI opponent is unavailable."

On foreground return the user is **inside** an active game, not resuming one and not in pre-start.
Three things break:

- The copy is wrong. 无法启动 AI 对手 ("cannot start the AI opponent") names an event that already
  happened successfully; the AI has been playing.
- **取消** has no defined consequence here. Its accepted semantics ("without creating or changing an
  active game"; "the draft remains") are vacuous mid-game. The user dismisses the notice and is
  returned to a board where it is the AI's turn.
- There is no such board state. `interaction-design.md`'s turn status defines exactly two
  human-versus-AI states — the human's turn, and the AI's turn with "AI thinking … shown as activity
  attached to the AI's turn" — and "Board input is accepted only when the committed game state permits
  the user to move. It is disabled while the AI is thinking." An AI-to-move game whose AI is
  unavailable shows a thinking indicator for a search that will never run, accepts no input, and
  offers no exit. Its own Need-to-discuss list confirms the gap: "Define empty, loading, AI-thinking,
  error, corrupted-import, and destructive-action states."

The `testing.md` gate inherits the error — "leaving the game saved and **resumable** with the AI
unavailable" describes a game the user is not currently in, which is not the scenario.

**Correction.** This PR cannot accept the backgrounding behaviour without a matching
`interaction-design.md` change in the same PR (repository change discipline: "Update an accepted
contract and its tests in the same change that alters the corresponding behavior"). Either (a) add an
accepted mid-game AI-unavailable presentation — distinct title, a defined turn-status state, and a
defined **取消** outcome — or (b) narrow the backgrounding rule so that re-preparation is deferred
until the user is at a surface where the accepted notice already applies, and state that the board
shows the position with no thinking indicator until then. Until one of those exists, drop "It uses the
same insufficient-memory path as any other preparation" and record the question in **Need to discuss**.

### 1.3 Re-preparation is unconditional, so the notice is reachable where no AI is wanted at all — **blocking**

> "Returning to the foreground obtains a fresh memory probe, re-prepares the engine, and requests a
> new search from the committed position if one is owed."

Only the *search* is conditional. Preparation is not. The notice is therefore reachable on foreground
return in every one of these states, none of which needs an engine:

- **Replay.** `interaction-design.md`: "the app moving to the background pauses playback." Returning
  now also re-prepares an engine and may throw a modal memory notice over a read-only document.
- **Unconfirmed natural result.** The result card is "non-dismissible" and offers only **悔棋** and
  **结束对局**. Stacking a modal 取消/重试 notice over a non-dismissible card is undefined.
- **After 结束对局**, in History, in Settings, or in **Free Play** — where no engine was ever prepared,
  so there is nothing to re-prepare.

**Correction.** Make preparation conditional on the same predicate as the search: "Returning to the
foreground re-prepares the engine only when an active human-versus-AI game exists and is ongoing, and
requests a new search when `MxqGameStatus.search_expected` is set." (See 1.5.)

### 1.4 One rule is applied to four platforms; on macOS and Windows it is wrong — **blocking**

> "Moving to the background cancels any running search **and releases the transposition table**…"

The open item this replaced said "Define backgrounding, suspension, teardown, and memory-pressure
behavior **on each platform**." The replacement collapses to a single unqualified rule and never names
a platform. On iOS/iPadOS "background" is a suspension-bound state with a real reclaim threat, and the
rationale given ("precisely the profile the operating system reclaims first") is an iOS argument. On
macOS and Windows "background" is ordinary loss of key-window focus — clicking Safari. Under this rule
a macOS user who clicks another window mid-search loses the AI's thinking and pays a full re-probe,
re-prepare and multi-gigabyte Hash reallocation every time they switch back, and can be handed
无法启动 AI 对手 for doing so. The PR body's own justification ("a backgrounded app can be holding
gigabytes it is not using") does not hold for a macOS app that is merely not frontmost.

**Correction.** Scope the trigger per platform: on iOS and iPadOS the scene-background transition; on
macOS the app-termination and system-sleep/App-Nap transitions, explicitly **not** deactivation,
occlusion or window hiding; on Windows the equivalent, named when the toolchain is pinned. State
which event each platform uses, or return the item to **Need to discuss** for macOS and Windows.

### 1.5 "if one is owed" is not defined in this document — **should-fix**

The predicate exists and is normative — `core-interface.md`'s `MxqGameStatus` carries
`search_expected` "so frontends never re-derive rules policy" — but `engine-integration.md` never
names it, so an implementer is invited to re-derive it. It must cover the non-obvious case that the
contracts already accept: a **failed AI-reply save**, where `interaction-design.md` says "the game
remains at the last committed position with the AI still to move, and the app requests a new AI move".
That case *is* derivable from committed state (AI to move, ongoing), which is why the predicate works —
but the document should say so rather than leave it to inference.

**Correction.** Replace "if one is owed" with "when `MxqGameStatus.search_expected` is set, which is
the same predicate that drives a new search after a failed AI-reply save."

### 1.6 The backgrounding path is undefined against an in-flight creation attempt — **blocking**

The two new sections interact and neither mentions the other. Between step 1 (prepare) and step 4
(search) of the preparation ordering there is a window in which backgrounding "releases the
transposition table, returning the engine to the uninitialized state." The ordering section's only
invalidation trigger is "Leaving the pre-start state," which on iOS backgrounding is not — the user
has not navigated away and the draft is not discarded. So a backgrounded creation attempt can proceed
to step 3, persist an active game, and reach step 4 against a released engine; or step 3's release-on-
failure can race the lifecycle teardown. `core-interface.md` guards only the reverse direction
(`mxq_engine_prepare`/`teardown` return `MXQ_ERR_STATE_SEARCH_IN_PROGRESS`), and there is no
"preparation in progress" guard at all.

**Correction.** Add to the ordering section: "Backgrounding during an attempt invalidates it on the
same terms as leaving the pre-start state: nothing is created, anything prepared is released, and a
late completion cannot commit."

### 1.7 "store quiescence" names a step the accepted C surface has no function for — **should-fix**

> "…the frontend's lifecycle event drives cancellation, engine release, and store quiescence in that
> order."

`core-interface.md` declares itself "the core's complete C-visible surface" — "Six groups, 53
functions" — and contains no store-quiescence entry point. Store operations "commit inside the call"
and run "on the calling thread under one internal mutex", so there is nothing asynchronous to quiesce;
the only function that quiesces the store is `mxq_core_shutdown`, which is termination, not
backgrounding. Naming a third ordered step with no callable behind it will send an implementer looking
for a function that does not exist, or invent one outside the contract.

**Correction.** Either drop "and store quiescence" (the store is already quiescent by construction) or
name the actual requirement: "…drives `mxq_core_cancel_all` then `mxq_engine_teardown`; no store step
is required, because every store operation commits inside its call."

### 1.8 The lifecycle event arrives on a thread that may not make these calls — **should-fix**

`core-interface.md`'s threading table places `mxq_engine_teardown` on "any non-UI thread except a
callback", blocking, and `mxq_core_cancel_all` blocking "until the engine quiesces". Platform
backgrounding notifications are delivered on the main/UI thread under a bounded deadline. The new text
requires an ordered, blocking, off-UI sequence to complete inside that window and says nothing about
how.

**Correction.** Add: "The frontend takes the platform's background-task assertion, dispatches the
sequence off the UI thread, and completes it before releasing the assertion."

### 1.9 `architecture.md` was not updated in the same change — **should-fix**

`architecture.md` (accepted) says only: "Undo, game completion, active-game replacement, leaving the
relevant state, and app backgrounding **cancel outstanding work**." Releasing the transposition table
is strictly more than cancelling outstanding work, and it is the decision this PR is named for.
Change discipline requires the accepted contract to move in the same change.

**Correction.** Amend that line to "…cancel outstanding work; app backgrounding additionally releases
the engine's memory, per [engine-integration.md](engine-integration.md)."

---

## 2. Preparation ordering

### 2.1 `core-interface.md`'s open item was left in place and is now false — **blocking**

`core-interface.md` **Need to discuss** still reads:

> "The exact ordering and cleanup contract between pre-start engine preparation, Random resolution,
> game creation, and the first search; this interface assumes prepare → resolve → create → search but
> the ordering is **owned by [engine-integration.md](engine-integration.md) and remains open there**."

After this PR it does not remain open there. Two accepted contracts now disagree about the status of
the same question, and the repository's rule is explicit: "Update an accepted contract and its tests
in the same change that alters the corresponding behavior." The PR body claims it "Closes six of the
eight open items" but leaves the cross-reference that pointed at one of them asserting the opposite.

**Correction.** Delete that bullet from `core-interface.md`'s **Need to discuss** in this PR, and if a
pointer is wanted, note in the search-facade prose that the ordering is accepted in
`engine-integration.md`.

### 2.2 Resolving Random before create contradicts the accepted wording — **should-fix**

`interaction-design.md` (accepted): "A Random first-mover choice is **resolved only as part of
successful game creation**." `game-data.md` (accepted): "A Random first-mover choice remains
unresolved in the draft. Only successful **开始对局** creation **commits** the resolved human side…"

The new step 2 resolves before create. `game-data.md` is compatible — it constrains *committing*, not
*resolving*. `interaction-design.md` is not: it constrains *resolving*, and the new ordering resolves
at a point where creation may still fail. The PR's own mitigation ("so a resolved side never survives
a failed creation") is an argument that the outcome is equivalent, not that the accepted sentence is
still true.

There is also a behaviour the new text leaves unstated: because step 2 is inside the gated sequence, a
**retry after a persistence failure re-draws Random**. A user can press 开始对局, see a save failure,
retry, and get the opposite side. That may well be the right answer, but neither document says it.

**Correction.** In the same change, amend `interaction-design.md` to "A Random first-mover choice is
resolved during a creation attempt and is committed only by successful game creation; a failed attempt
discards it and a retry draws again," and add the retry sentence to the ordering section.

### 2.3 Ordering against the rest of the accepted pre-start behaviour — verified consistent

Checked and no conflict found: "**开始对局** creates no active game unless the required AI resources
are available and the game can be persisted successfully" is satisfied by prepare-first;
`game-data.md`'s "Each creation attempt is single-flight and bound to the identity or revision of the
pre-start session… leaving invalidates the session so a late result cannot commit a game" matches the
new closing sentence; Free Play is unaffected because it has no prepare step. The `testing.md` gate
for the ordering matches the contract text at each failure point.

---

## 3. Variant packaging

### 3.1 The `EvalFile` claim is the inverse of what the engine does; as written the AI ships on classical evaluation — **blocking**

> "The core always sets `EvalFile` explicitly to the bundled network's path and never relies on the
> engine's default network-name lookup, **which derives a filename from the variant identifier**.
> Renaming the variant therefore cannot silently detach it from its network, and the pinned
> `minixiangqi-12c45d5da817.nnue` **needs no alias**."

Every clause is wrong. There is no derivation. `src/evaluate.cpp:77-103` applies a **prefix filter to
whatever `EvalFile` you set**:

```cpp
    string eval_file = string(Options["EvalFile"]);
    stringstream ss(eval_file);
    string variant = string(Options["UCI_Variant"]);
    useNNUE = false;
    while (getline(ss, eval_file, UCI::SepChar))
    {
        string basename = eval_file.substr(eval_file.find_last_of("\\/") + 1);
        string nnueAlias = variants.find(variant)->second->nnueAlias;
        if (basename.rfind(variant, 0) != string::npos || (!nnueAlias.empty() && basename.rfind(nnueAlias, 0) != string::npos))
        {
            useNNUE = true;
            break;
        }
    }
    if (!useNNUE)
        return;
```

Consequences, in order of severity:

1. **Setting `EvalFile` explicitly does not bypass the lookup — the lookup is applied *to* it.** The
   basename must *start with* the variant name or the variant's `nnueAlias`.
2. **The chosen pair fails the filter.** `"minixiangqi-12c45d5da817.nnue".rfind("minixiangqiaxf", 0)`
   is `npos`. `useNNUE` is set to `false` and the file is **never opened**.
3. **The failure is silent, and it is exactly the fallback the same PR forbids.** `evaluate.cpp:1612`
   then evaluates with `Evaluation<NO_TRACE>` — classical. The only trace is `info string classical
   evaluation enabled` (`evaluate.cpp:165-171`), suppressed entirely under XBoard. This directly
   defeats the accepted **Accepted network failure policy** two sections later: "There is no fallback
   to the engine's classical evaluation… substituting a different evaluation would silently make the
   opponent a different opponent, which the user would have no way to detect." As written, this PR
   guarantees that outcome.
4. **The alias route is closed to an ini variant.** `nnueAlias` is not parseable from `variants.ini`
   (`grep nnueAlias src/parser.cpp` → nothing), and `Variant::init()` (`src/variant.h:223-227`)
   clears it to `""`, which `variant.cpp:2186` applies to every ini-derived variant. Built-in
   `minixiangqi` sets no alias either.
5. **"Renaming the variant cannot silently detach it from its network" is backwards.** The variant
   name is the *only* thing the filter keys on; renaming the variant is precisely what detaches it.
6. **The preflight as described will not catch this.** "The core preflights the network against the
   engine's observable load state before any search, so the engine's own fatal verification path is
   never reached" — the fatal path (`evaluate.cpp:141-163`, `exit(EXIT_FAILURE)`) is gated on
   `useNNUE == true` and is therefore *already* unreachable in this failure mode. A preflight that
   checks the file's presence and SHA-256 passes while `useNNUE` is `false`.

The reason this was not caught: the reconciliation's harness builds with `-DNNUE_EMBEDDING_OFF`
through pyffish and never loads a network, and the verification recorded in the document —
"Its structural loading with the current local `minixiangqi` engine has been verified" — used the
**built-in** variant, whose name *is* a prefix of the pinned basename.

**Correction.** Pick one and state it, plus its consequence for the network's packaged name:

- **(a), cheapest, no fork change:** bundle the network under a basename that begins with the variant
  identifier, e.g. `minixiangqiaxf-12c45d5da817.nnue`, and pin that name and its SHA-256 in the
  manifest. Replace the third bullet with: "The engine enables NNUE only when the basename of an
  `EvalFile` entry begins with the selected variant's identifier (`src/evaluate.cpp:77-103`), so the
  bundled network is named `minixiangqiaxf-<hash>.nnue`. `EvalFile` is set explicitly to its full
  path; the byte length and SHA-256 remain those of the pinned artifact. Renaming either the variant
  or the network without the other silently disables NNUE, so both are pinned together in the
  manifest."
- **(b):** add a seventh fork change making `nnueAlias` settable from `variants.ini`, set it to
  `minixiangqi`, and add it to the enumerated change set and the manifest.

Either way, add to the failure-containment section: "The core's NNUE preflight must assert the
engine's **effective** `useNNUE` after option application, not merely the network file's presence and
hash, because a name-filter miss disables NNUE silently and never reaches the engine's fatal
verification path." And correct the `testing.md` gate, which currently tests the wrong property:
replace "…and that `EvalFile` is set explicitly rather than resolved from the variant identifier" with
"…and that with the variant selected and `EvalFile` set, the engine reports NNUE evaluation enabled
with the pinned network — asserting effective `useNNUE`, not file presence."

### 3.2 `minixiangqiaxf` as an identifier — **verified, claim holds**

`VariantMap::parse_istream` (`src/variant.cpp:2149-2206`) applies **no** validation to a section name:
no charset, length, case-folding or reserved-word check. The name is the raw text between `[` and the
first `:` or `]`. `minixiangqiaxf` is already used in the fork's own `test.py:138-150` as
`[minixiangqiaxf:minixiangqi]`. The only effective constraints are elsewhere and none apply: the
value must match the map key exactly and case-sensitively (`ucioption.cpp:345`), `var` is reserved
(`ucioption.cpp:354`), and section names are not whitespace-trimmed. One worth recording: a name
containing `,` would corrupt the XBoard `variants=` feature string (`xboard.cpp:172-177`).

### 3.3 Both variants selectable in one build — **verified, claim holds**

`add("minixiangqi", minixiangqi_variant());` at `src/variant.cpp:1936` is **unconditional** — outside
both the `ALLVARS` and `LARGEBOARDS` blocks — and 7x7 fits the non-`LARGEBOARDS` limits. Ini loading
is purely additive: `parse_istream` never clears, and `VariantMap::add` uses `std::map::insert`, a
no-op on an existing key; `clear_all()` is called only at shutdown (`main.cpp:59`). `on_variant_path`
re-publishes the whole key set (`ucioption.cpp:70-78`), so both names appear in the combo.

The stated rationale is stronger than the document claims, and worth recording: a name **collision**
is not an override — `variant.cpp:2178-2180` prints `Variant 'X' already exists.` to stderr, discards
the custom definition, and keeps the built-in. Reusing `minixiangqi` would therefore silently ship the
**unmodified built-in adjudication**. That is the real argument for a distinct name.

**Correction (nit).** Add: "A custom variant that reuses a built-in name is discarded with a stderr
message and the built-in is kept, so a collision would silently ship the wrong adjudication."

### 3.4 "geometry and piece set identical, so the pinned network stays structurally valid" — true but not sufficient — **should-fix**

Structurally the claim is correct and in fact understated. The header hash is a compile-time constant
(`half_ka_v2_variants.h:55`, `0x5f234cb8u`) that encodes neither geometry nor piece set; the only real
gate is byte length against `nnueDimensions`, computed in `Variant::conclude()`
(`variant.cpp:2006-2070`) from `maxRank`/`maxFile`, the `pieceTypes` popcount, `nnueKing`, promotion
fields, `startFen`, the drop/pocket flags, and the king's `mobilityRegion`. `nMoveRule`, `nFoldRule`,
`chasingRule` and `flyingGeneral` appear nowhere in that computation, so the AXF adjudication settings
provably leave the dimensions and the byte length unchanged.

But structural validity is not what gates loading — the name filter is (3.1) — so the sentence as
written is the load-bearing justification for a conclusion it does not support. One further constraint
belongs with it: `nnueMaxPieces` is derived from `startFen` and selects the layer-stack bucket at
runtime (`evaluate_nnue.cpp:163`), so the variant must also keep `minixiangqi`'s `startFen` verbatim.

**Correction.** "The variant keeps built-in `minixiangqi`'s board geometry, piece set and starting
position exactly; it differs only in adjudication. The network's compatibility is determined by
`nnueDimensions` and the layer-stack bucket count, which those three inputs fix and which no
adjudication setting touches, so the pinned network remains structurally valid. Structural validity is
necessary but not sufficient — see the naming requirement above."

---

## 4. The fork change set

### 4.1 P2 is described as a different defect from the one confirmed — **blocking**

> "…a flying-general pin test that **does not require the intervening pieces to stand between the two
> generals**."

The reconciliation's P2 row is "flying-general pin must consider pieces of **both colours** between
the kings", and §3.2's proven fact is that `position.cpp:2981` computes

```cpp
Bitboard kingFilePieces = file_bb(file_of(square<KING>(~sideToMove))) & pieces(sideToMove);
```

— the **victim's own pieces only**, so "A **chaser** piece standing between the kings is invisible to
it." The confirmed witness (`2k4/7/R6/2r4/7/2P4/2K4 w`) is a white soldier on c2 that **is** between
the two kings; it is invisible solely because of its colour. The PR's description names the
`file_bb`-versus-`between_bb` half and omits the `pieces(sideToMove)`-versus-`pieces()` half — the
half the witness turns on. An implementer following this sentence would change `file_bb` to
`between_bb` and still fail `mx-chs-029`. The phrasing is also self-contradictory: a piece is
"intervening" only if it stands between.

**Correction.** "…and a flying-general pin test that considers only the victim's own pieces on the
generals' file, so a chaser's piece standing between the two generals is invisible and a free piece is
marked pinned. The test must be computed over the squares strictly between the generals and over
pieces of **both** colours."

### 4.2 Four of the six items are cited to a contract that explicitly does not require them — **blocking**

> "The pinned fork carries only focused changes **this contract or [xiangqi-rules.md](xiangqi-rules.md)
> requires**…"

`xiangqi-rules.md` is a **Partially accepted** contract whose status line reads: "The exact definitions
of protection, interruption, and **discovered and pinned attacks**, and the fixtures for those and for
the accepted **mutual and mixed** outcomes, **remain unresolved**." Its **Need to discuss** goes
further: "Approve the deferred edge-case fixture tranche — protection variants, interruption,
discovered and pinned attacks, mutual perpetual check, and check-over-chase precedence — **before** the
rules facade's chase adjudication is relied on beyond the first approved set."

Against that, of the six enumerated items:

| item | reconciliation | basis in `xiangqi-rules.md` today |
|---|---|---|
| soldier chase-target exclusion | P0, landed | accepted (`mx-chs-003`) — sound |
| recoverable Hash | — | this contract's failure-containment section — sound |
| static library target | — | this contract's build requirement — sound |
| pinned chaser | P1 | "pinned attacks … remain unresolved" |
| flying-general pin | P2 | "protection … remain unresolved" |
| discovered-check exemption | P5 | "discovered … attacks … remain unresolved" |
| repetition-branch accessor | P4 | reason "reserved for the **deferred** mutual-violation fixtures" |

The PR body concedes the point — "The rules interpretations behind the two adjudication corrections
are a separate PR against `xiangqi-rules.md`" — so this PR accepts, in a contract it simultaneously
promotes to "Accepted", four fork changes whose rules basis lives in an unmerged PR. The repository's
own rule is that "`Need to discuss` is always non-normative and does not authorize implementation
choices"; the citation here is to text that is not merely non-normative but explicitly deferred.

The "wrong-result defects rather than judgement calls" defence does not carry P4 (an outcome that
`xiangqi-rules.md` reserves for the deferred tranche) or P5 (see 4.3), and the reconciliation itself
records that P2's original witness was "arguable" and needed tightening — these were not self-evident.

**Correction.** Merge the `xiangqi-rules.md` PR first, or gate this section: move the four rules-derived
items out of the accepted enumeration into a sentence reading "The rules-derived fork changes are
enumerated once [xiangqi-rules.md](xiangqi-rules.md) accepts the corresponding interpretations," and
leave the three engineering items (P0, Hash, static library) accepted.

### 4.3 P5 is written as accepted although its decision is an unfilled placeholder — **should-fix**

The reconciliation's §7 is titled "Decisions that need the product owner" and D6 — "Patch the
discovered-check exemption gap" — ends literally `RESULT_D6_PLACEHOLDER`. §3.5's own heading is
"code gap CONFIRMED, **reachability NOT established**", and §8 records "wrong result **if reachable**
… reachability open". Listing it among six accepted changes with the unhedged justification "so the
accepted exclusion of generals and soldiers holds in every path rather than in two of three" states
more than the evidence does. The rule it completes *is* accepted, so accepting the patch is defensible
— but it was not among the four decisions the product owner confirmed.

**Correction.** Either obtain the decision, or append "The gap is confirmed in the source; no reachable
position has been constructed, so this completes an accepted rule rather than fixing a demonstrated
wrong result."

### 4.4 P3 is genuinely absent, but the list reads closed — **should-fix**

Verified absent, not half-present: the diff contains no mention of the chase window, parity, or the
three-occurrence span, and `position.cpp:2694-2695`/`:2716` are untouched in the fork (`git log`
shows only the P0 merge above upstream). Good.

The problem is the framing. "The pinned fork carries **only** focused changes…" plus "**Every** change
must … keep all approved fixtures passing" reads as a closed enumeration. The reconciliation's D1
recommends "**yes, patch**" for P3, classifies it as a *wrong result*, and gates it with three fixtures
(`mx-chs-030`/`031`/`032`). An implementer building the manifest and the fork from this list will
conclude the divergence is bounded at six and size the patch stack accordingly, and the moment those
fixtures are approved the sentence "must keep all approved fixtures passing" becomes unsatisfiable
without a seventh change that the list says does not exist.

**Correction.** Add one sentence: "One further candidate — the chase-window parity defect — is under
investigation and is not part of the pinned set; it enters this list only if it is accepted."

### 4.5 Delivery status recorded in a contract — **nit**

"**Landed**; it introduces a variant property…" and "Its Makefile **currently** produces…" are
progress statements. `AGENTS.md`: "Track progress, tasks, experiments, and delivery status in GitHub
Issues or CI artifacts, not in repository documents." The manifest's pinned revision already records
what has landed.

**Correction.** Drop "Landed;" — the pinned revision in the manifest is the record.

### 4.6 The Makefile claim is factually wrong — **nit**

> "Its Makefile currently produces an executable and a Python module, neither of which the core can
> consume."

`src/Makefile` has no Python-module target; its targets are `build`, `profile-build`, `strip`,
`install`, `clean`, `net`, `objclean`, `profileclean`, `default`, `all: $(EXE)`, `config-sanity`, and
the profile helpers. The Python module is built by `setup.py`, outside the Makefile.

**Correction.** "The fork's build produces a command-line executable and, separately, a Python
extension module; neither is linkable by the core."

---

## 5. Contract consistency and scope

### 5.1 The manifest claims authority over the fork's own build inputs — **should-fix**

> "the build flags and defines used for each supported platform; … the ordered list of focused patches
> applied at that revision"
> "The fork repository documents its own build implementation, but the app build reads only this
> manifest, so **a value that appears in both is authoritative here**."

`MiniXiangqi/CLAUDE.md` and `AGENTS.md`: "Fairy-Stockfish implementation, **build**, **patch-
maintenance**, and upstream-sync instructions belong in the Fairy-Stockfish repository." This
document's own scope line says it "does not define … fork maintenance, source-level patch design".
Pinning a revision and hashes is legitimately the consumer's business; an ordered patch list and
per-platform build flags and defines are the fork's build implementation and patch maintenance, and
the final clause inverts the routing rule outright — it makes the app repository the authority on the
fork's compiler defines.

The `testing.md` gate inherits it: "the packaged engine artifact is the static library built from the
pinned revision **and flags**."

**Correction.** Replace the flags bullet with "the fork build's identifier — the named build
configuration the fork repository defines for each supported platform — so the app pins *which*
configuration it consumes without restating its contents," and replace the authority sentence with
"The fork repository is authoritative for how its build configurations are defined; this manifest is
authoritative for which revision, configuration and artifact hashes the app consumes."

### 5.2 The status line's own enumeration omits sections it declares accepted — **should-fix**

> "**Status: Accepted engine contract.** The search-facade placement, AI profiles, rule-integration
> decisions, failure-containment decisions, NNUE handling policy, Apple memory entitlements,
> backgrounding and teardown behavior, preparation ordering, variant packaging, network failure
> policy, the pinned-input manifest, and the library build requirement below are all accepted…"

The document's own newly added `### Accepted fork change set` is not in that list, and neither are
`## Scope and ownership`, `## Search lifecycle`, or `### Build and packaging requirements`. Under
`AGENTS.md` a fully accepted document needs no enumeration ("content outside `Need to discuss` is
accepted intended behavior"), and a partially accepted one "must state exactly which sections are
accepted." Keeping a partial-acceptance enumeration under a full-acceptance heading makes it
ambiguous whether the fork change set is accepted — the one section where that matters most (4.2).

**Correction.** If the whole document is accepted, cut the enumeration: "**Status: Accepted engine
contract.** The concrete search-facade C surface is the accepted contract in
[core-interface.md](core-interface.md). Items under **Need to discuss** are non-normative."

### 5.3 Consistency with the accepted C surface — checked, no further conflict

The reserved insufficient-memory error is used consistently:
`MXQ_ERR_ENGINE_INSUFFICIENT_MEMORY` "drives the accepted low-memory retry flow with a fresh probe per
retry", and the new allocation-failure bullet routes to the same notice — consistent with
`core-interface.md`'s statement that `mxq_engine_prepare` "refuses below the 256 MiB minimum … without
initializing anything" and with the reserved Hash-allocation-failure code being "reachable only after
the fork change". Cancellation ownership is consistent (`mxq_core_cancel_all` is annotated
`/* backgrounding */`). The two real gaps are 1.7 (store quiescence) and 1.8 (thread).

`src/tt.cpp:74-76` (`exit(EXIT_FAILURE)` on allocation failure) and `src/misc.cpp:474-481`
(large-page free on Windows) confirm the two enumerated process exits. Note a third that the
failure-containment section does not mention: `src/evaluate.cpp:141-163` also calls
`exit(EXIT_FAILURE)`. The contract's claim that it "is never reached" is currently true only because
the name filter disables NNUE first (3.1); once 3.1 is fixed it becomes reachable and depends entirely
on the preflight.

---

## 6. Document-status discipline and testing

### 6.1 A confirmed product-owner decision is missing from the diff — **blocking**

The fourth confirmed decision — **build locally now, with CI on both a macOS and a Windows runner when
Windows starts** — appears nowhere in the change. `engine-integration.md` still says CI is
"**recommended**"; `testing.md:31` still says "GitHub Actions CI is the **recommended** place for long
or multi-platform builds"; and `testing.md`'s **Need to discuss** still carries "Define the GitHub
Actions workflows, their pinned inputs, and which artifacts they retain." The PR promotes the document
to Accepted and adds ten gates, but omits the one decision on this subject that was actually made.

**Correction.** Record it in `engine-integration.md`'s build requirements and in `testing.md`:
"Engine and core builds run locally today. Once Windows implementation begins, CI runs the build on
both a macOS runner and a Windows runner, with pinned inputs from the manifest," and update
`testing.md:31` and its open item accordingly.

### 6.2 Removed open item vs. the gates that replaced it — **should-fix**

The removed item "Validate the complete approved fixture set, including `mx-chs-003`, against the fork
build that implements soldier chase-target exclusion" is evidence-backed for **P0 alone**: the
reconciliation records `77d602e0` with "all sixteen approved fixtures pass", and the fork's `git log`
confirms P0 is the only landed change. But the accepted change set now has five more items, and while
the new prose says "must keep all approved fixtures passing", **none of the ten new `testing.md` gates
covers it** — not the fixture set against the pinned fork build, and not "leave built-in variants'
adjudication unchanged". A normative sentence with no gate is exactly what the removed item was
protecting.

**Correction.** Add: "Verify the complete approved fixture set passes against the pinned fork build,
and that built-in variants' adjudication is unchanged by every patch in the pinned set."

### 6.3 Gates that restate the contract's errors — **blocking** (subsumed by 1.1, 1.2, 3.1)

Three of the ten new gates test the wrong property because they faithfully mirror wrong contract text:
the revision-check gate (1.1), the "resumable with the AI unavailable" gate (1.2), and the
`EvalFile` gate (3.1). Corrections are given in those sections. The remaining seven match the contract
text.

### 6.4 Duplicate and now-stale memory-probe gates — **nit**

The new gate "Verify each platform's memory probe against the accepted budget boundaries on real
hardware" duplicates the existing "Verify each platform's memory probe: `os_proc_available_memory()`
on iOS and iPadOS, and **the selected system-availability probes** on macOS and Windows" — which this
PR has now made concrete but did not update. The pre-existing gate also already covers "allocation
failure".

**Correction.** Fold the new gate into the existing one and name the three APIs there.

### 6.5 The macOS probe formula double-counts, and duplicates an existing bullet — **nit**

> "on macOS, `host_statistics64` with `HOST_VM_INFO64`, taking available memory as the free, inactive,
> and purgeable pages"

`free_count` already includes speculative pages and `purgeable_count` overlaps the inactive/external
counts, so free + inactive + purgeable over-reports on a machine using memory compression. It is the
common heuristic and the new **Need to discuss** item defers measured verification, so this is not
blocking — but the same paragraph now states the macOS probe twice at two precisions (the existing
bullet says it "reports the system's available physical memory").

**Correction.** Merge the two bullets and note the overlap: "…the free, inactive and purgeable page
counts, which overlap and therefore over-report; the measured behaviour is confirmed per platform
before that platform ships."

### 6.6 The manifest is declared accepted while its schema is undefined — **nit**

The status line accepts "the pinned-input manifest" while the new **Need to discuss** says "Fix the
manifest's concrete field names and schema version when the first build consumes it." The deferral is
honest; the status line overstates it.

**Correction.** "…the pinned-input manifest's contents (its concrete schema remains open below)…"

### 6.7 Items decided by the author rather than the owner — audit

Checked against the four confirmed decisions. Consistent with the accepted contracts and reasonable as
engineering choices: the memory-probe APIs (6.5 aside); the manifest's contents (5.1 aside); the
static-library requirement (verified: `src/Makefile` produces only `$(EXE)`); `minixiangqi-variants.ini`
as the bundled filename; and the ordering itself (2.2 aside). Not consistent, and covered above:
the identifier/alias reasoning (3.1), the P2 description (4.1), the rules-derived change set (4.2),
P5 as accepted (4.3), per-platform backgrounding (1.4), and the missing CI decision (6.1).

---

## Verdict

**DO NOT MERGE**
