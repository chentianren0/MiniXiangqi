# Pre-merge review, round 2 — PR #20 `design/core-settings-and-structure`

Read-only re-verification of commits `49a6e61` "Cut CLAUDE.md back to what was actually asked
for" and `499df7b` "Fix pre-merge review findings for Settings and the restructure", on top of
`576a9be`. Nothing in `MiniXiangqi/` was modified; nothing was written to GitHub.

Round-1 report: `discussion-drafts/review-pr20.md`.

**Scope note.** Per the coordinator, the removal of the canonical routing list, the
accepted/draft status rules, the fixed-project-settings list, the change-discipline block and the
validation block from `CLAUDE.md` was done at the user's instruction and is **not** re-reported.
Round-1 findings **S2, S3, S4, N1, N2** and the change-discipline half of **S5** are moot: the
rules they concerned no longer exist by design. What is checked instead is whether anything now
*dangles* or *depends on a rule that is gone* — section 2 below.

Net diff against `main` is now 8 files, +40/−107. Branch is current with `main`;
`mergeStateStatus: CLEAN`.

---

## 1. The two blocking items

### B1 — `game-data.md` status line. **FIXED, complete.**

> `docs/game-data.md:5`: "…content equivalence and import validation, the store schema version 1,
> **the Settings placement**, and the migration and compatibility promise below are accepted."

The new entry sits in the enumeration, in document order, matching the `### Accepted Settings
placement` section at `:149`. The pattern every other accepted section follows — a `### Accepted …`
heading with a corresponding status-line phrase — is now unbroken across all six of them. The
authority chain `product.md:87 → game-data.md` and `architecture.md:36 → game-data.md` now
terminates in accepted text. ✅

*Residual (nit, carried, never a finding):* `### Accepted Settings placement` is still a `###`
subsection of `## Library store schema` even though its content is that preferences are **not** in
the store. Now that the status line names it in its own right, promoting it to `##` would match.

### B2 — the CI direction. **Structurally FIXED; one residual conflict, one open question.**

> Moved out of **Need to discuss** into the body of `## Repository layout and build`
> (`architecture.md:77`), and the open item narrowed to `:83` — "Windows toolchain pinning for the
> core and frontend, and the concrete CI matrix and runner images."

All three sub-problems from round 1:

1. **Self-contradictory placement** — resolved. No text calling itself accepted remains inside a
   section declared non-normative. ✅
2. **Not covered by the status line** — resolved without needing an edit: `architecture.md:5`
   already accepts "the build and CI policy below", which is exactly the section it moved into.
   The version pin was also correctly dropped ("a macOS 26 runner" → "a macOS runner"), matching
   the narrowed open item about runner images. ✅
3. **An unratified fifth decision** — see **R2** and the flag below. Not a discipline violation any
   more; a content question.

---

## 2. Does anything now dangle, or depend on a rule that no longer exists?

This was the coordinator's substituted question for item 1. **Answer: no on both counts.**

**Dangling references — none.** `grep -rn "CLAUDE\|AGENTS"` across every tracked file in the
repository returns exactly one hit:

> `CLAUDE.md:3`: "Rules for this repository. The workspace `../CLAUDE.md` also applies, and owns
> the workspace boundary, authorization, identity isolation, and the Apple toolchain."

`../CLAUDE.md` exists (27 lines) and does own all four named areas — Boundaries, Authorization,
Identity, Apple toolchain. Both round-1 repoints were removed rather than left pointing at deleted
sections:

- `architecture.md:74` — "The fixed project settings listed in `CLAUDE.md` — bundle identifiers,
  development team, …" is gone, replaced by the self-contained "It changes file locations and the
  project's references to them, and nothing else about the build." That is a better constraint
  than the reference it replaced: it is checkable against the diff of the relocation itself. ✅
- `core-interface.md:3` — "the documents in [CLAUDE.md](../CLAUDE.md)'s canonical list" is gone.
  Its replacement is inaccurate for a different reason; see **R3**. ✅ for the dangle, ✗ for the
  wording.

**Nothing depends on a vanished rule.** I traced every guardrail that `docs/` relies on:

| Removed from `CLAUDE.md` | Where the docs' dependence is satisfied now |
|---|---|
| Document status authority (the four accepted/draft rules) | Every one of the eight documents carries a **self-contained** status line: `product.md:5–7` and `interaction-design.md:5–7` define accepted-outside-`Need to discuss` in their own words; `architecture.md:5`, `core-interface.md:5`, `game-data.md:5`, `engine-integration.md:5` and `xiangqi-rules.md:5` enumerate what is accepted; `testing.md:5` declares itself non-normative until marked otherwise. `CLAUDE.md:5` delegates correctly — "Each document states its own scope and status in its opening lines … follow the status it declares." No document relies on a rule stated only in `CLAUDE.md`. ✅ |
| Canonical routing list | `README.md:41–48` lists all eight contracts with one-line scopes; each document's opening paragraph states what it does and does not own. ✅ |
| Fully offline boundary | `product.md:15`, `architecture.md:12` (both accepted). ✅ |
| Single main window | `product.md:26`, `architecture.md:13`. ✅ |
| Rules-facade authority / search never commits | `architecture.md:21–22`, `xiangqi-rules.md:79`, `core-interface.md:131`. ✅ |
| Never commit NNUE bytes | `engine-integration.md:91` — "The repository never contains NNUE bytes. The network file is not committed to version control in any form" — inside the *accepted* NNUE handling policy; plus `README.md:54`. ✅ |
| Platform scope, deployment targets, `x86_64`, Swift 6 | `product.md:17–25`, `README.md:26–35`, `testing.md:11–16`. ✅ |
| Bundle identifiers, development team, signing, entitlements | `MiniXiangqi.xcodeproj/project.pbxproj` (`DEVELOPMENT_TEAM = 7P9PPXP2SF` at five build configurations). This is the verified fact rather than a copy of it — which is what the user asked for. No document references the list, so nothing dangles. ✅ |
| Validation matrix | `docs/testing.md` in far more detail than `CLAUDE.md` ever held. See the observation at the end of this report. |

---

## 3. Round-1 fixes verified

| Round-1 | Status | Evidence |
|---|---|---|
| S5 (`testing.md`) | **FIXED** | `:103` now reads "Test **pin-state persistence**, History sorting, replay, permanent deletion…" — the delete-confirmation preference is out of `### Game data`. Four gates added at `:143–146`. Nothing was lost: `:143` "every Settings preference persists … and survives relaunch" subsumes the removed clause, and `:81` still covers the behaviour. ✅ (placement defect at `:146` — see **R4**) |
| S6 (删除前确认 mischaracterized) | **FIXED, well** | `:153` "No preference is: **four** are presentation or device capability; **Confirm Before Deleting** gates a permanent deletion but does not perform it, and the core's own deletion invariants — including that a failed deletion leaves the record intact — hold whatever the preference says; and the two that affect a game are read only when one is created." Arithmetic checks (4 + 1 + 2 = 7) and the new reasoning is the correct one — the conclusion now rests on the deletion invariants at `:125`, not on a false claim about what kind of preference it is. ✅ |
| S7 (archive collision) | **FIXED, complete** | `:157` "…The archive does record `first_mover_choice` and `ai_level`, but as the created game's own frozen configuration rather than as the preference that suggested it; changing the preference afterwards leaves the archived game untouched." Reconciles cleanly with `:38` and `:48`. ✅ |
| S8 (pre-start draft crosses the C boundary) | **HALF FIXED** | `game-data.md:154` corrected. `architecture.md:36` was **not** touched. See **R1** — the PR summary's claim that "the pre-start draft no longer 'crosses the C boundary'" is not accurate as stated. ⚠️ |
| S9 (Windows / interface language) | **FIXED in `product.md`** | `:85` now distinguishes Apple from Windows; `:109` adds "Decide whether the Windows build needs an in-app interface-language override, once the Windows frontend exists and internal testers there can be asked." `interaction-design.md` not updated — see **R6**. ⚠️ |
| S10 (`fixtures/`) | **FIXED** | Added to the tree at `:71` with a placement rationale at `:74`. ✅ (wording — see **R5**) |
| S11 (naming inside `game-data.md`) | **FIXED** | `:125`, `:151`, `:153` all use "Confirm Before Deleting". ✅ (cross-document split remains — **R7**) |
| N4 | unchanged | `game-data.md:147` "…and are not planned for a later one". Still a small unrequested narrowing; still a nit. |

---

## 4. New and residual findings

**R1 — `architecture.md:36` still contradicts `:35` and the C interface. should-fix.**

> `architecture.md:35`: "transient UI state such as selection, **pre-start drafts**, and
> confirmation flows;" *(listed among what **frontends own**)*
> `architecture.md:36`: "The core never reads one: the two that affect a game **cross the C
> boundary in the pre-start draft** at creation."

The correction was applied to `game-data.md:154` ("The frontend holds the pre-start draft in
memory and passes its resolved values as arguments to game creation") but not to the second
location quoted in round 1. Two adjacent bullets of an accepted contract now say the draft is
frontend-only transient state and that it crosses the C boundary. `core-interface.md:45,54` is
unambiguous — what crosses is `MxqGameConfig` at `mxq_game_create`.

*Correction:* `architecture.md:36` → "…The core never reads one: the two that affect a game are
passed as arguments to game creation and frozen into the game."

**R2 — the two CI bullets conflict. should-fix.**

> `:76`: "Long or large builds … are **recommended to run on GitHub Actions CI rather than only on
> developer machines**. **CI is a convenience, not a required gate**…"
> `:77`: "**Builds run on developer machines until Windows implementation begins**… When Windows
> begins, **CI covers both** a macOS runner and a Windows runner, **so neither platform is ever
> reproducible only on one machine**."

Two adjacent accepted bullets. The first recommends CI for exactly the build classes the second
says run locally; the first declares CI not a required gate, the second states an obligation
("covers both", "never … only on one machine"). A reader has to guess which governs today.

*Correction:* fold into one bullet — "Long or large builds … are recommended to run on GitHub
Actions CI rather than only on developer machines; CI is a convenience, not a required gate, and
must not receive undocumented inputs … Until Windows implementation begins that recommendation is
not acted on: Windows cannot be built here at all, and CI setup would otherwise block the first
Apple work, so builds run on developer machines. When Windows begins, CI is expected to cover both
a macOS runner and a Windows runner."

*Flag, not a finding:* the CI commitment remains outside the four decisions the product owner
confirmed. It is now legitimately placed and legitimately covered by the status line, so there is
no discipline problem — but "CI covers both runners" is an obligation nobody ratified. Worth one
sentence of confirmation. The local-builds-for-now half is a statement of fact (Windows is
unbuildable on this machine) and needs no ratification.

**R3 — `core-interface.md:3` now routes progress tracking into `docs/`. should-fix.**

> "It does not define Xiangqi rules, persistence schemas, archive serialization, engine search
> policy, UI behavior, **implementation progress, or work tracking**; those belong to **the other
> contracts in this directory**."

The first five belong to contracts in `docs/`. The last two do not — and `CLAUDE.md:7`, one of the
five rules the repository still has, says the opposite: "Track progress, tasks, experiments, and
delivery status in **GitHub Issues, not in the contracts**." Every other document's scope line
excludes progress without claiming a destination (`product.md:3`, `game-data.md:3`,
`architecture.md:3`). The old wording had the same seven-item list, but `AGENTS.md` separately
routed progress to Issues so the sentence resolved; nothing resolves it now. This is a new
contradiction between an accepted contract and the live rule file, introduced by `499df7b`.

*Correction:* "…UI behavior, implementation progress, or work tracking; the first five belong to
the other contracts in this directory, and progress and work tracking to GitHub Issues."

**R4 — the fourth new test gate is filed under the wrong heading. should-fix.**

> `testing.md:146`, under **`### UI, accessibility, sound, and haptics`**: "Verify the core test
> runner executes the approved fixtures identically on every development platform without a
> frontend."

No UI, accessibility, sound or haptic content. Its home is `### Shared core` (`:43–48`), which
already opens with "Core changes run the core test suite — rules fixtures, archive codec, library
store, and search facade — on at least one Apple platform…". This is the same misfiling class as
the `:103` defect this very commit fixed.

*Correction:* move `:146` into `### Shared core`, after `:45`.

*Nit alongside it:* the new `:144` ("Verify a game created from the pre-start draft freezes the
first-mover choice and AI level supplied at creation…") substantially overlaps `:63–64` under
`### Product and interaction`, which already cover fresh-draft, no-Settings-mutation, and
freeze-on-creation. Only the "changing either Settings default afterwards leaves the **archived**
game untouched" clause is new. Merging it into `:64` would avoid two gates drifting apart.

**R5 — the `fixtures/` rationale contradicts the one-runner rule two lines below. nit.**

> `:74`: "…both the core's test runner and **any future harness** consume it."
> `:75`: "…they standardize on **one shared C++ test runner** rather than per-platform harnesses …
> **two harnesses would make a discrepancy between them possible**."

*Correction:* "…it is the independent authority the core is validated against rather than an
artifact of the core's implementation, and the core's test runner consumes it in place rather than
copying it under `core/`."

**R6 — `interaction-design.md:416` was not given the Windows qualification. nit.**

> "The app follows the language the operating system selects for it and offers no
> interface-language control of its own, per the Settings scope in [product.md](product.md). **On
> Apple platforms** the system's per-app language setting is the place a user changes it."

`product.md:85` now covers Windows and `product.md:109` records the open question;
`interaction-design.md` still carries the unconditional statement with the Apple-only explanation
— the exact shape of round-1 S9, now fixed in one document of two.

*Correction:* append "On Windows the app follows the system's language preference list; whether
internal testers there need an in-app override is an open question in `product.md`."

**R7 — cross-document naming split. nit, pre-existing, not introduced.**
`product.md:62,80` and `game-data.md:125,151,153` say "Confirm Before Deleting";
`interaction-design.md:348,352` and `testing.md:81` say **删除前确认**, and
`interaction-design.md:414` makes Simplified Chinese the normative source copy. `game-data.md` is
now internally consistent, which is what round 1 asked for. Worth a follow-up issue, not a change
here.

---

## 5. The identity-destination question — judged

**The standing rule is sufficient. Do not restore the per-write destination check. Nothing to
raise with the user.**

> `CLAUDE.md:6`: "Write only to repositories owned by `ppppvz`. External repositories, **including
> the Fairy-Stockfish upstream**, are read-only reference: never open issues, pull requests,
> reviews, or comments there, and never push to them, unless the user asks."

Four reasons, in order of weight:

1. **The old check existed because the old rule was conditional.** `AGENTS.md` permitted external
   contributions "without the user's explicit approval, do not…" — i.e. *with* approval, yes. That
   made every remote write a case that had to be adjudicated, so a per-write destination test was
   the adjudication step. The new rule is categorical. There is no line to be on the wrong side of,
   so there is nothing for a per-write check to decide.
2. **It closes the one case where the two questions come apart.** The residual risk I was worried
   about is not "am I `ppppvz`?" but "is this remote external?" — and those diverge in exactly one
   place in this workspace: `Fairy-Stockfish/` is a `ppppvz`-owned fork with an external upstream,
   where "the repository I am in is `ppppvz`-owned" is true while `git push upstream` still writes
   outside. The current text names that case explicitly. That is better drafting than the rule it
   replaced, which named no case at all.
3. **The remaining risk is structural, not procedural.** There is no ambient default that resolves
   to an external repository: `git push` names its remote, `gh` takes `--repo`, and the workspace
   holds one read-only external checkout (`pychess-variants/`) plus the fork. A procedural
   reminder adds nothing a named remote does not already make visible.
4. **Re-adding it would repeat the mistake the user objected to** — a rule carried forward from a
   retired document because it was there, rather than because a live need was demonstrated. I
   cannot demonstrate one.

Round-1 **S1** is therefore withdrawn.

---

## 6. Observation, not a finding

Recorded because it is a consequence worth knowing, not because this PR should act on it: with
`CLAUDE.md`'s validation block removed, the only statement of what must be validated before a
change is claimed done is `docs/testing.md`, whose own status line says "Nothing in this document
is normative until its status or an individual section is explicitly marked accepted." So there is
currently no binding validation requirement anywhere. That is a consequence of an instructed
deletion, not a defect in this PR, and the right remedy is accepting `testing.md` (or sections of
it) rather than re-adding rules to `CLAUDE.md`. Raise with the user if and when core
implementation starts; nothing in this design-only PR is affected.

---

## Summary

| ID | Severity | Finding |
|---|---|---|
| B1 | **cleared** | `game-data.md:5` enumerates "the Settings placement" — real and complete |
| B2 | **cleared** | CI text moved into the accepted body, covered by "the build and CI policy"; open item correctly narrowed |
| R1 | should-fix | `architecture.md:36` still says the pre-start draft crosses the C boundary, contradicting `:35`; the fix was applied only to `game-data.md` |
| R2 | should-fix | `architecture.md:76` and `:77` conflict — CI recommended vs. builds run locally, "not a required gate" vs. "covers both"; plus the unratified CI commitment to flag |
| R3 | should-fix | `core-interface.md:3` now routes implementation progress and work tracking to "the other contracts in this directory", contradicting `CLAUDE.md:7` |
| R4 | should-fix | `testing.md:146` (core test runner) filed under **UI, accessibility, sound, and haptics** |
| R5 | nit | `fixtures/` rationale invokes "any future harness" two lines above the one-harness rule |
| R6 | nit | `interaction-design.md:416` lacks the Windows qualification `product.md:85` now carries |
| R7 | nit | "Confirm Before Deleting" vs **删除前确认** across documents (pre-existing) |
| — | nit | `### Accepted Settings placement` still nested under `## Library store schema`; `game-data.md:147` "not planned for a later one"; `testing.md:144` overlaps `:63–64` |
| S1 | **withdrawn** | the categorical `ppppvz`-only rule is sufficient; see section 5 |

Both blocking items are genuinely resolved, five of the eight round-1 should-fixes are fully
resolved, and section 2 confirms nothing dangles and nothing depends on a removed rule. What
remains is one half-applied correction and one newly introduced contradiction, both in accepted
contract text, both one line.

---

## VERDICT: DO NOT MERGE

Two one-line edits, then merge. Neither is a new opinion: R1 is the unapplied half of a correction
already accepted in round 1 — and the PR's own account ("the pre-start draft no longer 'crosses the
C boundary'") is not accurate until it lands — and R3 is a factual error introduced by `499df7b`
into an accepted contract's scope line, contradicting one of the five rules the repository still
has.

1. `docs/architecture.md:36` — replace "the two that affect a game cross the C boundary in the
   pre-start draft at creation" with "the two that affect a game are passed as arguments to game
   creation and frozen into the game."
2. `docs/core-interface.md:3` — replace "those belong to the other contracts in this directory"
   with "the first five belong to the other contracts in this directory, and progress and work
   tracking to GitHub Issues."

Optional in the same push, none blocking: R2 (fold the two CI bullets together, and confirm the
CI commitment with the product owner), R4 (move `testing.md:146` to `### Shared core`), R5, R6.

---

# Round 3 — final confirmation pass

Commit `7fda738` "Fix round-two review findings". Read-only. Working tree clean; local and
`origin/design/core-settings-and-structure` both at `7fda738`. Net diff against `main`: 8 files,
+41/−108.

## Both blocking items — cleared

**R1 — `architecture.md:36`. FIXED.**
> "…The core never reads one: the two that affect a game are **passed as arguments to game
> creation, where they are frozen into the game**."

No longer contradicts `:35` (pre-start drafts as frontend-owned transient UI state), and the
wording now matches `game-data.md:154` almost verbatim, so the two accepted contracts state the
same fact the same way. Consistent with `MxqGameConfig` at `core-interface.md:45,54`. ✅

**R3 — `core-interface.md:3`. FIXED.**
> "…engine search policy, **or UI behavior, which belong to the other contracts in this
> directory, nor implementation progress or work tracking, which belong in GitHub Issues**."

The split is correct on both sides and now agrees with `CLAUDE.md:7`. ✅

## The three should-fix / nit items — cleared

**R2 — the CI bullets. FIXED, and better than the correction I proposed.**
> ":76": "Builds run on developer machines while the project is Apple-only… When Windows
> implementation begins, GitHub Actions CI covers **both** a macOS runner and a Windows runner…"
> ":77": "CI must not receive undocumented inputs… It remains **a convenience rather than a merge
> gate**; what it guarantees is that **every platform is buildable somewhere other than one
> developer's machine**."

The contradiction is gone at the root: the "recommended to run on GitHub Actions CI" clause that
conflicted with "builds run on developer machines" was deleted rather than patched around, and
"not a required gate" was sharpened to "not a **merge** gate", which is genuinely compatible with
the coverage commitment beside it — CI can cover both platforms without blocking a merge. The
restated guarantee is the substantive claim, not a slogan. Nothing normative was lost with the
dropped "long or large builds" enumeration; the new bullets are unconditional where it was
advisory. ✅

**R4 — the core-test-runner gate. FIXED.** Now `testing.md:46`, directly under `### Shared core`
beside the existing core-test-suite gate, and reworded to "the **one shared** core test runner",
which ties it to `architecture.md:75`. Removed from the UI block. ✅

**R6 — `interaction-design.md:416`. FIXED.** "…on Windows the app follows the system's language
preference list", matching `product.md:85`; the sentence still routes to `product.md`, where the
open question lives. ✅

**R5 — the `fixtures/` rationale. FIXED.** "…it is the independent authority the core is validated
against, **not an implementation detail of the core it validates**." The "any future harness"
phrase that sat against the one-harness rule is gone, and the replacement states the actual reason
for the placement. ✅

## Nothing new broke

- Full-tree sweep for `AGENTS`/`CLAUDE`: still exactly one hit, `CLAUDE.md:3` → `../CLAUDE.md`,
  which exists and owns all four areas it names. No dangling references.
- `game-data.md:5` still enumerates "the Settings placement"; the round-3 commit did not touch
  `game-data.md`, `product.md` or `CLAUDE.md`.
- The round-3 diff is confined to the six regions reported. No collateral edits.
- Remaining items are the ones already recorded as non-blocking and unchanged: R7 (the
  "Confirm Before Deleting" / **删除前确认** split across documents, pre-existing), the `###`
  nesting of `Accepted Settings placement` under `## Library store schema`, `game-data.md:147`
  "not planned for a later one", and the `testing.md:145` / `:63–64` overlap. None warrant holding
  the PR; R7 is worth a follow-up issue.
- Identity-destination: withdrawn in round 2, confirmed not restored. `CLAUDE.md:6` is unchanged.

## FINAL VERDICT: MERGE
