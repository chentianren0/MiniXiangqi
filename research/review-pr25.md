# Independent pre-merge review — PR #25, `chore/repository-restructure`

Reviewer: independent agent. Read-only on the repository; no commits, pushes, merges or GitHub writes.
Base `main` = `1639da5`, head = `7f0433e` (single commit, fast-forwardable, `merge-base` = `1639da5`).
Toolchain: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`, Xcode 27.0 build `27A5228h`. Global `xcode-select` untouched. All derived data written to `/tmp`.

---

## Verdict summary

The mechanical part of this change is impeccable. `project.pbxproj` is the same git blob, every one of the eleven moves is a 100 % rename, no file is lost, the settings resolve identically from the new location, the entitlements file is genuinely processed from `apple/MiniXiangqi/`, and the project builds signed for macOS, builds for an iOS simulator, and passes the unit test target.

What the change misses is prose. The PR's own scope is "move the files and fix what referred to them", and the repository's front-door build instruction still names the old path. One further sentence — the one the PR deliberately amended — asserts the opposite of what the PR verified.

**1 blocking, 3 should-fix, 5 nits.**

---

## Part A — executed verification

### 1. Nothing but location changed

**A1. `project.pbxproj` is the same object.**

```
$ git --no-optional-locks -C MiniXiangqi rev-parse main:MiniXiangqi.xcodeproj/project.pbxproj
5e6ac92bae8cdb1271ee81a81fdbc6da7550345f
$ git --no-optional-locks -C MiniXiangqi rev-parse chore/repository-restructure:apple/MiniXiangqi.xcodeproj/project.pbxproj
5e6ac92bae8cdb1271ee81a81fdbc6da7550345f
```

Same blob id, so byte-identical by construction. Confirmed independently against the bytes on disk:

```
$ git cat-file blob main:MiniXiangqi.xcodeproj/project.pbxproj > /tmp/pbx_main.txt
$ git cat-file blob chore/repository-restructure:apple/MiniXiangqi.xcodeproj/project.pbxproj > /tmp/pbx_branch.txt
$ wc -c /tmp/pbx_main.txt /tmp/pbx_branch.txt
   23420 /tmp/pbx_main.txt
   23420 /tmp/pbx_branch.txt
$ cmp /tmp/pbx_main.txt /tmp/pbx_branch.txt && echo IDENTICAL
IDENTICAL
$ shasum -a 256 /tmp/pbx_main.txt /tmp/pbx_branch.txt wt-restructure/apple/MiniXiangqi.xcodeproj/project.pbxproj
eedaab1c1ac1b5030111f088a4444013ec24f599fe48ca0ee4fd00a6258a1692  /tmp/pbx_main.txt
eedaab1c1ac1b5030111f088a4444013ec24f599fe48ca0ee4fd00a6258a1692  /tmp/pbx_branch.txt
eedaab1c1ac1b5030111f088a4444013ec24f599fe48ca0ee4fd00a6258a1692  .../wt-restructure/apple/MiniXiangqi.xcodeproj/project.pbxproj
```

(An earlier run of this comparison produced two zero-byte files and a spurious `IDENTICAL`; the byte counts above are what makes the result trustworthy.)

**A2. Settings verified independently of the pbxproj, by resolution rather than by reading.**
`main` was exported to `/tmp/mx-main-export` with `git archive`, and `xcodebuild -showBuildSettings` was run against **both** layouts for all three targets:

```
$ xcodebuild -project <proj> -target <t> -configuration Debug -showBuildSettings \
    -destination 'generic/platform=macOS' | grep -E 'PRODUCT_BUNDLE_IDENTIFIER|DEVELOPMENT_TEAM|IPHONEOS_DEPLOYMENT_TARGET|MACOSX_DEPLOYMENT_TARGET|SUPPORTED_PLATFORMS|EXCLUDED_ARCHS|SWIFT_VERSION|CODE_SIGN_ENTITLEMENTS|TARGETED_DEVICE_FAMILY|CODE_SIGN_STYLE'
```

Resolved values (identical on both branches):

| target | value |
|---|---|
| `MiniXiangqi` | `PRODUCT_BUNDLE_IDENTIFIER = com.chentianren.MiniXiangqi` |
| `MiniXiangqiTests` | `PRODUCT_BUNDLE_IDENTIFIER = com.chentianren.MiniXiangqiTests` |
| `MiniXiangqiUITests` | `PRODUCT_BUNDLE_IDENTIFIER = com.chentianren.MiniXiangqiUITests` |
| all three | `DEVELOPMENT_TEAM = 7P9PPXP2SF`, `IPHONEOS_DEPLOYMENT_TARGET = 26.5`, `MACOSX_DEPLOYMENT_TARGET = 26.5`, `SUPPORTED_PLATFORMS = iphoneos iphonesimulator macosx`, `SWIFT_VERSION = 6.0`, `TARGETED_DEVICE_FAMILY = 1,2`, `CODE_SIGN_STYLE = Automatic` |
| `MiniXiangqi` | `EXCLUDED_ARCHS = x86_64`, `CODE_SIGN_ENTITLEMENTS = MiniXiangqi/MiniXiangqi.entitlements` |

```
$ diff /tmp/settings_main.txt /tmp/settings_branch.txt && echo "NO DIFFERENCES"
NO DIFFERENCES
```

**A3. Entitlements file moved, unchanged, and actually consumed.**

```
$ git rev-parse main:MiniXiangqi/MiniXiangqi.entitlements chore/repository-restructure:apple/MiniXiangqi/MiniXiangqi.entitlements
1a11c74ccd2f1d5d1305843a1eb93c26fd59f2d8
1a11c74ccd2f1d5d1305843a1eb93c26fd59f2d8
```

`CODE_SIGN_ENTITLEMENTS` is `SRCROOT`-relative, so it only proves itself under a signing build. Both layouts were therefore built with signing **enabled** (no `CODE_SIGNING_ALLOWED=NO`):

```
main   : ** BUILD SUCCEEDED   ProcessProductPackaging /tmp/mx-main-export/MiniXiangqi/MiniXiangqi.entitlements
branch : ** BUILD SUCCEEDED   ProcessProductPackaging .../wt-restructure/apple/MiniXiangqi/MiniXiangqi.entitlements
$ diff /tmp/ent_main.txt /tmp/ent_branch.txt && echo "IDENTICAL embedded entitlements"
IDENTICAL embedded entitlements
```

The embedded set is `com.apple.security.hardened-process*` (+ `hardened-heap`, `checked-allocations`, `dyld-ro`, `enhanced-security-version-string 2`, `platform-restrictions-string 2`), sandbox, and team identifier — identical on both sides. The two `com.apple.developer.kernel.*` keys are dropped by the macOS profile on both branches equally; pre-existing, not this PR.

### 2. The project works from its new location

```
$ xcodebuild -project apple/MiniXiangqi.xcodeproj -scheme MiniXiangqi \
    -destination 'platform=macOS,arch=arm64' -configuration Debug \
    -derivedDataPath /tmp/mx-review-dd-macos CODE_SIGNING_ALLOWED=NO build
EXIT=0
** BUILD SUCCEEDED **      (no error:, no source warning:)
```

**iOS path — the author did not check this; it is clean.**

```
$ xcodebuild -project apple/MiniXiangqi.xcodeproj -scheme MiniXiangqi -showdestinations
  { platform:iOS, name:Any iOS Device }
  { platform:iOS Simulator, name:Any iOS Simulator Device }
  { platform:iOS Simulator, arch:arm64, OS:27.0, name:iPhone 17 Pro Max } ... (11 iOS Simulator entries)
  incompatible: visionOS Simulator (expected — SUPPORTED_PLATFORMS excludes it)
```

The same command against the `main` export yields a byte-for-byte identical destination list. First attempt by simulator *name* failed with `EXIT=70` — two simulators share the name "iPhone 17 Pro Max" on this machine, an environment ambiguity, not a project defect. By UDID:

```
$ xcodebuild ... -destination 'platform=iOS Simulator,id=43DAA3E6-9C91-458C-9DAF-567A375B2B5F' ... build
EXIT=0
** BUILD SUCCEEDED **
```

**Unit tests run.**

```
$ xcodebuild test -project apple/MiniXiangqi.xcodeproj -scheme MiniXiangqi \
    -destination 'platform=macOS,arch=arm64' -only-testing:MiniXiangqiTests
EXIT=0
Test case 'MiniXiangqiTests/example()' passed on 'My Mac - MiniXiangqi (4659)' (0.000 seconds)
** TEST SUCCEEDED **
```

### 3. Nothing left behind or silently dropped

`main` tracks 40 files, the branch 43. Stripping the `apple/` prefix from the branch listing and diffing hash-plus-path against `main` accounts for every path with no residue:

```
$ git ls-tree -r --format='%(objectname) %(path)' main | sort > /tmp/tree_main.txt
$ git ls-tree -r --format='%(objectname) %(path)' chore/repository-restructure | sort > /tmp/tree_branch.txt
$ sed 's| apple/| |' /tmp/tree_branch.txt | sort | diff /tmp/tree_main.txt -
> 4e0c34e... core/README.md          (added)
> a166373... windows/README.md       (added)
> d194dae... README.md               (added — apple/README.md with the prefix stripped)
< 913074b... docs/architecture.md     |  (modified: one line)
> 8b964a2... docs/architecture.md     |
```

Every other blob id is unchanged. `git diff -M --summary` records all eleven moves as `rename ... (100%)`. Nothing lost, nothing unexpected added.

**`.gitignore` is unchanged (`dd16e31` on both) and every pattern is unanchored, so the move breaks none of them:**

```
.DS_Store / .build/ / DerivedData/ / *.xcuserstate / xcuserdata/
$ git check-ignore -v apple/.DS_Store apple/.build/ apple/DerivedData/ core/DerivedData/ \
    apple/MiniXiangqi.xcodeproj/xcuserdata/ apple/MiniXiangqi.xcodeproj/project.xcworkspace/xcuserdata/
.gitignore:1:.DS_Store        apple/.DS_Store
.gitignore:2:.build/          apple/.build/
.gitignore:3:DerivedData/     apple/DerivedData/
.gitignore:3:DerivedData/     core/DerivedData/
.gitignore:5:xcuserdata/      apple/MiniXiangqi.xcodeproj/xcuserdata/
.gitignore:5:xcuserdata/      apple/MiniXiangqi.xcodeproj/project.xcworkspace/xcuserdata/
```

No pattern was written against an old path, none now matches nothing, and none matches too much. The worktree is still clean after every build run above (`git status --porcelain -uall` → empty).

### 5. Layout matches the contract

```
$ git ls-tree chore/repository-restructure
100644 .gitignore   100644 CLAUDE.md   100644 LICENSE   100644 README.md
040000 apple        040000 core        040000 docs      040000 fixtures    040000 windows
```

Exactly the tree in `docs/architecture.md:66-73`, with `fixtures/` and `docs/` at the root as the contract requires.

---

## Part B — findings

### F1 — `README.md:39` still tells the reader to open a path that no longer exists — **blocking**

> "Open `MiniXiangqi.xcodeproj` with that Xcode installation."

There is no `MiniXiangqi.xcodeproj` at the repository root after this PR. This is the single instruction in the repository that tells a developer how to open the project, in the document `README.md:3` describes as "an introduction for developers, testers, and reviewers". The PR's stated scope is a move plus the references to it; this is the one reference in prose and it was missed, because verification stopped at the project's internal references. `apple/README.md` does not supply the path either, so after this merge no document in the repository names where the project is.

**Correction — `README.md:39`:**

> Open `apple/MiniXiangqi.xcodeproj` with that Xcode installation.

### F2 — The amended `architecture.md` sentence asserts a change this PR proved did not happen — **should-fix**

> "The Apple frontend's Xcode project sits under `apple/`. It was relocated there while it was still the generated scaffold, so **the move changed file locations and the project's references to them** and nothing else about the build." (`docs/architecture.md:77`)

The `main` text was a prediction in the future tense — "It **changes** file locations and the project's references to them". Converting it to the past tense turns a falsified prediction into an assertion of fact. The project's references did **not** change: `project.pbxproj` is the same git object (A1 above), and the PR body says so itself — "moving them together **preserves every reference**". `architecture.md` is an accepted contract; it should not record a false fact about the repository's own history, and it should not contradict the verification the same PR performed.

**Correction — `docs/architecture.md:77`:**

> - The Apple frontend's Xcode project sits under `apple/`. It was relocated there while it was still the generated scaffold; because every path inside the project is relative to the project directory, the move changed file locations only — the project's own references and nothing else about the build.

### F3 — `apple/README.md` sends the reader to a file that is not in the repository — **should-fix**

> "Requires the toolchain pinned in the workspace `CLAUDE.md`." (`apple/README.md:10`)

The workspace `CLAUDE.md` is `/Users/tianren/coding/minixiangqi/CLAUDE.md` — one directory *above* the repository root, untracked, and part of no repository. Anyone who clones `ppppvz/MiniXiangqi` cannot follow this pointer. Worse, the repository *does* contain a `CLAUDE.md` at its root, so a reader lands there — and that file contains no toolchain pin at all; it only says "the workspace `../CLAUDE.md` also applies". The toolchain is in fact pinned twice inside the repository, at `README.md:26-30` and `docs/testing.md:7-24`.

This is the only outward-facing reference in the three new READMEs that does not resolve; the six markdown links in them all do.

**Correction — `apple/README.md:10`:**

> Requires the Apple toolchain pinned in the repository [`README.md`](../README.md) and [`docs/testing.md`](../docs/testing.md).

### F4 — `windows/README.md` states an open question as a deliberate decision, and cites the wrong document for it — **should-fix**

> "Not yet started. Apple platforms are implemented and distributed first, and the Windows toolchain is **deliberately unpinned rather than assumed** — see the open items in [`docs/architecture.md`](../docs/architecture.md) and [`docs/product.md`](../docs/product.md)." (`windows/README.md:5-7`)

Two problems.

*The framing.* No contract calls the unpinned Windows toolchain deliberate. `docs/architecture.md:86` files it under **Need to discuss**, which the document's own status line marks non-normative: "Windows toolchain pinning for the core and frontend, and the concrete CI matrix and runner images." `docs/testing.md:30` calls it "unpinned **draft state**" that "must be pinned and verified before Windows validation claims are made". An unanswered question is being restated as an answered one — a decision to defer. That is exactly the kind of invention a design-first repository cannot absorb quietly, because the next reader will treat it as settled.

*The citation.* `docs/product.md`'s Need to discuss contains two Windows items (lines 109-110): whether the Windows build needs an in-app interface-language override, and the Windows internal-distribution mechanism and packaging format. Neither is about the toolchain. The document that actually states the toolchain is unpinned — `docs/testing.md` — is not cited.

**Correction — `windows/README.md:5-7`:**

> Not yet started; Apple platforms are implemented and distributed first. The Windows toolchain is not yet pinned — pinning it is an open item in [`docs/architecture.md`](../docs/architecture.md), and [`docs/testing.md`](../docs/testing.md) requires it to be pinned and verified before any Windows validation claim. Further open Windows items — the in-app interface-language override and the internal-distribution mechanism — are in [`docs/product.md`](../docs/product.md).

### F5 — `core/README.md` widens the hash-verification claim beyond the contract — **nit**

> "Pinned third-party inputs — the fork revision and its patches, build flags, the variant configuration, the network, and the vendored SQLite amalgamation — are recorded in the repository's pinned-input manifest and **verified by hash at build time**." (`core/README.md:14-16`)

The five-item list is a faithful compression of `docs/engine-integration.md:164-168`. The verification clause is not: two of the five items carry no hash in the manifest (the fork revision and patch list are recorded by revision; the build flags are flags), and the contract's own wording is narrower — "The build verifies every hash **before packaging** and fails on a mismatch" (`engine-integration.md:170`).

**Correction — `core/README.md:16`:** `...are recorded in the repository's pinned-input manifest, and every hash it records is verified before packaging.`

### F6 — `core/README.md` generalises a rules-facade-only authority to the whole core — **nit**

> "Its tests run on every development platform without a frontend, through one shared C++ test runner, and are **validated against the approved fixtures** in [`fixtures/`](../fixtures/) **rather than against engine behaviour**." (`core/README.md:10-12`)

The test runner and the "not against engine behaviour" stance are both accepted (`architecture.md:78`, `:26`), but the fixtures gate the **rules facade** specifically — `fixtures/rules/README.md:38` says "The shared core's rules facade is gated by these fixtures on every platform". The archive codec and the library store, which the preceding paragraph lists as core responsibilities, are not validated by rules fixtures. As written the sentence says the core's whole test suite is. Secondarily, it is the facade that the fixtures validate, not the tests.

**Correction — `core/README.md:10-12`:** `Its tests run on every development platform without a frontend, through one shared C++ test runner. The rules facade is gated by the approved fixtures in `fixtures/`, which are its authority rather than engine behaviour.`

### F7 — `windows/README.md`'s presentation claim cites the wrong two documents — **nit**

> "Product behaviour and persisted meaning are identical to the Apple frontend; only presentation follows the platform, using Fluent materials, navigation and context menus rather than recreated Apple styling." (`windows/README.md:9-11`)

The claim itself checks out: the first clause is `product.md:24`, and the Fluent clause is `interaction-design.md:32` ("system materials, controls, and navigation patterns rather than recreated Apple styling") plus `:505` (context menus), both in accepted sections. But `interaction-design.md` is the source and the README never cites it, pointing instead at `architecture.md` and `product.md` in the sentence above. Adding the link also protects the reader from over-reading it: `interaction-design.md:536` still has "Define the Windows navigation presentation, Fluent material usage ... when Windows implementation begins" under **Need to discuss**, so the *direction* is accepted while the *specifics* are not.

**Correction:** add `see [`docs/interaction-design.md`](../docs/interaction-design.md)` to that sentence.

### F8 — Spelling drifts from the sentence being paraphrased — **nit**

`core/README.md:12` "engine behaviour" paraphrases `architecture.md:26` "engine behavior"; `windows/README.md:9` "Product behaviour" paraphrases `product.md:24` "Product behavior". The repository is already mixed (`interaction-design.md` and `xiangqi-rules.md` use "behaviour"; every other contract uses "behavior"), so this is genuinely minor — but a paraphrase that flips the spelling of the word it is quoting reads like a different source.

### F9 — Two observations, both pre-existing and neither caused by this PR

- **No shared scheme is committed.** The tree contains `project.pbxproj` and `project.xcworkspace/contents.xcworkspacedata` and nothing under `xcshareddata/xcschemes/`; `-scheme MiniXiangqi` works only because `xcodebuild` autocreates it into gitignored `xcuserdata/`. True on `main` too, so not a regression — but a restructure PR is the cheapest moment to add `apple/MiniXiangqi.xcodeproj/xcshareddata/xcschemes/MiniXiangqi.xcscheme`, and `docs/architecture.md:79-80` anticipates CI, which will need it. Out of scope for this PR; worth an issue.
- **`.gitignore` has no `build/` entry.** `git check-ignore build/ apple/build/` → not ignored. Unchanged by this PR and unrelated to the move; noted only because item 3 asked for full `.gitignore` accounting.

### Checked and clean

- **Repository-wide reference sweep.** `git grep` across `docs/`, `README.md`, `CLAUDE.md`, `fixtures/` and the new READMEs for `MiniXiangqi.xcodeproj`, `MiniXiangqiTests`, `MiniXiangqiUITests`, `MiniXiangqi/MiniXiangqi` and `.entitlements` returns exactly one stale hit — F1. The other two hits are Swift type names inside the moved test files.
- **Workspace `CLAUDE.md` one directory up** describes `MiniXiangqi/` as "the product repository" and never names the app source directory or the Xcode project. Correct before and after; no change needed. (It is outside the repository in any case.)
- **`discussion-drafts/` scripts.** No contract cites any script by name — `grep -rn '\.(py|sh|zsh|rb|js)\b' docs/ fixtures/ README.md CLAUDE.md` returns nothing. The fixture checker resolves its own path as `Path(__file__).parent.parent / "MiniXiangqi" / "fixtures" / "rules"` (`engine-fixture-check.py:34`), which still resolves because `fixtures/` stays at the root — the contract's stated reason for keeping it there is load-bearing here. No other script in `discussion-drafts/` references a moved path. Only two superseded review documents mention the old `MiniXiangqi.xcodeproj` path, correctly, as history.
- **All six relative markdown links** in the three new READMEs resolve.
- **`architecture.md:5` status line** ("The repository layout, the relocation of the Xcode project ... are also accepted") remains correct and needed no edit.

---

## Recommendation

The move itself is verified to a standard that leaves nothing to argue with, and F2–F8 are all prose. But F1 leaves the repository's only build instruction pointing at a path this very PR deleted, in a repository whose deliverable is currently its documentation. That is a one-word fix, and it should not land broken.

Fix F1; fix F2 in the same push since it is the sentence this PR chose to touch and it now says the opposite of what the PR proved; F3 and F4 should follow. Re-verification after those edits needs no rebuild — they are documentation-only.

**DO NOT MERGE**

---

# Round 2 — re-review of `46cd13a`

Head is now `46cd13a` ("Point the build instruction at the project's new location"), one commit on top of `7f0433e`. `main` is still `1639da5`, so the branch remains two commits and fast-forwardable. Same read-only rules; worktree clean before and after.

## Scope of the fix commit — confined, as stated

```
$ git diff --name-only 7f0433e 46cd13a
README.md
apple/README.md
docs/architecture.md
windows/README.md
 4 files changed, 6 insertions(+), 5 deletions(-)
```

Four documentation files, six lines. Nothing else. Confirmed at blob level rather than by reading the diff:

```
$ git rev-parse 46cd13a:apple/MiniXiangqi.xcodeproj/project.pbxproj main:MiniXiangqi.xcodeproj/project.pbxproj
5e6ac92bae8cdb1271ee81a81fdbc6da7550345f
5e6ac92bae8cdb1271ee81a81fdbc6da7550345f
$ git rev-parse 46cd13a:apple/MiniXiangqi/MiniXiangqi.entitlements main:MiniXiangqi/MiniXiangqi.entitlements
1a11c74ccd2f1d5d1305843a1eb93c26fd59f2d8
1a11c74ccd2f1d5d1305843a1eb93c26fd59f2d8
$ git diff --stat main 46cd13a -- .gitignore fixtures/ CLAUDE.md LICENSE
(empty)
```

Full tree accounting against `main` still balances at 40 → 43 files, with the only deltas being the three added READMEs and the two edited documents (`README.md` `d1c762c`→`6eb05ca`, `docs/architecture.md` `913074b`→`95d84a4`). All eleven moved blobs are untouched by both commits.

Rebuilt and retested at `46cd13a` anyway:

```
macOS, signing enabled : exit=0  ** BUILD SUCCEEDED
                         ProcessProductPackaging .../wt-restructure/apple/MiniXiangqi/MiniXiangqi.entitlements
iOS Simulator (by UDID) : exit=0  ** BUILD SUCCEEDED
xcodebuild test         : exit=0  ** TEST SUCCEEDED **
                         Test case 'MiniXiangqiTests/example()' passed
git status --porcelain -uall : empty
```

## F1 — fixed, and it is the only stale path in the repository

`README.md:39` now reads "Open `apple/MiniXiangqi.xcodeproj` with that Xcode installation." Correct, and the path exists.

Re-swept, three ways.

```
$ git grep -nIE 'MiniXiangqi\.xcodeproj|MiniXiangqiTests|MiniXiangqiUITests|MiniXiangqi/(MiniXiangqi|Item|ContentView|Assets)|\.entitlements|\.xcassets' -- . ':!apple/MiniXiangqi.xcodeproj'
README.md:39: Open `apple/MiniXiangqi.xcodeproj` ...            <- the corrected line
apple/MiniXiangqiTests/MiniXiangqiTests.swift:3: struct MiniXiangqiTests {      <- Swift type name
apple/MiniXiangqiUITests/MiniXiangqiUITests.swift:3: final class MiniXiangqiUITests   <- Swift type name
```

Every backticked path-shaped token in every tracked markdown file, checked for existence on disk: all resolve. The two that do not exist are `pinned-inputs.json` (an artifact `engine-integration.md:162` specifies for the future, correctly not present yet) and `public.json` (an Apple UTI in `game-data.md:35`, not a path — a false positive of the heuristic).

Every relative markdown link in every tracked `.md` file, resolved from its own directory: **no broken links**.

**F1 is fixed and complete.** The only remaining path reference outside the repository is `CLAUDE.md`'s own "the workspace `../CLAUDE.md` also applies", which is pre-existing text this PR does not touch and which is addressed to agents rather than to a clone.

## F2 — fixed, and the replacement claim is itself verified

> "The Apple frontend's Xcode project sits under `apple/`. It was relocated there while it was still the generated scaffold. **Every reference inside the project is relative to the project directory, so moving the project and its sources together changed nothing about the build.**" (`docs/architecture.md:77`)

This no longer contradicts the evidence — it *is* the evidence. Because the sentence now asserts a structural fact about the project file, I verified that fact rather than taking it:

```
$ grep -o 'sourceTree = [^;]*;' apple/MiniXiangqi.xcodeproj/project.pbxproj | sort | uniq -c
   5 sourceTree = "<group>";
   3 sourceTree = BUILT_PRODUCTS_DIR;
$ grep -o 'path = [^;]*;' ... | sort | uniq -c
   1 path = MiniXiangqi;          1 path = MiniXiangqi.app;
   1 path = MiniXiangqiTests;     1 path = MiniXiangqiTests.xctest;
   1 path = MiniXiangqiUITests;   1 path = MiniXiangqiUITests.xctest;
$ grep -nE '(path|[A-Z_]+) *= *"?(/|\.\./|\$\(SRCROOT\)/\.\.)' ...   -> NONE
$ grep -nE '/Users/|~/' ...                                          -> NONE
$ grep -nE 'projectDirPath|projectRoot' ...
186: projectDirPath = "";
187: projectRoot = "";
```

Two `sourceTree` kinds only — `"<group>"`, which with `projectDirPath = ""` resolves against the project directory, and `BUILT_PRODUCTS_DIR` for the three products. Six `path =` entries, all bare names. No absolute path, no parent traversal, no `/Users/`, no `~`. The claim is exactly true. Combined with round 1's identical `-showBuildSettings` dumps, identical embedded entitlements, and both builds succeeding, "changed nothing about the build" is earned.

**F2 is fixed.**

## F3 — fixed

> "Requires the Apple toolchain pinned in [`docs/testing.md`](../docs/testing.md)." (`apple/README.md:10`)

The link resolves inside the repository, and `docs/testing.md:9-16` carries every value: Xcode 27 beta at `/Applications/Xcode-beta.app`, developer directory `/Applications/Xcode-beta.app/Contents/Developer`, expected build `27A5228h`, Swift 6, "iOS, iPadOS, and macOS 26.5 targets", and "Apple-silicon macOS; `x86_64` is not supported on macOS". Checked against `README.md:20-30` for drift: the two documents agree on every value. A clone now has the pin.

**F3 is fixed.** One residual, below as N6.

## F4 — fixed

> "Not yet started. Apple platforms are implemented and distributed first, and the Windows toolchain is **not yet pinned** — an open item in [`docs/architecture.md`](../docs/architecture.md), with [`docs/testing.md`](../docs/testing.md) recording that no Windows validation claim may be made until it is." (`windows/README.md:5-7`)

Both citations check out. `architecture.md:86` is under **Need to discuss**: "Windows toolchain pinning for the core and frontend, and the concrete CI matrix and runner images." `testing.md:30`: "...is unpinned draft state and must be pinned and verified before Windows validation claims are made." The invented "deliberately" is gone, and the misdirected `product.md` citation is gone. Dropping `product.md` entirely rather than re-pointing it at its actual open items is a reasonable narrowing — those items are about distribution and localization, not this file's subject.

**F4 is fixed.**

## Regression check

Nothing adjacent broke. The fix commit touched four files, all documentation; every other tracked blob is bit-identical to `7f0433e`, and `project.pbxproj` is still the same object as on `main`. All markdown links repository-wide resolve. Builds and tests are green at the new head. The five round-1 nits are untouched, as intended — none of them was made worse.

## Remaining items

Still open from round 1: **F5**, **F6** (both `core/README.md`), **F7**, **F8**, **F9** — all nits, none blocking. One new nit from the F3 fix:

### N6 — the toolchain is now pinned to a document that declares itself non-normative — **nit**

`docs/testing.md:5` reads: "**Status: Draft validation proposal.** Nothing in this document is normative until its status or an individual section is explicitly marked accepted." The "Required toolchain" section carries no accepted marker. So `apple/README.md` now says "the Apple toolchain **pinned** in `docs/testing.md`" while that document says nothing in it binds yet. `README.md:26-30` states the identical values with no such caveat, and the two do not drift.

**Correction — `apple/README.md:10`:** `Requires the Apple toolchain recorded in the repository [`README.md`](../README.md) and [`docs/testing.md`](../docs/testing.md).`

This is strictly better than the pre-fix state either way; the pointer now resolves for a clone, which was the finding.

### If you want nits in this pass

Take **F5** and **F6** now. Both are in `core/README.md`, both are a new summary claiming more than the contract it summarises, and `core/` is the next milestone — that file will be the first thing read when core implementation starts, and a contract summary that overreaches is worse than no summary. **F7** (one link to `interaction-design.md`) and **N6** (one link to `README.md`) are single-token edits and safe to take with them; all four are confined to `core/README.md`, `windows/README.md` and `apple/README.md`, which nothing else in the repository links to.

Leave **F8** (spelling; the repository is already mixed) and **F9** (no committed shared scheme; no `build/` ignore entry — both pre-existing on `main` and unrelated to the move) for separate issues. F9's shared scheme in particular deserves its own change, since `architecture.md:79-80` anticipates CI that will need it.

None of these gates the merge.

---

## Round 2 verdict

The four findings are correctly and completely fixed, the fix commit did only what it said, the replacement architecture sentence is now a claim I verified rather than one I contradicted, and the project still builds signed for macOS, builds for iOS, and passes its tests from the new location.

**MERGE**
