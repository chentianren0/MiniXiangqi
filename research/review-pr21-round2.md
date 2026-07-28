# Pre-merge review — PR #21 `design/engine-packaging`, round 2

Re-verification of commit `ab56b48` ("Fix pre-merge review findings in the engine contract"), rebased
onto `main` at `d357c4a` (PR #20 merged). Read-only throughout; nothing written to GitHub.

Round-1 report: `discussion-drafts/review-pr21.md`.

**Verdict: DO NOT MERGE** — but narrowly. Seventeen of the nineteen round-1 findings are genuinely
fixed, and the two blocking items left are each a one-clause correction. Both are *consequences of the
round-2 fixes* rather than survivals from round 1.

---

## A. Round-1 findings — verification

| # | finding | status |
|---|---|---|
| 3.1 | `EvalFile` prefix rule / silent classical fallback | **fixed** (A.1) |
| 1.1 | late result "rejected by the revision check" | **fixed here, broken elsewhere** → B1 |
| 1.2 | mid-game re-preparation has no defined UI state | **fixed** — routed to Need to discuss (A.3) |
| 1.3 | re-preparation unconditional | **fixed** (A.4) |
| 1.4 | one backgrounding rule for four platforms | **partly fixed** → B2 |
| 1.6 | backgrounding vs. in-flight creation | **fixed** |
| 4.1 | P2 misdescribed | **fixed** (A.5) |
| 4.2 | four fork changes cited to deferred definitions | **fixed, with a defective clause** → C1 |
| 4.4 | P3's absence unsignalled | **fixed** |
| 6.1 | missing CI decision | **fixed** (A.6) |
| 2.1 | `core-interface.md` ordering item stale | **fixed** — bullet deleted |
| 2.2 | Random resolved before create | **fixed** — retry re-draw now stated |
| 1.5 | "if one is owed" undefined | **fixed** — defined in place |
| 1.7 | "store quiescence" | **fixed** enough (nit D5) |
| 1.8 | blocking teardown on the lifecycle thread | **fixed** |
| 1.9 | `architecture.md` not updated | **not fixed** → B1 |
| 5.1 | manifest claimed authority over the fork's build | **fixed** |
| 5.2 | status line omitted the fork change set | **fixed** |
| 6.2 | no gate for the fixture set against the pinned build | **fixed** |
| 6.3 | gates restating wrong contract text | **fixed** for NNUE and revision; **new instance** → B2 |

### A.1 The NNUE prefix fix is correct — verified against source

> "**The bundled network's filename must begin with the variant identifier.** … the engine restricts
> NNUE to the matching variant by requiring the file's basename to start with the variant name (or
> with a `nnueAlias` that an `.ini` variant cannot set). A basename that does not match does not
> produce an error — it silently sets `Use NNUE` false and the engine plays on classical evaluation.
> The pinned network is therefore bundled as **`minixiangqiaxf-12c45d5da817.nnue`**. Only the filename
> changes; the bytes, the byte length, and the SHA-256 that pins them are unchanged, since the hash is
> over content."

Re-checked against `src/evaluate.cpp:77-103`. Every clause is now accurate:
`basename.rfind(variant, 0) != string::npos` is a prefix test; `nnueAlias` is unparseable from
`variants.ini` and cleared by `Variant::init()`; a miss `return`s with no diagnostic other than an
`info string`. `"minixiangqiaxf-12c45d5da817.nnue".rfind("minixiangqiaxf", 0) == 0` — the new name
passes. The content hash is invariant under rename, so keeping the length and SHA-256 is right, and
the NNUE-policy bullet was updated in the same commit so the two sections agree. The preflight
requirement ("assert the engine's **effective NNUE state** after configuration, not merely that the
file exists and parses") is the correct guard, and `testing.md` gained a matching gate.

One wording defect remains — see C2.

### A.2 Late-result rejection — the statement here is now correct

> "A result arriving from a search cancelled this way is discarded because **its request is no longer
> the current one** — the cancellation itself is what rejects it. The position-revision check does not
> cover this case: no mutation occurred, so the revision is unchanged and a late result would match
> it."

Correct, and the `testing.md` gate matches it. The problem is that two other accepted contracts still
say the opposite — B1.

### A.3 Mid-game re-preparation failure — honestly routed

The contract now states the outcome and explicitly declines to invent the presentation:

> "…it is an open interaction question below."

and the new open item names the reason precisely: "The accepted **无法启动 AI 对手** notice assumes a
game that has not started, so its wording and its 取消 action do not fit". That is the right
resolution: the engine contract states what it owns, and the presentation question goes to the
document that owns it. Should-fix C3 is only that the receiving document was not told.

### A.4 Re-preparation gating — well-defined, and better than deferring to foreground return

> "**Re-preparation happens when a search is next owed, not on return to the foreground.** A search is
> owed exactly when the resumed state is an active human-versus-AI game whose committed status reports
> the AI to move and a search expected. Replay, Free Play, a confirmed result, a game awaiting the
> user's move, and having no active game all require no engine, so none of them re-prepares one."

This closes 1.3 and 1.5 together and is stronger than what I asked for. Checked against the cases in
the brief: the failed-AI-reply-save path (`interaction-design.md`: "the game remains at the last
committed position with the AI still to move, and the app requests a new AI move") is covered, because
the committed status reports the AI to move; the first search after creation is covered by the
ordering section; suspension during creation is covered by the new invalidation bullet; replay, Free
Play, the non-dismissible result card and the confirmed-result state are all named as requiring
nothing. The predicate is exactly `MxqGameStatus.search_expected`, and moving preparation to the
moment a search is owed also makes it agree with `interaction-design.md`'s accepted "Any active game
being resumed remains saved and unchanged while the AI opponent is unavailable."

### A.5 P2 is now described accurately

> "…a flying-general pin test that counts only the victim's own pieces on the shared file, so a chaser
> standing between the two generals is invisible to it and a demonstrably free piece is marked pinned."

Matches `position.cpp:2981` (`file_bb(file_of(square<KING>(~sideToMove))) & pieces(sideToMove)`) and
matches the confirmed witness `mx-chs-029`, whose blocker is a white soldier on c2 — between the kings
and invisible solely because of its colour. Correct.

### A.6 CI — verified against the merged policy

`architecture.md:79-80` on the new `main` reads: "Builds run on developer machines while the project is
Apple-only… When Windows implementation begins, GitHub Actions CI covers **both** a macOS runner and a
Windows runner". The engine contract's replacement bullet quotes it faithfully. Round-1 finding 6.1 is
resolved.

---

## B. Blocking

### B1. The corrected cancellation rule now contradicts two accepted contracts — **blocking**

*This is the line the coordinator asked me to name — and there are two.*

`architecture.md:51` (accepted, "Concurrency and lifecycle"):

> "Undo, game completion, active-game replacement, leaving the relevant state, and app **backgrounding**
> cancel outstanding work. Cancellation is cooperative, and a result is rejected whenever its revision
> is stale — **cancellation alone is not trusted**."

`core-interface.md:130` (accepted, search facade):

> "Because every accepted mutation bumps the revision, an un-cancelled in-flight search is neutralized
> by staleness; **cancellation is a promptness optimization, not a correctness requirement**."

Both are now false in exactly the case this PR introduces, and the engine contract says so in as many
words: "no mutation occurred, so the revision is unchanged and a late result would match it… the
cancellation itself is what rejects it."

`core-interface.md` is the more dangerous of the two, because `engine-integration.md:28` delegates to
it: "The concrete search-facade functions, request/result types, **cancellation and stale-rejection
mechanics**, and threading rules are the accepted contract in [core-interface.md](core-interface.md)."
So the document that owns the rejection ladder tells its implementer that the cancelled rung is an
optimization — which is precisely the belief that produced round-1 finding 1.1. Fixing the consequence
in `engine-integration.md` while leaving the premise standing in the delegated-to document reopens the
same hole one indirection away.

`architecture.md:51` has a second, independent problem: it names the trigger as "app **backgrounding**",
which the engine contract now explicitly rejects for two of four platforms — "The trigger is the
platform's own suspension signal, not loss of focus… switching windows changes nothing." On macOS and
Windows, "app backgrounding" in ordinary usage *is* not being frontmost. It also says only "cancel
outstanding work", where the accepted behaviour is now cancel *and release the transposition table*.

**Corrections.**

- `core-interface.md:130` — append: "That holds for every cancellation accompanied by a mutation. It
  does not hold for suspension, which cancels without mutating: there the revision still matches and
  the cancelled rung of the ladder is the only thing that rejects the result, so it is a correctness
  requirement in that case."
- `architecture.md:51` — "Undo, game completion, active-game replacement, leaving the relevant state,
  and the platform's app-suspension signal cancel outstanding work; suspension additionally releases
  the engine's memory, per [engine-integration.md](engine-integration.md). Cancellation is
  cooperative. A result is rejected whenever its revision is stale, and a result from a
  suspension-cancelled request is rejected as superseded even though no mutation bumped the revision."

Both are accepted documents, so change discipline requires them to move in this same PR.

### B2. iOS and iPadOS memory pressure was dropped, and a gate now has no contract behind it — **blocking**

Round 1 said: define the trigger per platform. The fix did that for focus loss, but in doing so it
deleted this round-1 bullet entirely —

> "Under a platform memory-pressure warning while in the foreground, the engine cancels and releases on
> the same path rather than shrinking Hash, because a partially reduced table is not a state this
> contract defines."

— and folded memory pressure into the macOS/Windows branch only:

> "On iOS and iPadOS that is scene backgrounding. On macOS and Windows … it is system sleep, app
> termination, and a platform memory-pressure notification".

Two problems.

**(a) The primary platform lost its memory-pressure behaviour.** iOS and iPadOS are where a hard
per-process limit exists, where `os_proc_available_memory()` is the probe, where the
`increased-memory-limit` and `extended-virtual-addressing` entitlements are requested, and where the
app may be holding up to 4 GiB of Hash. A foreground memory warning there is the last signal before
jetsam. The contract's own rationale — "a suspended app can be holding gigabytes it is not using…
Losing the app costs the user their place" — is an argument *for* responding to it, and the previous
revision did. As written, an implementer does nothing on an iOS memory warning and the app is killed
holding the table. The removed open item was "Define backgrounding, suspension, teardown, **and
memory-pressure behavior** on each platform"; on the platform that matters most it is now undefined,
so that item is not genuinely resolved.

**(b) A `testing.md` gate now tests a rule the contract no longer states.** The gate survives —

> "Verify a memory-pressure notification takes the same cancel-and-release path and **never shrinks
> Hash in place**."

— but "never shrinks Hash in place", and the reasoning that a partially reduced table is not a defined
state, were deleted along with the bullet. This is round-1 finding 6.3's failure mode inverted: a gate
asserting a property no accepted text carries.

**Correction.** Restore both, inside the per-platform sentence:

> "On iOS and iPadOS that is scene backgrounding or a memory-pressure warning; on macOS and Windows,
> where an unfocused window is still a running app, it is system sleep, app termination, or a
> memory-pressure notification; switching windows changes nothing."

and restore the deleted clause as its own bullet: "A memory-pressure signal takes this same path
rather than shrinking Hash, because a partially reduced table is not a state this contract defines."

---

## C. Should-fix

### C1. "execution-confirmed" and "lands with its fixture" are both false for the classifier-path completion

*This is the direct answer to the coordinator's P5 question.*

> "The two adjudication corrections and the classifier-path completion rest on **execution-confirmed
> defects** rather than on the deferred definitions… **Each lands together with the fixture that pins
> it**, in the deferred edge-case tranche, **and not before**."

Accepting P5 is **not blocking** — the rule it completes ("kings and soldiers are excluded as chase
targets") is accepted in this contract and in `xiangqi-rules.md`, the change is one line inside a
function the fork already patches, and making an accepted rule true in all three classifier paths
rather than two needs no new interpretation. I would not hold the merge for that.

The sentence justifying it is the problem, because it asserts two things that the evidence base
contradicts for that item specifically:

- **"execution-confirmed"** — the reconciliation's §3.5 heading is "code gap CONFIRMED, **reachability
  NOT established**", and its body: "**a real code gap of unproven reachability, not a demonstrated
  wrong result**." I checked the search output: `r-p4c.out` reaches 29,500 legal samples over
  11,192,728 cycles with **0 hits**. That is strong evidence the path is *unreachable* — the opposite
  of execution-confirmation, and in fact the argument D6 itself records against patching ("an
  unreachable patch is pure cost"). The 20,000-sample figure understates the run, but the direction of
  the inference is backwards.
- **"lands together with the fixture that pins it… and not before"** — P5 has no fixture. §5.5's
  patch-gating slate is `mx-chs-028` (P1), `029` (P2), `030`/`031`/`032` (P3), and §6 records "A
  witness for the discovered-check exemption gap (§3.5): **Not constructed.**" Read literally, this
  clause makes the classifier-path completion unlandable, contradicting the enumerated item four lines
  above it. Two accepted statements in one section disagree.

**Correction.** Split the sentence:

> "The two adjudication corrections rest on execution-confirmed defects rather than on the deferred
> definitions of protection, interruption, and discovered or pinned attacks, which
> [xiangqi-rules.md](xiangqi-rules.md) still leaves open; each lands together with the fixture that
> pins it, in the deferred edge-case tranche, and not before. The classifier-path completion is
> different: the gap is confirmed in the source but no reachable position has been constructed, so it
> completes an accepted rule in all paths rather than fixing a demonstrated wrong result, and it is
> not fixture-gated."

Note also that the two placeholders in the evidence base (`RESULT_PLACEHOLDER` at
`rules-edge-cases-reconciliation.md:569` and `RESULT_D6_PLACEHOLDER` at `:641`) are still unfilled, so
the conclusion this PR relies on is not written down anywhere. That is a workspace-draft matter, not a
repository one, but it is worth closing before the `xiangqi-rules.md` PR cites it.

### C2. "silently sets `Use NNUE` false" names the wrong thing

`Use NNUE` in backticks is the exact UCI option name, and the option is **not** modified.
`evaluate.cpp:79` reads it into the internal `Eval::useNNUE`; the prefix loop then clears that internal
variable at `:91`. `Options["Use NNUE"]` still reports `true`. An implementer who takes the sentence
literally and preflights by reading the option back gets `true` while the engine evaluates classically
— which is the precise trap the very next bullet exists to prevent.

**Correction.** "…it silently disables the engine's internal NNUE flag while the `Use NNUE` option
still reads back true, and the engine plays on classical evaluation."

### C3. The interaction question was routed but not delivered

> "…this belongs to [interaction-design.md](interaction-design.md)."

`interaction-design.md` was not touched. Its **Need to discuss** has adjacent items — "Define the
insufficient-memory notice presentation, repeated-failure behavior, and accessibility announcement"
and "Define empty, loading, AI-thinking, error… states" — but neither names the mid-game
AI-unavailable state, which is a new state this PR creates. This is the milder mirror of round-1
finding 2.1: a document declaring a question owned elsewhere without the owner recording it.

**Correction.** Add to `interaction-design.md`'s **Need to discuss** in this PR: "Define what the user
sees when an active human-versus-AI game is resumed after suspension and the engine cannot be
re-prepared: the game is active and saved with the AI unable to move, and the accepted **无法启动 AI
对手** notice does not fit, because its wording and its 取消 action assume a game that has not started."

---

## D. Nits (unchanged from round 1 unless noted)

1. **The Makefile claim is still factually wrong.** "Its Makefile currently produces an executable and
   a Python module" — `src/Makefile`'s targets are `build`, `profile-build`, `strip`, `install`,
   `clean`, `net`, `objclean`, `profileclean`, `default`, `all: $(EXE)`, `config-sanity` and the
   profile helpers. No Python target; `setup.py` builds the module. Say "the fork's build produces a
   command-line executable and, separately, a Python extension module".
2. **"Landed;"** is delivery status in a contract; the manifest's pinned revision is the record.
3. **Duplicate probe gates** — the new "Verify each platform's memory probe against the accepted budget
   boundaries on real hardware" still duplicates the existing "Verify each platform's memory probe:
   `os_proc_available_memory()` on iOS and iPadOS, and the selected system-availability probes on
   macOS and Windows", which was never updated to name the now-fixed APIs.
4. **macOS probe formula** — free + inactive + purgeable double-counts (`free_count` includes
   speculative; `purgeable_count` overlaps the inactive/external counts), so it over-reports under
   memory compression. Deferred by the Need-to-discuss item, so not urgent.
5. **"then the store's outstanding work"** still names a third teardown step for which the 53-function
   surface has no entry point; store calls commit inside the call, so there is nothing to drain.
6. **New:** the round-1 gate clause "that the committed game is unchanged throughout" was dropped in the
   rewrite, while the contract still says "The committed game is never affected." Restore it.
7. **"Its structural loading with the current local `minixiangqi` engine has been verified"** now sits
   directly after the renamed file and reads as if it verified the bundled artifact. It verified the
   *built-in* variant, whose name happened to satisfy the prefix rule. Say so, or drop it.
8. The status line accepts "the pinned-input manifest" while **Need to discuss** defers its schema.

---

## Verdict

**DO NOT MERGE** — two blocking items, each a one-clause fix:

- **B1**: `core-interface.md:130` and `architecture.md:51` still say cancellation is not a correctness
  requirement and that staleness is the authority; the corrected engine text depends on the opposite,
  and `engine-integration.md:28` delegates the rejection mechanics to one of them.
- **B2**: iOS/iPadOS memory pressure is no longer a trigger, and the "never shrinks Hash in place" rule
  was deleted while its `testing.md` gate survives.

**C1** (the P5 justification sentence) is the should-fix I would most want landed with them. Accepting
P5 itself is not blocking.
