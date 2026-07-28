# Pre-merge review — PR #20 `design/core-settings-and-structure`

Independent adversarial review standing in for human review. Read-only: nothing in
`MiniXiangqi/` was modified, and nothing was written to GitHub.

**Under review:** commit `576a9be` "Accept Settings placement, the core test runner, and the
restructure", 7 files, +86/−103. Branch is up to date with `main`; `mergeStateStatus: CLEAN`.

**Sources used**

- `git diff main...design/core-settings-and-structure` and `git show main:AGENTS.md`
  (repository `AGENTS.md`, recovered in full).
- Workspace `/Users/tianren/coding/minixiangqi/AGENTS.md`: **never in any repository**, and
  already deleted from disk. It was recovered verbatim from this session's project-instruction
  context, which was captured before the deletion and still carries the file under the heading
  `Contents of /Users/tianren/coding/minixiangqi/AGENTS.md`. That text is treated as
  authoritative below; where a claim rests on something not in it, it is marked unverifiable.
- `gh pr view 20`, `gh issue view 2` (identity confirmed `ppppvz`, read-only).

---

## 1. The `AGENTS.md` consolidation

### 1a. Repository `AGENTS.md` → `MiniXiangqi/CLAUDE.md` — clause-by-clause

Legend: **MOVED** = same rule, same force, new home. **CHANGED** = force or content differs
(both quoted). **DROPPED** = no longer stated in the repository. `WS` = workspace
`/Users/tianren/coding/minixiangqi/CLAUDE.md`; `RE` = repository `MiniXiangqi/CLAUDE.md`.

| # | Old repository `AGENTS.md` clause | Disposition | Now at |
|---|---|---|---|
| H | "This document is for coding agents working inside the `MiniXiangqi` app repository… defines the workspace, identity, toolchain, project-setting, documentation-routing, and validation rules… A parent `../AGENTS.md`, **when present**, also applies." | **CHANGED** | `RE:3` — "It defines the **identity, toolchain, project-setting, documentation-routing, change, and validation** rules… The parent `../CLAUDE.md` **also applies and owns** the workspace boundary, the authorization limits, the Apple toolchain, and the GitHub identity rules." Parent goes from *optional* to *load-bearing*; "workspace" leaves the repository's own list. See **S3**. |
| W1 | "Treat `/Users/tianren/coding/minixiangqi` as the only authorized project workspace. Do not create or configure project materials outside it without the user's explicit authorization." | **DROPPED from repo** (kept workspace-side) | `WS:7–10` |
| W2 | "Use only the project's dedicated GitHub identity, `ppppvz`, for this repository." | **DROPPED from repo** | `WS:35` |
| W3 | "Before GitHub CLI use or Git remote operations, source `.git/minixiangqi-control/activate.zsh` or reproduce its isolated environment exactly." | **DROPPED from repo / CHANGED path** | `WS:36` — "Source `MiniXiangqi/.git/minixiangqi-control/activate.zsh`". Repo-relative form no longer exists anywhere. See **N3**. |
| W4 | "Never use the system GitHub CLI identity, global Git configuration, default SSH identity, a connector authenticated as another account, or a browser session authenticated as another account." | **DROPPED from repo** | `WS:37` (verbatim in substance) |
| W5 | "Write Git configuration only to this repository's `.git/config`." | **DROPPED from repo** | `WS:38` ("the relevant repository's local `.git/config`") |
| W6 | "Before every remote write, **verify through the project-scoped configuration** that the active identity is `ppppvz` **and the destination is a `ppppvz` repository**." | **CHANGED — weakened** | `WS:39` — "Confirm the active identity is `ppppvz` before every remote write. If identity or destination is uncertain, stop and ask." The affirmative destination check and the named verification mechanism are gone. See **S1**. |
| W7 | "Do not write to an external upstream repository or create external issues, pull requests, discussions, reviews, or comments without the user's explicit authorization." | **CHANGED — strengthened; DROPPED from repo** | `WS:23` — "**Never** write to a repository the `ppppvz` account does not own." Approval gate removed in favour of an absolute ban. Not restated in `RE`. |
| P1 | Platform targets iOS/iPadOS/macOS/Windows, one C++ core, native frontend per platform. | **MOVED** | `RE:7` (verbatim) |
| P2 | "Apple platforms are implemented first. The Windows toolchain is not yet pinned; do not invent one silently." | **MOVED** | `RE:8` (verbatim) |
| A1 | "Use Xcode 27 beta at `/Applications/Xcode-beta.app`." | **DROPPED from repo** | `WS:28` |
| A2 | "Set `DEVELOPER_DIR=…` or invoke tools through that developer directory explicitly." | **DROPPED from repo** | `WS:29` |
| A3 | "Verify build `27A5228h` before building or testing. If it is unavailable or does not match, stop and report the mismatch instead of using another Xcode." | **DROPPED from repo / split** | Version + stop-and-report at `WS:30`; timing only at `RE:63` ("verify **the required Xcode version**" — number no longer stated in the repository). See **S4**. |
| A4 | "Do not rely on the system-selected Xcode or change the global `xcode-select` setting." | **CHANGED — strengthened; DROPPED from repo** | `WS:31` — "**Never** rely… and **never** change…" |
| A5 | "Preserve Swift 6." | **CHANGED** | `RE:19` — becomes a bullet in the *Fixed project settings* list rather than an Apple-toolchain imperative. Force is comparable. |
| S0 | "**Discuss the exact change with the user before modifying:**" | **CHANGED** | `RE:12` — "The following are settled values, not defaults to revisit. Preserve them through any change, including the repository restructure, and **raise it with the user rather than changing one in passing**." Admitted in the PR body. |
| S1 | app / unit-test / UI-test bundle identifiers | **MOVED** | `RE:14` |
| S2 | development team `7P9PPXP2SF`, signing, entitlements | **MOVED** | `RE:15` |
| S3 | iOS/iPadOS/macOS 26.5 deployment targets | **MOVED** | `RE:16` |
| S4 | supported iPhone, iPad, macOS platforms | **MOVED** | `RE:17` |
| S5 | the `x86_64` exclusion | **MOVED** | `RE:18` |
| S6 | "**target structure or platform configuration**" | **DROPPED — not admitted** | Only `RE:21` — "Relocating the Xcode project under `apple/` is authorized, and target and platform configuration may change **only as far as that relocation requires**." That scopes the *relocation*; it restores no rule for target-structure changes outside it. See **S2**. |
| S7 | "Do not delete ignored build products, `.DS_Store`, or Xcode user data as incidental cleanup." | **MOVED** | `RE:21` (verbatim) |
| G1 | Do not infer decisions from the `Item`/`ContentView`/`ModelContainer` scaffold. | **MOVED** | `RE:25` |
| G2 | Preserve the fully offline boundary; networking/accounts/cloud/analytics need explicit discussion. | **MOVED** | `RE:26` |
| G3 | Preserve the single-main-window boundary. | **MOVED** | `RE:27` |
| G4 | Rules facade is the runtime authority; frontends must not reimplement; search never commits a result. | **MOVED** | `RE:28` |
| G5 | "Never commit NNUE network bytes to this repository." | **MOVED** | `RE:29` |
| C0 | "Read the relevant contract before changing behavior:" | **MOVED** | `RE:33` (with a new design-first sentence folded in from the old repo `CLAUDE.md`) |
| C1–C8 | Routing list: `product.md`, `interaction-design.md`, `xiangqi-rules.md`, `architecture.md`, `core-interface.md`, `game-data.md`, `engine-integration.md`, `testing.md` | **MOVED** | `RE:35–42` (verbatim, all eight) |
| D1 | "In a living target contract, content outside `Need to discuss` is accepted intended behavior unless it explicitly says otherwise." | **MOVED** | `RE:46` |
| D2 | "A document marked `Draft` is a proposal as a whole and does not authorize implementation unless a section is explicitly marked accepted." | **MOVED** | `RE:47` |
| D3 | "A partially accepted document must state exactly which sections are accepted." | **MOVED** | `RE:48` — and **violated by this same PR**; see **B1**. |
| D4 | "`Need to discuss` is always non-normative and does not authorize implementation choices." | **MOVED** | `RE:49` — and **violated by this same PR**; see **B2**. |
| CH1 | "Update an accepted contract and its tests in the same change that alters the corresponding behavior." | **MOVED** | `RE:55` — **not complied with by this PR**; see **S5**. |
| CH2 | Never describe target-MVP behavior as implemented without source and tests. | **MOVED** | `RE:56` |
| CH3 | Track progress/tasks/experiments/status in Issues or CI artifacts. | **MOVED** | `RE:57` |
| CH4 | Fairy-Stockfish build/patch/upstream-sync instructions stay in that repository. | **MOVED** | `RE:58` |
| CH5 | "Treat third-party repositories and imported game files as untrusted inputs." | **MOVED** | `RE:59` |
| V1–V6 | Validation: Xcode first; smallest focused tests then platform checks; UI form-factor + accessibility; game-data persistence/relaunch/migration/deletion/malformed-import/round-trip; rules-or-engine conformance/illegal-move/cancellation/stale-result; report exact commands and keep the matrix in `testing.md`. | **MOVED** | `RE:63–68` (verbatim, all six) |

Additions with no `AGENTS.md` antecedent (all benign, all sourced from the old repo
`CLAUDE.md`): the design-first sentence at `RE:33`, and `RE:51` "Open product and engineering
questions live in those `Need to discuss` sections and in GitHub Issues — see issue #2".
Issue #2 exists and is open ("Design: resolve remaining MVP product decisions").

### 1b. Workspace `AGENTS.md` → workspace `CLAUDE.md`

| # | Old workspace `AGENTS.md` clause | Disposition | Now at |
|---|---|---|---|
| 1 | "Treat `/Users/tianren/coding/minixiangqi` as the only authorized workspace." | MOVED | `WS:7` |
| 2 | "Do not create, install, or configure project materials outside this workspace… dependencies, caches, credentials, configuration, helper tools, and temporary artifacts." | MOVED | `WS:8` |
| 3 | "Do not change system-wide or user-wide configuration… **unless the user has explicitly authorized that exact action**." | CHANGED — **strengthened** | `WS:9` + `WS:24` — escape hatch removed; "**Never touch system configuration.**" |
| 4 | "If the best solution requires anything outside the workspace, stop and ask… first." + "Do not choose an inferior workaround merely to avoid requesting authorization." | MOVED (merged) | `WS:10` |
| 5–8 | Apple toolchain: beta path, `DEVELOPER_DIR`, no system Xcode / no global `xcode-select` change (was conditional), expected build `27A5228h` + stop-and-report. | MOVED; clause 7 strengthened | `WS:28–31` |
| 9–13 | Identity isolation: `ppppvz` only; source `activate.zsh`; never system gh/global git/default SSH/other-account connector or browser; write git config only to the repository's local `.git/config`; confirm identity before remote writes. | MOVED, except: **"Never modify system or global Git configuration"** folded into the general system-config ban (`WS:9`/`WS:24`), and the **destination check dropped** | `WS:35–39`. See **S1**. |
| 14 | "In repositories owned by `ppppvz`, agents may make in-scope commits and pushes without requesting additional approval." | CHANGED — **widened** | `WS:16–19` now also allow managing branches/worktrees, creating/editing/commenting/closing issues and PRs, and "**merge a pull request once an independent agent review has passed and confidence is high**". See **N6**. |
| 15 | "Without the user's explicit approval, do not open, submit, or modify issues, pull requests, discussions, reviews, comments, or other contributions in repositories owned by anyone other than `ppppvz`." | CHANGED — **strengthened** | `WS:23` (absolute) |
| 16 | "Do not push branches, commits, or tags to an external upstream repository. External repositories may be read or fetched only as reference material." | MOVED | `WS:23` |
| 17 | "Never use an external write as a workaround for local work, testing, or CI." | MOVED | `WS:23` |

Orientation content from the old workspace `CLAUDE.md` is carried over correctly, including the
removal of `AGENTS.md` from the source-of-truth list (`WS:43`) and the NNUE never-commit rule
(`WS:48`).

### Findings for item 1

**S1 — the remote-write destination check was dropped. should-fix (near-blocking).**

> Old (repository `AGENTS.md`): "Before every remote write, verify through the project-scoped
> configuration that the active identity is `ppppvz` **and the destination is a `ppppvz`
> repository**."
>
> New (`WS:39`): "Confirm the active identity is `ppppvz` before every remote write. If identity
> or destination is uncertain, stop and ask."

The old rule required an affirmative check of *both* identity and destination before every
remote write. The new rule requires an affirmative check of identity only, and reduces the
destination to a conditional ("if… uncertain"). An agent that is confident and wrong now performs
no destination check at all. This is precisely the safeguard against the one irreversible action
in this workspace — a push or a published contribution to an external repository, which cannot be
un-published. `WS:23` bans the *outcome* absolutely, but the *procedure* that would have caught
the mistake before it happened is what was removed. The PR body says "One substantive change
rather than a move: the protected-settings list…" — that admission is **incomplete**; this is a
second substantive change, and it weakens a destructive-action guard.

*Correction:* restore the affirmative check in `WS:39`:
"Before every remote write, confirm through the project-scoped configuration both that the active
identity is `ppppvz` and that the destination repository is owned by `ppppvz`. If either is
uncertain, stop and ask."

**S2 — "target structure or platform configuration" left the protected list with no replacement.
should-fix.**

> Old: protected list item — "target structure or platform configuration."
> New (`RE:21`): "Relocating the Xcode project under `apple/` is authorized, and target and
> platform configuration may change only as far as that relocation requires."

The new sentence scopes *the relocation*. It does not reinstate any rule for target-structure or
platform-configuration changes that are **not** part of the relocation — adding, removing or
renaming targets, changing build configurations, altering platform sets after the move. Before
this PR those required discussion; after it, and after the relocation lands, nothing governs them.
The PR body describes the change as turning "a list of things to ask about" into "fixed values to
preserve" and mentions target/platform configuration only inside the relocation carve-out, so the
loss of the general protection is not admitted.

*Correction:* add to the `RE` "Fixed project settings" section, after the relocation sentence:
"Any other change to target structure or platform configuration is discussed with the user first."

**S3 — the repository is no longer self-contained. should-fix.**

> `RE:3`: "The parent `../CLAUDE.md` **also applies and owns the workspace boundary, the
> authorization limits, the Apple toolchain, and the GitHub identity rules**."

`../CLAUDE.md` is `/Users/tianren/coding/minixiangqi/CLAUDE.md` — outside the repository and not
tracked by it. The old repository `AGENTS.md` deliberately restated identity isolation and the
Apple toolchain in-repo and treated the parent as optional ("A parent `../AGENTS.md`, **when
present**, also applies"). After this PR, a clone of `ppppvz/MiniXiangqi` contains no statement
of the workspace boundary, the external-write ban, the Xcode version, or the `ppppvz` identity
procedure, and `RE:3` asserts the existence of a file that will not be there. Four rule families
that the PR body lists as "preserved" are preserved only outside the repository.

*Correction:* either (a) keep a short "Identity and toolchain" section in `RE` restating W2, W3,
W6, W7 and A1–A4 as the repository's own copy, or (b) change `RE:3` to "A parent `../CLAUDE.md`,
when present, also applies and owns…" and add a one-line note that outside that workspace those
rules must be supplied by the operator.

**S4 — `RE:63` references an Xcode version the repository no longer states. should-fix.**

> `RE:63`: "For Apple work, verify **the required Xcode version** before other validation."

`27A5228h` was stated in `AGENTS.md § Apple toolchain`; it is now only in `WS:30`, `README.md`,
and `docs/testing.md`. The rule file that issues the instruction no longer defines its object.

*Correction:* append to `RE:63`: "— Xcode 27 beta at `/Applications/Xcode-beta.app`, expected
build `27A5228h`, per `README.md` and `docs/testing.md`; stop and report a mismatch."

**N3 — `activate.zsh` path is no longer usable from inside the repository. nit.**
`WS:36` gives `MiniXiangqi/.git/minixiangqi-control/activate.zsh`; the repo-relative form
`.git/minixiangqi-control/activate.zsh` (old `AGENTS.md` W3 and the old repo `CLAUDE.md`) was
deleted. An agent whose cwd is the repository will follow a path that does not resolve.
*Correction:* write `WS:36` as "`<workspace>/MiniXiangqi/.git/minixiangqi-control/activate.zsh`
(`.git/minixiangqi-control/activate.zsh` from inside the repository)".

**N6 — the widened authorization is not what the PR body describes. nit.**
`WS:16–19` newly authorize managing branches/worktrees, creating and closing issues and PRs, and
merging PRs after an independent agent review. The PR body characterizes the permission change
only as "it required approval for work the user has since authorized". The merge authority in
particular is a new capability, and `WS:21` claims the two remaining limits were "restated by the
user on 2026-07-27" — a claim I cannot verify from any artifact in the repository. It is
consistent with the stored workflow preference (self-merge on `ppppvz` repos after an Opus agent
check), so I do not treat it as a defect, but the PR body under-describes it.

**Nothing else was lost.** Every clause of the repository `AGENTS.md` other than S6 survives
somewhere; every clause of the workspace `AGENTS.md` survives, three of them strengthened.

---

## 2. Dangling references

Swept the repository (all tracked files) and the workspace, excluding `discussion-drafts/`,
`pychess-variants/`, `agent-guidance-references/`, and `Fairy-Stockfish/`.

- Repository: the only surviving `AGENTS` string is the historical note in `RE:3`. `README.md`,
  `docs/*.md`, `.gitignore`, and `fixtures/` are clean. No surviving `@AGENTS.md` import.
- Workspace: only the equivalent historical note in `WS:3`. The workspace `AGENTS.md` file is
  gone from disk.
- `grep -rni "protected.settings"` across `docs/`, `README.md`, `CLAUDE.md`: no hits. The old
  `architecture.md` phrase "the protected-settings review in `AGENTS.md`" was the only one and it
  is gone.

**Repointed reference 1 — `docs/core-interface.md:3`: ACCURATE.**
> "those belong to the documents in [CLAUDE.md](../CLAUDE.md)'s canonical list."

From `docs/`, `../CLAUDE.md` resolves to `MiniXiangqi/CLAUDE.md`, which does contain
`## Canonical documentation` listing all eight contracts. The referenced topics (rules,
persistence schemas, archive serialization, engine search policy, UI behavior) all map onto
entries in that list; "implementation progress… work tracking" is covered by `RE:51`/`RE:57`,
exactly as it was under `AGENTS.md`.

**Repointed reference 2 — `docs/architecture.md:74`: ACCURATE in content, sloppy in form.**
> "The fixed project settings listed in `CLAUDE.md` — bundle identifiers, development team,
> signing, entitlements, deployment targets, supported platforms, the `x86_64` exclusion, and
> Swift 6 — are preserved through it"

All six `RE:14–19` bullets are enumerated, in order, with nothing added or omitted. **N1 (nit):**
`CLAUDE.md` is bare text while every other cross-reference in `architecture.md` is a markdown link
(`[game-data.md](game-data.md)`, `[core-interface.md](core-interface.md)`); read relative to
`docs/` it points at a non-existent `docs/CLAUDE.md`. *Correction:* `[CLAUDE.md](../CLAUDE.md)`.
The same applies to `` `product.md` `` in `docs/game-data.md:156`.

**N2 (nit):** `../CLAUDE.md` now denotes two different files depending on which document says it
— the workspace file when written in `RE:3`, the repository file when linked from `docs/`. Worth
one disambiguating word in `RE:3` ("the workspace-level `../CLAUDE.md`").

---

## 3. The Settings decision's consistency

**The central claim survives testing.** I checked the C interface and every accepted behaviour
that depends on a preference:

- `grep -ni "setting|preference" docs/core-interface.md` returns **zero hits**, confirming the PR
  body's premise. There is no settings function and no settings-shaped parameter anywhere in the
  53-function inventory.
- **First-mover choice and AI level:** `MxqGameConfig` (`core-interface.md:45`) carries
  `MxqPlayMode`, resolved `human_side`, `first_mover_choice`, `ai_level`, `ai_movetime_ms`; the
  frontend supplies all of them at `mxq_game_create`. Random is resolved before creation
  (`core-interface.md:251` — "prepare → resolve → create → search"; `game-data.md:90`). The core
  never sees a default. ✅
- **删除前确认:** `mxq_store_history_delete(MxqCore*, uint64_t record_id, MxqError*)` has no
  confirmation parameter, and `game-data.md:125` already said "Once the accepted UI policy
  authorizes deletion, the core removes the whole History record." The frontend gates; the core
  executes. **No contradiction with "local app state"** — that phrase and "each platform's own
  preference system" are compatible, and the enforcement point is unchanged by this PR. ✅
- **Sound and haptics:** frontend-owned since `architecture.md:32`. `interaction-design.md:397`
  agrees. ✅
- **Piece style and symbols:** presentation only; `interaction-design.md:61,89` and
  `testing.md:156` all state that they do not touch game content, archives, or notation. ✅

I found **no accepted behaviour that would require the core to read a preference.** The decision
is sound. Three defects are in the supporting text.

**S6 — the characterization of 删除前确认 is false. should-fix.**
> `game-data.md:153`: "No preference is correctness-critical: **five are presentation or device
> capability**, and the two that affect a game are read only when one is created."

The five must be 删除前确认, sound, haptics, piece style, piece symbols. 删除前确认 is neither
presentation nor device capability: it is the only guard on a permanent, irreversible deletion —
`product.md:62` "A completed deletion is permanent: the target MVP has neither deletion Undo nor
Recently Deleted." Since the ownership rule stated one line above is the entire justification for
the placement, a false premise here matters even though the conclusion happens to hold (it holds
because the *enforcement* is a UI flow, not because the preference is presentational).

*Correction:* "No preference is correctness-critical: four are presentation or device capability,
删除前确认 gates a frontend confirmation flow that the core neither sees nor needs — the core's
delete operation is unconditional either way — and the two that affect a game are read only when
one is created."

**S7 — "outside the game archive" collides with the accepted archive format. should-fix.**
> `game-data.md:157`: "Preferences are outside the game archive and outside export and import. A
> file moved between platforms never carries them."

`game-data.md:38` lists `ai_level` and `first_mover_choice` as `content` members of archive
version 1, and `game-data.md:48` fixes their vocabularies. Two of the seven named preferences
therefore appear in every exported human-versus-AI file, under the same names. The intended
statement — that the *Settings default* is not archived, only the per-game frozen value — is
correct, but as written two accepted sections of one document appear to contradict each other.

*Correction:* "The Settings defaults are outside the game archive and outside export and import.
What an archive carries is the per-game value frozen at creation (`first_mover_choice`,
`ai_level`, `ai_movetime_ms`), never the preference it was copied from; importing a file never
changes a Settings default."

**S8 — "the pre-start draft crosses the C boundary" contradicts three accepted statements.
should-fix.**
> `architecture.md:36`: "…the two that affect a game cross the C boundary **in the pre-start
> draft** at creation."
> `game-data.md:154`: "**The pre-start draft** already carries the first-mover choice and AI level
> **across the C boundary** at game creation…"

`architecture.md:35` — one line above — lists "pre-start drafts" among the **frontend-owned
transient UI state**; `game-data.md:76` calls the pre-start destination "transient in-memory
state"; `game-data.md:87` says "Neither mode's pre-start state is written to the store or a game
archive." The draft does not cross the boundary. `MxqGameConfig` does, at `mxq_game_create`.

*Correction:* in both places, "…the two that affect a game are passed explicitly in
`MxqGameConfig` at `mxq_game_create`, copied out of the frontend's in-memory draft."

**S9 — the no-language-control decision is justified for Apple but applied to every platform.
should-fix.** Covered under item 5.

---

## 4. Status-line accuracy (`architecture.md`)

> New: "…The repository layout, the relocation of the Xcode project, the placement of Settings
> preferences, and the core test-runner decision below are also accepted."

- The removed clause ("The repository restructuring steps remain draft until reviewed") is
  correctly retired: `architecture.md:74` now carries the authorization. ✅
- After this PR every section of `architecture.md` outside **Need to discuss** is accepted, and
  the status line no longer marks anything draft. I found nothing left in the document that
  should still be draft. ✅
- **Nothing draft is relied on as accepted** — with one exception, which runs the other way:
  `architecture.md`'s status line accepts "the placement of Settings preferences", but
  `architecture.md:36` defers the substance to `game-data.md`, whose own status line does **not**
  accept it. See **B1**. The chain `product.md:87 → game-data.md → (unaccepted)` and
  `architecture.md:36 → game-data.md → (unaccepted)` both terminate in nothing.
- **Removing "Whether core tests standardize on one framework or per-platform runners" is
  justified.** `architecture.md:75` answers it directly and completely: one shared C++ runner for
  core tests, native frameworks for binding tests, with the reason (the fixtures are the
  independent authority, so two harnesses could disagree). ✅

**N5 — the follow-on question is now recorded nowhere. nit.** The old bullet asked *whether* one
framework; the answer is "one shared C++ test runner", but *which* C++ framework (GoogleTest,
Catch2, doctest, …) is now neither accepted nor listed as open. It vanished with the bullet.
*Correction:* add to `architecture.md`'s **Need to discuss**: "Which C++ test framework the shared
core runner uses, and how the approved `fixtures/rules/` JSON is driven from it."

**S10 — the newly accepted layout omits `fixtures/`. should-fix.**
> `architecture.md:66–72`: `core/`, `apple/`, `windows/`, `docs/`.

`fixtures/rules/` sits at the repository root today and is cited by three accepted or normative
references: `xiangqi-rules.md:5` (inside its **accepted** status line, as
`[fixtures/rules/](../fixtures/rules/)`), `xiangqi-rules.md:83`, `testing.md:86`, and
`README.md:45`. While the layout was draft the omission was harmless; now that the relocation is
authorized to proceed "before core implementation begins" without further review, an implementer
has no accepted answer to whether `fixtures/` stays at the root or moves under `core/` — and
moving it silently breaks an accepted link in another contract's status line.

*Correction:* add `├── fixtures/  # approved rules fixtures, path-stable` to the tree, or state in
`architecture.md:74` that `fixtures/` remains at the repository root through the relocation.

---

## 5. Document-status discipline

**B1 — `game-data.md`'s status line was not updated to accept the new section. BLOCKING.**
> `game-data.md:5` (**unchanged by this PR**): "**Status: Partially accepted data contract.** The
> core-owned SQLite storage direction, the save-before-mode behavior, the pre-start behavior, the
> MVP record behavior, the archive format version 1, the serialized identifier vocabulary, content
> equivalence and import validation, the store schema version 1, and the migration and
> compatibility promise below are accepted."
>
> `CLAUDE.md:48` (restated by this very PR): "A partially accepted document **must state exactly
> which sections are accepted**."

`### Accepted Settings placement` (`game-data.md:149`) is not in that list. Every other accepted
section of this document follows the pattern — "### Accepted archive format, version 1" ↔ "the
archive format version 1", "### Accepted serialized identifier vocabulary" ↔ "the serialized
identifier vocabulary", and so on. The new section is the only `### Accepted …` heading with no
status-line entry, so under the document's own governing rule it is a self-declared acceptance in
a document whose acceptance is enumerated elsewhere. This matters beyond formalism: `product.md:87`
and `architecture.md:36` both make `game-data.md` the fixing authority, so the entire Settings
decision rests on a section its own document has not accepted.

*Correction:* in `game-data.md:5`, insert "the Settings placement," after "the store schema
version 1,".

**B2 — a fifth decision is smuggled in as "accepted" inside `Need to discuss`. BLOCKING.**
> `architecture.md:82`: "Windows toolchain pinning for the core and frontend, and the CI matrix
> that builds all platforms. **The accepted direction is that builds run locally until Windows
> work begins, and that CI then covers both a macOS 26 runner and a Windows runner;** the exact
> matrix and pinning remain open."
>
> `CLAUDE.md:49` (restated by this very PR): "`Need to discuss` is **always non-normative and does
> not authorize implementation choices**."

Three separate problems:

1. It is self-contradictory: text calling itself "the accepted direction" sits in the one section
   the rules define as never normative. Either it is accepted and belongs above the heading, or it
   is not and must not say "accepted".
2. It is not covered by the status line, which enumerates what is accepted and does not mention a
   CI-runner direction.
3. **It is a fifth decision.** The four confirmed with the product owner are Settings placement,
   the core test runner, the restructure promotion, and no interface-language control. The PR body
   describes no CI decision at all — the section headings are "Settings preferences live with each
   platform", "Core tests use one shared C++ runner", "The repository restructure is accepted, not
   draft", "No interface-language control", "AGENTS.md is retired". A named macOS-26 runner and a
   Windows runner, plus "builds run locally until Windows work begins", is new accepted content
   that nobody signed off, and it sits in tension with the accepted `architecture.md:76`
   ("Long or large builds… are recommended to run on GitHub Actions CI… CI is a convenience").

*Correction:* delete the added sentence, restoring the bullet to "Windows toolchain pinning for
the core and frontend, and the CI matrix that builds all platforms." If the direction is real,
raise it separately and put it above the **Need to discuss** heading with a status-line entry.

**S9 — the interface-language decision widens silently past its own justification. should-fix.**
> Deleted from `product.md`'s **Need to discuss**: "Decide whether the app needs its own
> interface-language control **on any platform**, given that Apple platforms already provide a
> per-app language setting."
>
> New `product.md:85`: "It also holds no interface-language control: the app follows the language
> the operating system selects for it, **which on Apple platforms is already a per-app setting the
> system provides**."
> New `interaction-design.md:416`: "**On Apple platforms** the system's per-app language setting is
> the place a user changes it."

The deleted question explicitly asked "on any platform". The answer given is unconditional — no
control anywhere — but the justification is stated for Apple only, and both new sentences say so
in the same breath. `product.md:23` and `README.md` commit the product to Windows 11 / Windows 10
1809, and `product.md:24` requires identical product behavior across platforms. Nothing in either
document says what a Windows user does when the OS display language is not the one they want the
app in. The `Need to discuss` item was removed without the diff resolving the part of it that
concerned non-Apple platforms.

*Correction:* either add to `product.md:85` "On Windows the app follows the system's display
language; whether that is sufficient is settled when the Windows frontend is designed", or leave a
narrowed bullet in **Need to discuss**: "Whether Windows needs an in-app interface-language control,
given that the Apple per-app setting has no direct Windows equivalent."

**Everything else newly stated as accepted checks out.** `product.md:87`, `architecture.md:36`,
`architecture.md:74–75`, and `game-data.md:149–157` are all direct restatements of the four
confirmed decisions. `RE`'s reframed Fixed project settings is admitted in the PR body (with the
S2 gap). Nothing else was silently promoted.

**N4 — one silent narrowing. nit.**
> Old `game-data.md`: "Local preferences are not in schema version 1; **if** Settings preferences
> land in the shared store, a key-value table is a purely additive migration."
> New (`:147`): "Local preferences are not in schema version 1 **and are not planned for a later
> one**…"

That forecloses a future schema version rather than merely recording where preferences live. The
following sentence ("Should that ever be revisited…") mostly repairs it; a reader could still take
"not planned for a later one" as a commitment nobody made. *Correction:* "…are not in schema
version 1: they live with each platform, per the accepted placement below."

---

## 6. Cross-document consistency

**Settings text agrees across the four documents.** `product.md:87`, `game-data.md:149–157`,
`architecture.md:36`, and `interaction-design.md` (which describes the Settings groups at
`:180`, `:348`, `:397` and asserts no placement) are mutually consistent. The count is right:
`product.md:78–83` lists exactly seven preferences and `game-data.md:151` names the same seven.
`engine-integration.md:55` ("Setup changes never alter the persistent Settings default") also
agrees. The only intra-document defect is naming:

**S11 — `game-data.md` now names the same preference two ways, 26 lines apart. should-fix.**
> `:125` "The **Confirm Before Deleting** preference is local app state…"
> `:151` "…the default AI level, **删除前确认**, the sound and haptics toggles…"

`interaction-design.md:348,352` and `testing.md:81` use 删除前确认;
`product.md:62,80` and `game-data.md:125` use "Confirm Before Deleting".
`interaction-design.md:414` makes Simplified Chinese the source language and its accepted copy
normative, so 删除前确认 is the correct term. The mismatch pre-dates this PR across documents, but
this PR is what introduced it *inside a single document*.
*Correction:* change `game-data.md:125` to 删除前确认 (and, ideally in the same pass,
`product.md:62,80`).

**S5 — `testing.md` should have been updated in this PR and was not. should-fix
(change-discipline violation).**

`git diff main...design/core-settings-and-structure -- docs/testing.md` is empty.

> `testing.md:103`, under **`### Game data`**: "Test pin-state and **delete-confirmation
> preference persistence**, History sorting, replay, permanent deletion, deletion failure
> rollback, ended-early records, confirmed resignation, and immutable game content."

`### Game data` is the change-to-validation block for the core-owned store: every other item in it
is a store or archive invariant, and it opens with "Test the single-active-game invariant… atomic
old-game archive-and-clear operation". Filing delete-confirmation *preference persistence* there
asserts that the preference is game-data state — which is exactly what this PR decides it is not.
It belongs with `testing.md:142–143`, where piece-style, sound, haptics and piece-symbols
persistence already live under **UI, accessibility, sound, and haptics**.

The PR also adds no gate for any of its four decisions: nothing verifies that preferences persist
through each platform's own preference system and survive relaunch there, that no preference is
written to the store, that export/import carries no preference, or that the app has no
interface-language control and follows the system language.

> `CLAUDE.md:55` (restated by this very PR): "Update an accepted contract and its tests in the
> same change that alters the corresponding behavior."

`game-data.md` is an accepted contract and this PR alters it. `testing.md`'s draft status does not
exempt it: it is where `CLAUDE.md:68` says the gate matrix lives, and the repository's own
precedent is to update it in the same commit — `5286480`, `028e82d` and `e1e6420` on the last
merged design PR all did. **This PR does not comply with its own change-discipline rule.**

*Correction:* move "delete-confirmation preference persistence" out of `testing.md:103` into the
`:143` bullet, and add under **UI, accessibility, sound, and haptics**: "Verify every Settings
preference is stored in the platform's own preference system, survives relaunch and app update,
is registered with the accepted defaults on a clean install, is absent from the library store, and
is neither exported nor imported by a game file. Verify the app has no interface-language control
and follows the language the operating system selects for it."

---

## Summary

| ID | Severity | Finding |
|---|---|---|
| B1 | **blocking** | `game-data.md:5` status line does not accept `### Accepted Settings placement`; `product.md` and `architecture.md` both defer to it |
| B2 | **blocking** | `architecture.md:82` states an unratified fifth decision ("The accepted direction is…") inside **Need to discuss** |
| S1 | should-fix | remote-write **destination** check dropped; PR body's "one substantive change" admission is incomplete |
| S2 | should-fix | "target structure or platform configuration" dropped from protected settings with no rule outside the relocation |
| S3 | should-fix | repository no longer self-contained: identity, toolchain, boundary and authorization live only in an untracked parent file |
| S4 | should-fix | `RE:63` cites "the required Xcode version" that the repository's own rule file no longer states |
| S5 | should-fix | `testing.md` untouched; `:103` files delete-confirmation persistence under **Game data**; no gates for the four new decisions; violates `CLAUDE.md:55` |
| S6 | should-fix | `game-data.md:153` calls 删除前确认 "presentation or device capability"; it guards a permanent deletion |
| S7 | should-fix | `game-data.md:157` "outside the game archive" collides with `:38`, which archives `first_mover_choice` and `ai_level` |
| S8 | should-fix | `architecture.md:36` / `game-data.md:154` say the pre-start draft crosses the C boundary; `:35`, `game-data.md:76,87` say it is frontend-only |
| S9 | should-fix | no-interface-language decision applied to every platform on an Apple-only justification; deleted question said "on any platform" |
| S10 | should-fix | newly accepted layout tree omits `fixtures/`, whose path three accepted references depend on |
| S11 | should-fix | `game-data.md` names 删除前确认 two ways, at `:125` and `:151` |
| N1 | nit | `architecture.md:74` `CLAUDE.md` unlinked; resolves to a non-existent `docs/CLAUDE.md` |
| N2 | nit | `../CLAUDE.md` denotes two different files depending on the citing document |
| N3 | nit | `activate.zsh` path only given repo-prefixed; unusable from inside the repository |
| N4 | nit | "not planned for a later one" forecloses a future schema version that was not decided |
| N5 | nit | which C++ test framework is now neither accepted nor open |
| N6 | nit | widened authorization (incl. PR merge) under-described in the PR body; `WS:21`'s "restated by the user" is unverifiable from the repository |

**No rule protecting against a destructive or irreversible action was removed outright**, but one
was weakened (S1: the pre-write destination check) and one lost its scope (S2). The core Settings
claim — "the core never reads a preference" — is **verified correct** against the full C interface
and every dependent accepted behaviour.

---

## VERDICT: DO NOT MERGE

Shortest path to mergeable — the two blocking items:

1. `docs/game-data.md:5` — insert "the Settings placement," into the accepted list after "the
   store schema version 1,".
2. `docs/architecture.md:82` — delete "The accepted direction is that builds run locally until
   Windows work begins, and that CI then covers both a macOS 26 runner and a Windows runner; the
   exact matrix and pinning remain open.", restoring the bullet to its previous text.

Strongly recommended in the same change (cheap, and two of them are rule regressions):

3. `WS:39` — restore the affirmative destination check (S1).
4. `MiniXiangqi/CLAUDE.md` "Fixed project settings" — restore a discuss-first rule for target
   structure and platform configuration outside the relocation (S2).
5. `docs/testing.md` — move the delete-confirmation persistence gate out of **Game data** and add
   gates for the new decisions (S5), as `CLAUDE.md:55` requires.
6. `docs/game-data.md:153,157` and `docs/architecture.md:36` — the three inaccurate justification
   sentences (S6, S7, S8).
