# Independent pre-merge review — PR #26, round 2

Workspace-only research note. Not part of any repository. Round 1: `review-pr26.md`.

- New commit: `5dc8f72` "Resolve the callback rule in the header, and assert on programming errors", on top of `8ac078e`
- Touches 4 files: `core/include/mxq.h` (+9/−5), `core/src/mxq_internal.cpp` (+4), `core/tests/main.cpp` (+26/−8), `core/tests/mxq_fixture.cpp` (+8). `pinned-inputs.json`, `fixtures/` and `docs/` untouched.
- All builds in `/tmp/mxq-r2`; the worktree was left clean.

**Verdict: DO NOT MERGE.** One blocking finding remains — the same rule B1 was about, left un-updated in one more place — plus one behaviour regression introduced by the round-2 commit. Both are small. Everything else the commit set out to fix is genuinely fixed, and nothing else regressed.

---

## B1 — the callback rule: fixed in nine places, **not** in the tenth — **BLOCKING**

The new wording is right, and the four functions are correctly identified:

> `mxq.h:691-696` — "It must copy and return. Inside it the legal calls are the status and blob helpers — `mxq_status_domain`, `mxq_status_name`, `mxq_blob_bytes`, `mxq_blob_len`, `mxq_blob_release` — together with the four pure queries that take no core instance and no lock: `mxq_core_version`, `mxq_rules_start_fen`, `mxq_engine_plan` and `mxq_archive_supported_versions`. Every other core function returns `MXQ_ERR_ARG_REENTRANT`."

I re-derived the set from the per-function `Thread:` lines rather than trusting the prose. **Exactly nine functions say "including inside a search callback", and they are exactly the nine the callback block names:**

```
INCLUDING callbacks (9):
    mxq_status_domain, mxq_status_name, mxq_blob_bytes, mxq_blob_len, mxq_blob_release,
    mxq_core_version, mxq_rules_start_fen, mxq_engine_plan, mxq_archive_supported_versions
EXCEPT callbacks (29)
neither (15)   # core_init/shutdown "never inside a search callback"; session-owner functions
```

No function is in the block but missing the phrase, and none has the phrase but is absent from the block. That half is complete and correct.

### The residue

`MXQ_ERR_ARG_REENTRANT`'s own definition still carries the superseded rule:

> `mxq.h:181-183` —
> ```c
> MXQ_ERR_ARG_REENTRANT         = 1010, /* called from inside a search callback,
>                                        * where only the status and blob
>                                        * helpers are legal */
> ```

```
$ grep -n "only mxq_status\|only the status\|the only core function" core/include/mxq.h
182:                                           * where only the status and blob
```

`mxq.h` therefore still says, in two places at once, both that `mxq_core_version` is legal inside a callback (line 761, and the callback block) and that only the status and blob helpers are (line 182). That is the same contradiction, about the same four functions, that made B1 blocking in round 1, and it survives in the one place a frontend author lands when they are handling the error code rather than writing the callback. Both binding generators surface an enum constant's trailing comment as its doc comment, so a C# author reading the generated `MXQ_ERR_ARG_REENTRANT` and a Swift author reading `MxqSearchCallback` still get different rules.

I am not re-litigating the resolution — following `core-interface.md:218` is correct, and the new wording states it well. This is one comment that the sweep missed.

**Correction:**

```c
MXQ_ERR_ARG_REENTRANT         = 1010, /* called from inside a search callback,
                                       * where only the status and blob helpers
                                       * and the four pure queries listed on
                                       * MxqSearchCallback are legal */
```

### Two smaller notes on the same commit

- `mxq.h:759-760` now reads "Callable before `mxq_core_init`, as are the other queries that take no core instance: `mxq_rules_start_fen`, `mxq_engine_plan` and `mxq_archive_supported_versions`." That is no longer false — the round-1 exclusivity claim is gone, confirmed — but the list omits the five status and blob helpers, which also take no core instance and are equally callable before init. **Nit;** say "…as are `mxq_rules_start_fen`, `mxq_engine_plan`, `mxq_archive_supported_versions` and the status and blob helpers."
- The edit left a stranded short line: `mxq.h:695` ends "…returns MXQ_ERR_ARG_REENTRANT. It must not block," with the rest on the next line. **Nit;** reflow.

Round-1 finding 1.1 (`"and the only core function that is"`, contradicted three times) is **fixed and verified**.

---

## B2 — the debug asserts: correct, and correctly scoped — **fixed, with one site missed**

Debug build has no `NDEBUG` (`grep -c NDEBUG build.ninja` → `0`). One case per process so each abort is attributable:

```
----- Debug build (asserts live) -----
  case 1: ABORT :: Assertion failed: (false && "required in pointer was null"),  check_in,  mxq_internal.cpp:76
  case 2: ABORT :: Assertion failed: (false && "required out pointer was null"), begin_out, mxq_internal.cpp:56
  case 3: ABORT :: Assertion failed: (false && "struct_size is smaller than this interface version"), check_in,  :81
  case 4: ABORT :: Assertion failed: (false && "struct_size is smaller than this interface version"), begin_out, :61
  case 5: ABORT :: begin_out, mxq_internal.cpp:56          (mxq_core_version, NULL out)
  case 6: ABORT :: begin_out, mxq_internal.cpp:61          (mxq_core_version, struct_size 2)
  case 7: rc=0  start_fen(cap=4)  RUNTIME -> MXQ_ERR_ARG_BUFFER_TOO_SMALL required=48
  case 8: rc=0  start_fen(NULL,0) RUNTIME -> MXQ_ERR_ARG_BUFFER_TOO_SMALL len=47
  case 10: rc=0 blob helpers on NULL -> bytes=0x0 len=0            (NULL-safe by contract, no assert)

----- Release build (NDEBUG) -----
  case 1..6: rc=0, returning MXQ_ERR_ARG_NULL / MXQ_ERR_ARG_STRUCT_SIZE exactly as in round 1
  case 7..11: identical to the Debug build
```

**Answering the specific question: no runtime error asserts.** `MXQ_ERR_ARG_BUFFER_TOO_SMALL` does not abort in either build, on either of its two paths (a too-small buffer and the count-only probe), which is exactly right — `core-interface.md:208` carves it out by name. The blob helpers are NULL-safe by contract and correctly do not assert. The release build's behaviour is byte-for-byte what round 1 measured, and `-Werror` still passes, including under `-Wunreachable-code-aggressive -Wshadow -Wextra-semi` (the code after `assert(false && …)` is unreachable in a Debug build and drew no warning).

`assert(false && "…")` also carries the message into the abort output, which is better than a bare predicate — the diagnostics above name the exact violation.

### Finding R2-1 — one argument-domain error still does not assert — **should-fix**

```
  case 9 (Debug): rc=0  archive_supported_versions(NULL,NULL) -> MXQ_ERR_ARG_NULL
```

`mxq_archive_supported_versions` (`core/src/mxq_archive.cpp:12-16`) is the one implemented function that does not route through `begin_out`/`check_in`; it calls `mxq::fill_error` directly. Both out-parameters NULL is an argument-domain programming error other than buffer-too-small, so `core-interface.md:208` and `mxq.h:141-145` require it to assert.

I am rating this **should-fix rather than blocking**, and the reason matters: B2 was blocking because the miss was *systemic* — `begin_out` and `check_in` are the helpers all 44 remaining functions will be built on, so the omission would have propagated. That is now fixed. What is left is one hand-written call site whose blast radius is a single pure function called with two NULLs, which no frontend does. It should land with B2, not after it.

**Correction:** add `assert(false && "both out parameters were null");` before the `fill_error` call in `mxq_archive_supported_versions`.

---

## Fixture loader: non-finite and out-of-range numbers — **fixed**

The injected `1e400` fixture that round 1 showed was silently *accepted* now errors:

```
ERROR  b16-occurrence-overflow
       fixture.assertions.game_state.at_occurrence: expected an integer, got a non-finite number
```

The range check correctly precedes the cast, and the bounds are exactly right: `-9223372036854775808.0` and `9223372036854775808.0` are both exactly representable as doubles, so the accepted interval `[-2^63, 2^63)` is precisely the set of doubles that convert to `int64_t` without undefined behaviour. I probed every edge I could construct:

```
ERROR  c04-occ-int64-max   (9223372036854775807)  integer is outside the representable range   # rounds up to 2^63
ERROR  c05-occ-2pow63      (9223372036854775808)  integer is outside the representable range
ERROR  c06-occ-fraction    (3.5)                  expected an integer
ERROR  c07-occ-1e308                              integer is outside the representable range
ERROR  c08-prefix-1e400                           expected an integer, got a non-finite number
ERROR  c09-prefix-neg-1e400                       expected an integer, got a non-finite number
```

**The undefined behaviour is gone.** Rebuilt with `-fsanitize=address,undefined` and run over all three corpora:

```
  bad   (24 malformed fixtures): sanitizer diagnostics = 0
  bad2  (12 numeric edge cases): sanitizer diagnostics = 0
  rules (the 16 real fixtures):  sanitizer diagnostics = 0
```

Round 1 reported `mxq_fixture.cpp:106:36: runtime error: inf is outside the range of representable values of type 'long long'`. It no longer reproduces.

### Note — the semantic half of the round-1 correction was not taken — **nit**

```
NOT IMPL  c01-occ-negative       ("at_occurrence": -5)
NOT IMPL  c02-occ-above-uint32   ("at_occurrence": 4294967296)
NOT IMPL  c03-occ-int64-min      ("at_occurrence": -9223372036854775808)
```

`at_occurrence` is `uint32_t` in `MxqGameStatus`, so none of these can ever match. They are now merely *representable* rather than undefined, so this has been demoted from a correctness issue to a reporting one: once the facade lands they become FAIL (blamed on the core) instead of ERROR (blamed on the fixture). Downgraded from should-fix to **nit**. Correction unchanged: `if (n < 0 || n > static_cast<int64_t>(out.moves.size()) + 1) return load.fail(…)`.

---

## Directory scan — **fixed, but it introduced a regression**

The order dependence is gone. The same dangling symlink now behaves identically whichever way it sorts, and the message names the offending entry rather than the directory:

```
  aa-dangling:  mxq_core_tests: cannot read /tmp/mxq-r2/sym/aa-dangling.json: No such file or directory
                exit=2
  zz-dangling:  mxq_core_tests: cannot read /tmp/mxq-r2/sym/zz-dangling.json: No such file or directory
                exit=2
```

Round 1's failure — `aa-dangling` silently dropped with exit 0, `zz-dangling` aborting the run with a message blaming the directory — does not reproduce. A valid symlink *to* a real fixture still resolves and runs. An unreadable regular file is reported as an ERROR verdict at exit 1, which is the right verdict (the file exists and is a fixture; it just could not be parsed).

### Finding R2-2 — a `*.json` directory now aborts the entire run — **should-fix**

Re-running round 1's unmodified malformed corpus, which contains a directory named `b25-directory.json`:

```
$ mxq_core_tests --fixtures /tmp/mxq-pr26/bad
mxq_core_tests: cannot read /tmp/mxq-pr26/bad/b25-directory.json: not a regular file
exit=2
```

Round 1's build ignored it and evaluated the other 24 entries (20 ERROR, exit 1). The round-2 build evaluates **nothing**. The new code conflates two different conditions:

```cpp
std::error_code entry_ec;
if (!entry.is_regular_file(entry_ec) || entry_ec) {          // main.cpp:502
```

The commit's own comment justifies only the first of them — "An entry that **cannot be stat'd** is a setup failure, because a fixture we cannot read is not a fixture we may skip." A directory named `x.json` stats perfectly well; it simply is not a regular file, and it never was a fixture. On macOS the same applies to any `.json` bundle or package directory.

This fails *closed* — exit 2 is a hard setup failure, so it can never hide a real defect, which is why it is should-fix and not blocking. But it is a behaviour change the commit message does not describe, and it turns a stray directory into a total suite outage.

**Correction:** separate the two conditions —

```cpp
std::error_code entry_ec;
const bool regular = entry.is_regular_file(entry_ec);
if (entry_ec) {                       /* genuinely could not be stat'd: setup failure */
    std::cerr << "mxq_core_tests: cannot read " << entry.path().string()
              << ": " << entry_ec.message() << "\n";
    return 2;
}
if (!regular) {                       /* a directory or device named *.json is not a fixture */
    continue;
}
files.push_back(entry.path());
```

Removing the directory confirms nothing else changed — 21 ERROR (one more than round 1, because `b16` moved from NOT IMPLEMENTED to ERROR), exit 1.

---

## Nothing else regressed

Every round-1 measurement re-run against `5dc8f72`:

| Check | Round 1 | Round 2 |
|---|---|---|
| 53 signatures vs `core-interface.md` | 0 missing / 0 extra / 0 mismatches | **identical** |
| Header standalone, `-Wall -Wextra -pedantic -Wpadded` | clean under c99/c11/c17/c23/gnu17/c++20 | **identical** |
| `-Wpadded` on 5 non-Apple ABIs (MSVC x64/x86/arm64, Linux x64, armv7) | clean | **identical** |
| CMake configure + build, `-DMXQ_WARNINGS_AS_ERRORS=ON` | 14/14, zero warnings | **identical**, and also clean under `-Wunreachable-code-aggressive -Wshadow -Wextra-semi` |
| Pure-C TU links against the C++ archive | OK | **OK** |
| `mxq_engine_plan` vs an independently derived reference | 3298 cases, 0 mismatches | **3298 cases, 0 mismatches** |
| All 52 `mxq_status_name` values | 0 mismatches | **0 mismatches** |
| Real fixtures | 16 NOT IMPLEMENTED, 0 passed, exit 0 | **identical**; JUnit `skipped="16"` |
| `-DMXQ_ENABLE_RULES_FACADE=ON` | link failure, not a silent pass | **link failure** |
| Exit codes (malformed 1 / real 0 / missing dir 2 / empty dir 2 / bad arg 2 / help 0) | as listed | **identical** |
| Swift module map, `-swift-version 6` | compiles and runs, 0 errors | **0 errors**, same layouts (`MxqError=160 MxqPosition=120 MxqSearchResult=168 MxqVersion=232`) |
| `pinned-inputs.json` | fork revision exists; network 4,333,499 B / `12c45d5d…09ce` | **unchanged and re-verified** |

No fixture reports PASS, and the structural gate that guarantees it (`main.cpp` returns `NotImplemented` before `evaluate_fixture` is reachable) is untouched.

---

## Your three deferred items — my view on severity

### 1. `ctest` reporting "100% tests passed" — **should-fix, not blocking**

Still reproduces:

```
$ ctest --test-dir /tmp/mxq-r2/rel
1/1 Test #1: rules_fixtures ...................   Passed    0.01 sec
100% tests passed, 0 tests failed out of 1
```

Not blocking, for three reasons. The dangerous version of this defect — the runner passing a fixture it cannot evaluate — does not exist and is structurally prevented. The JUnit report is correct (`skipped="16"`), the runner's own stdout is unambiguous, and the process exit code is honest. And `architecture.md:80` says CI "remains a convenience rather than a merge gate", so no gate is currently being fooled.

What is actually wrong is narrower than the finding's title: `main.cpp:20-23` claims "**no CI dashboard shows this suite as green-and-complete**", and `ctest` — the invocation both `core/CMakeLists.txt:12` and `core/README.md` document — does exactly that. The cheapest honest fix is to delete the over-claim, one line, and do the `SKIP_RETURN_CODE 77` wiring when CI lands. I would take the one-line deletion now; a comment that promises a property the code does not have is how the next reader gets misled.

### 2. The loader not checking `variant` or move syntax — **should-fix, not blocking**

Confirmed still open:

```
NOT IMPL  c10-variant-chess     ("variant": "chess")
NOT IMPL  c11-move-malformed    ("moves": ["zz99", …])
NOT IMPL  c12-fen-garbage       ("start_fen": "not a fen")
```

Not blocking: none of these can turn a fixture the core got *wrong* into a PASS. The worst outcome is a schema violation misattributed to the core as a FAIL, which is noisy rather than dangerous.

I would flag one thing though, and it is the reason I would not let this sit indefinitely: this is the only one of your three where the fixtures are the project's independent authority and the loader is the sole gate on them. `fixtures/rules/README.md` says an accepted fixture's "`id`, position, moves, and assertions are immutable in meaning", and a silent `variant` drift would let a fixture claim a different ruleset while still counting as authority. With 16 hand-reviewed fixtures in one directory that risk is theoretical. It stops being theoretical when the deferred mutual-violation tranche lands, because that is when a hand-authored typo is most likely and least likely to be caught by eye. **Before the next fixture tranche, not before this merge.**

### 3. The manifest calling its field names provisional while CMake consumes three — **should-fix, not blocking**

Nothing is wrong at runtime; the three consumed values are correct and I re-verified all of them against reality. It is a stale sentence, and staleness in a manifest is worth fixing but does not block a scaffold.

One adjacent robustness point I would rather see land with it than separately: `mxq_pinned_get` (`core/CMakeLists.txt:60-66`) accepts whatever `string(JSON … GET)` returns and bakes it straight into `MxqVersion`, which the contract calls load-bearing rather than diagnostic. If `network.sha256` were ever `null` — as `variant.sha256` and `sqlite.sha256` are today — the build would silently report a bogus network identity instead of failing. A length-and-hex check on the three consumed values is a few lines.

### 4. `core-interface.md:11`'s Sendable claim — **not blocking; parking it is right**

To answer directly: **no, it does not block this scaffold**, and I think your disposition is the correct one.

The defect is in the contract's prose, not in the header's design. `MxqCoreConfig` carrying two borrowed `const char *` paths is the accepted design — `core-interface.md` itself says unbounded strings "cross as `const char *` borrowed for the duration of the call", and `MxqCoreConfig` is the only struct that carries any. Making the blanket claim true would mean changing the interface (fixed-capacity path arrays, or a different `mxq_core_init` shape), which is precisely the kind of decision that being design-paused exists to prevent someone making alone.

It also costs nothing at runtime. `MxqCoreConfig` is constructed and consumed inside a single `mxq_core_init` call and never crosses an isolation boundary, so a Swift binding never needs it to be `Sendable`; the twelve structs that *do* travel — including `MxqSearchResult`, the one that crosses from the engine thread — all conform, which I re-verified. The claim is wrong; the design is not.

One request for whenever that contract change lands: give `mxq.h:30-32` the matching one-clause caveat at the same time, so the header and the contract do not drift the way lines 218 and 236 did.

---

## Summary

**Fixed and verified:** B1 in nine of ten places; B2 at both shared helpers, correctly scoped so no runtime error asserts and the release build is unchanged; round-1 finding 1.1; the fixture loader's undefined behaviour, now clean under UBSan across three corpora; the directory scan's order dependence.

**Blocking (1):** `mxq.h:181-183` — `MXQ_ERR_ARG_REENTRANT`'s own comment still states the superseded callback rule, contradicting the nine per-function comments and the callback block that this commit corrected. One comment.

**Should-fix, new in round 2 (2):** `mxq_archive_supported_versions` still returns `MXQ_ERR_ARG_NULL` without asserting (B2's residue, one line); a `*.json` **directory** now aborts the whole run with exit 2 instead of being ignored (a regression from this commit — fails closed, but a stray directory takes the suite out).

**Carried from round 1, still open:** 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8, 2.2, 2.3, 2.4, 3.3, 3.4, 3.5, 3.6, 5.1, 5.2, 6.2, 6.3 — none blocking, and four of them deliberately deferred with reasons I agree with.

**DO NOT MERGE** — but this is a short list. Fix `mxq.h:182`, add the one `assert` in `mxq_archive_supported_versions`, and split the two conditions in `main.cpp:502`, and I expect to sign off without further findings.

---
---

# Round 3 — final pass

- New commit: `0480ef7` "Fix the tenth statement of the callback rule, and a regression it caused", on top of `5dc8f72`
- Touches 4 files: `core/include/mxq.h` (+4/−2), `core/src/mxq_archive.cpp` (+3), `core/tests/main.cpp` (+11/−6), and nothing else. Across all three commits only five files have changed since the scaffold: `mxq.h`, `mxq_archive.cpp`, `mxq_internal.cpp`, `tests/main.cpp`, `tests/mxq_fixture.cpp`. `pinned-inputs.json`, `fixtures/`, `docs/` and `CMakeLists.txt` are untouched.
- Builds in `/tmp/mxq-r3`; worktree left clean.

**Verdict: MERGE.** All three items are fixed, I found nothing new, and nothing regressed.

## B1, the tenth site — fixed, and fixed better than I proposed

I re-derived the legal set from the per-function `Thread:` lines rather than reading the prose, as asked:

```
derived from Thread: lines — INCLUDING callbacks (9):
    mxq_status_domain, mxq_status_name, mxq_blob_bytes, mxq_blob_len, mxq_blob_release,
    mxq_core_version, mxq_rules_start_fen, mxq_engine_plan, mxq_archive_supported_versions
EXCEPT (29), NEVER (7), session-owner-only (8), total declarations 53

MxqSearchCallback names: [the same nine]
agrees with Thread: lines: True
```

9 + 29 + 7 + 8 = 53, so every declaration is accounted for and no function's thread class is unstated. The old phrasing is gone:

```
$ grep -niE "only the status|only mxq_status|the only core function|helpers are legal" core/include/mxq.h
  (zero occurrences)
```

**All ten statements now agree.** And the tenth is better than the correction I suggested: rather than restating the list a second time, it delegates —

> `mxq.h:181-185` — "called from inside a search callback, where the legal calls are the status and blob helpers and the four pure queries that take no core instance: **see MxqSearchCallback**"

One authoritative list with nine cross-references, instead of two lists that can drift. That is the right shape for a rule that has now been wrong in three different places, and it is why I do not expect a fourth.

## `mxq_archive_supported_versions` — fixed, and it was the last site

Confirmed by exhaustive audit rather than by grepping one pattern. The implementation has exactly six argument-domain return sites:

```
mxq_internal.cpp:57,62,77,82   begin_out / check_in            -> all four assert
mxq_archive.cpp:18             both out params NULL            -> now asserts (mxq_archive.cpp:15)
mxq_internal.cpp:113           MXQ_ERR_ARG_BUFFER_TOO_SMALL    -> correctly does NOT assert
```

`mxq_archive.cpp` was the only translation unit calling `fill_error` directly; `mxq_blob.cpp`, `mxq_rules.cpp` and `mxq_status.cpp` have no argument-domain return at all — the blob helpers are NULL-safe by contract, `mxq_rules_start_fen` reaches only the runtime buffer path, and the status helpers are total. So the set is closed.

Executed, one case per process so each abort is attributable:

```
----- Debug (asserts live, NDEBUG count 0) -----
  case 1: ABORT :: "required in pointer was null", check_in, mxq_internal.cpp:76
  case 2: ABORT :: "required out pointer was null", begin_out, mxq_internal.cpp:56
  case 3: ABORT :: "struct_size is smaller than this interface version", check_in, :81
  case 4: ABORT :: "struct_size is smaller than this interface version", begin_out, :61
  case 5: ABORT :: begin_out, mxq_internal.cpp:56            (mxq_core_version, NULL out)
  case 6: ABORT :: begin_out, mxq_internal.cpp:61            (mxq_core_version, struct_size 2)
  case 9: ABORT :: "both out parameters were null", mxq_archive_supported_versions, mxq_archive.cpp:15
  case 7: rc=0  start_fen(cap=4)  RUNTIME -> MXQ_ERR_ARG_BUFFER_TOO_SMALL required=48
  case 8: rc=0  start_fen(NULL,0) RUNTIME -> MXQ_ERR_ARG_BUFFER_TOO_SMALL len=47
  case 10: rc=0 blob helpers on NULL -> bytes=0x0 len=0
  case 11: rc=0 archive_supported_versions(&mn,&cur) -> MXQ_OK 1 1

----- Release (NDEBUG) -----
  cases 1-6, 9: return their codes, no abort; identical to rounds 1 and 2
```

**Seven programming errors assert; no runtime error does.** Both `MXQ_ERR_ARG_BUFFER_TOO_SMALL` paths and the NULL-safe blob helpers stay assert-free, which is exactly the carve-out `core-interface.md:208` names. The release build's behaviour is unchanged across all three rounds.

## The directory regression — fixed, and correct for every entry type

`is_regular_file` is now called once, its error code checked alone, and the two cases separated. I tested more entry types than the two in question:

```
  real fixtures + a stray.json directory     16 NOT IMPLEMENTED, exit=0
  FIFO pipe.json + nested sub.json/deeper     1 NOT IMPLEMENTED, exit=0
  round-1 corpus with b25-directory.json     21 ERROR, exit=1     (round 2: exit 2, zero evaluated)

  dangling symlink aa-dangling.json   cannot read …/aa-dangling.json: No such file or directory   exit=2
  dangling symlink zz-dangling.json   cannot read …/zz-dangling.json: No such file or directory   exit=2
  symlink loop                        cannot read …/a.json: Too many levels of symbolic links     exit=2
  valid symlink to a real fixture      1 NOT IMPLEMENTED, exit=0
```

**Both symlink orders behave identically**, which was the round-1 defect, and a directory, a nested directory or a FIFO named `*.json` is passed over rather than taking the suite down, which was the round-2 regression. An entry that genuinely cannot be stat'd — ENOENT or ELOOP — is still a setup failure at exit 2. The code and the comment above it now describe the same thing.

## The `ctest` over-claim — deleted

`grep -n "green-and-complete"` returns nothing. The surviving sentence claims only what is true: NOT IMPLEMENTED "is stated on its own summary line and is emitted as a skipped test case in the JUnit report." Deleting rather than rewording was the right call — the guarantee a skipped JUnit case provides is that a JUnit consumer can see it, not that every dashboard will.

## Nothing regressed

Every measurement from rounds 1 and 2, re-run against `0480ef7`:

| Check | Result |
|---|---|
| 53 signatures vs `core-interface.md` | 0 missing / 0 extra / 0 mismatches |
| Header standalone, `-Wall -Wextra -pedantic -Wpadded` | clean under c99/c11/c17/c23/gnu17/c++20 |
| `-Wpadded` on MSVC x64/x86/arm64, Linux x64, armv7 | clean — no implicit padding on any ABI |
| Build with `-DMXQ_WARNINGS_AS_ERRORS=ON` | 14/14, zero warnings; also zero under `-Wconversion -Wsign-conversion -Wunreachable-code-aggressive -Wshadow -Wextra-semi` |
| Pure-C TU links against the C++ archive | OK |
| `mxq_engine_plan` vs an independent reference | 3298 cases, 0 mismatches |
| All 52 `mxq_status_name` values | 0 mismatches |
| Real fixtures | 16 NOT IMPLEMENTED, 0 passed, exit 0; JUnit `skipped="16"` |
| `-DMXQ_ENABLE_RULES_FACADE=ON` | link failure, not a silent pass |
| ASan + UBSan over 5 fixture directories | 0 diagnostics |
| Swift module map, `-swift-version 6` | 0 errors; 12 value structs `Sendable` under `-strict-concurrency=complete` |
| `pinned-inputs.json` | fork revision `77d602e0` exists; network 4,333,499 B / `12c45d5d…09ce` |

Exit codes, measured capturing `$?` before any command substitution:

```
  real fixtures (16 NOT IMPL)        exit=0      dangling symlink       exit=2
  malformed corpus (21 ERROR)        exit=1      symlink loop           exit=2
  numeric edge corpus (9 ERROR)      exit=1      valid symlink          exit=0
  round-1 corpus w/ b25 directory    exit=1      missing directory      exit=2
  real fixtures + stray.json dir     exit=0      empty directory        exit=2
  FIFO + nested dir named *.json     exit=0      bad argument           exit=2
                                                 --help                 exit=0
```

*Instrument note, recorded so the numbers above can be trusted:* a first pass at this table printed `exit=0` for the two malformed corpora. That was my harness, not the runner — I had written `echo "$(basename $d) exit=$?"`, and the command substitution ran between the runner and the expansion of `$?`. Re-measured with `rc=$?` captured first, both are `exit=1`, and the full output confirms 21 and 9 ERROR verdicts respectively. No regression existed.

## Carried forward, none blocking

Open from round 1, unchanged and agreed as out of scope for this scaffold: **1.2** (count-only probe's return status unspecified), **1.3** (two homes for the first-illegal index), **1.4** (`MxqEnginePlan.threads` 0-substitution and no upper bound), **1.5** (`struct_size` write-back undocumented), **1.6**, **1.7**, **1.8**, **2.2** (`min_known == sizeof` contradicts the helpers' documented intent — inert today, wrong on the first appended field), **2.3** (ClangSharp names unnamed enums from source location; unverified, no .NET SDK here), **2.4** (Sendable claim — parked with the contract correction, correctly), **3.3** (`variant` and move-syntax validation — before the next fixture tranche), **3.5**, **3.6**, **5.1** (fork license absent from the manifest), **5.2** (manifest provisionality + the hex check in `mxq_pinned_get`), **6.2** (who resolves a Random first mover), **6.3** (`mxq_store_history_page` `limit` vs `cap`).

The two I would put first once the rules facade lands, because they are the ones that stop being cheap later: **2.2**, which becomes wrong the first time a struct grows, and **3.3**, which is the sole gate on the fixtures that are the project's independent authority.

## Summary

Three rounds, two blocking findings and one self-inflicted regression, all closed and each verified by execution rather than by reading the diff. The scaffold does what it claims: 53 signatures matching the accepted contract exactly, every vocabulary matching `game-data.md`, no implicit padding on six ABIs, a working Swift module map, Hash arithmetic that agrees with `engine-integration.md` in 3298 cases, a manifest whose every established value matches reality, and a fixture runner that reports 16 NOT IMPLEMENTED and cannot be made to pass a fixture it has not evaluated.

**MERGE**
