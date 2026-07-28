# Independent pre-merge review — PR #26, `feat/core-scaffold`

Workspace-only research note. Not part of any repository.

- PR: `ppppvz/MiniXiangqi#26`, "Scaffold the shared core: mxq.h, CMake, fixture runner, pinned inputs"
- Branch head: `8ac078e`, contains `main` (`60fc044`); 23 files, 4404 insertions, 0 deletions
- Reviewed against: `docs/core-interface.md` (accepted), `docs/architecture.md`, `docs/game-data.md`, `docs/engine-integration.md`, `docs/xiangqi-rules.md`, `fixtures/rules/README.md`
- All builds in `/tmp/mxq-pr26`; the worktree was left clean (`git -C wt-core status --porcelain` → empty)
- Toolchain: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`, AppleClang 21.0.0, CMake 4.3.2, Ninja 1.13.2

**Verdict: DO NOT MERGE.** Two blocking findings. Everything else in the PR's verification claims reproduced exactly, and the arithmetic and manifest are clean.

---

## 1. The header against the contract, function by function

I did not use the author's script. I extracted every `MXQ_API` declaration from `mxq.h` and every declaration from the `c` code blocks in `core-interface.md`, normalised whitespace and pointer spacing, and compared name, return type, parameter types, parameter order and constness.

```
$ python3 … # extract + normalised diff, full script in the transcript
spec count: 53 unique 53
hdr count: 53

In spec, not in header: []
In header, not in spec: []

--- mismatches ---
mismatch count: 0
```

**All 53 signatures match exactly**, including parameter names, `const char *const *`, `size_t` vs `uint32_t` choices, and out-parameter order. No function is missing, none is extra.

### Value structs

Every struct the contract describes is present with the described members:

| Contract | Header | Verdict |
|---|---|---|
| `MxqPosition` — FEN, side to move, `in_check`, `ply_count`, `position_revision` | all five present | ok |
| `MxqGameStatus` — `state`, `reason`, `at_occurrence`, `claim_available`, `undo_available`, `undo_plies`, `resign_available`, `search_expected` | all eight present | ok |
| `MxqGameConfig` — mode, resolved `human_side`, `first_mover_choice`, `ai_level`, `ai_movetime_ms` | all five present (declared in a different order than the contract's prose; layout is not specified there) | ok |
| `MxqArchiveInfo` — format version, identity, timestamps, mode, human side, `MxqOutcome`, `MxqEndReason`, move count | all present | ok |
| `MxqVersion` — API version, both archive versions, store schema, core/fork revision, variant, NNUE SHA-256 | all present | ok |
| `MxqSearchResult` — outcome, move, score, depth, nodes, elapsed, profile id (+ `game_id`, `position_revision` required by contract line 130) | all present | ok |
| `MxqRecordSummary` | covers `game-data.md:143`'s derived summary columns | ok |

### Error codes

```
codes in the wrong 1000-block: []
code count: 52
per domain: {1000: 10, 2000: 13, 3000: 5, 4000: 8, 5000: 5, 6000: 8, 7000: 2, 9000: 1}
  1000: 1001..1010 count=10 contiguous=True startsAt1=True
  2000: 2001..2013 count=13 contiguous=True startsAt1=True
  3000: 3001..3005 count=5 contiguous=True startsAt1=True
  4000: 4001..4008 count=8 contiguous=True startsAt1=True
  5000: 5001..5005 count=5 contiguous=True startsAt1=True
  6000: 6001..6008 count=8 contiguous=True startsAt1=True
  7000: 7001..7002 count=2 contiguous=True startsAt1=True
  9000: 9001..9001 count=1 contiguous=True startsAt1=True
duplicate status values: {0: ['MXQ_OK', 'MXQ_DOMAIN_OK']}   # intentional
```

Every item the contract's taxonomy table names has exactly one code, in the right block, with no gaps and no extras. `mxq_status_name` was tested against all 52 generated case-by-case: **0 name mismatches**.

### Serialized vocabularies vs `game-data.md`

`game-data.md:48-52` against the header's enums, checked constant by constant:

- `mode`: `human-vs-ai`, `free-play` — matches
- `human_side`: `red`, `black` — matches
- `ai_level`: `fast`, `standard`, `deep` — matches
- `first_mover_choice`: `human-first`, `ai-first`, `random` — matches
- `outcome`: `red-wins`, `black-wins`, `draw`, `none` — matches `MxqOutcome`
- `end_reason`: all nine — matches `MxqEndReason`
- `provenance`: `locally-played`, `imported`, `derived` — matches
- fixture states `ongoing`, `claimable-draw`, `red-wins`, `black-wins`, `draw` — matches `MxqGameState`

The `*_NONE = -1` additions are documented as in-band absence with no serialized counterpart. Correct.

### Finding 1.1 — the header contradicts itself on what is callable before `mxq_core_init` — **should-fix**

> `mxq.h:758` — "Report the four independent version axes. Callable before mxq_core_init, and **the only core function that is.**"

Contradicted three times in the same file:

> `mxq.h:1010` — "Write the frozen starting FEN and its length. **Callable before mxq_core_init**"
> `mxq.h:1081` — "A pure function: it touches no core state, initialises nothing, and is **callable before mxq_core_init**"
> `mxq.h:1262` — "The archive format versions this build reads and writes. **Callable before mxq_core_init**."

This is the single input both binding generators consume; the false claim will be copied verbatim into the Swift and C# doc comments.

**Correction:** delete ", and the only core function that is" from line 759, or replace it with the accurate list — `mxq_core_version`, `mxq_rules_start_fen`, `mxq_engine_plan`, `mxq_archive_supported_versions`, and the status and blob helpers.

### Finding 1.2 — the count-only buffer probe's return status is unspecified — **should-fix**

> `mxq.h:880-883` — "when cap is too small, returns MXQ_ERR_ARG_BUFFER_TOO_SMALL with MxqError.required_size set, which is routine rather than a programming error. **Passing out as NULL with cap 0 is the legal way to ask for the count alone.**"

The header never says which status that legal probe returns. The one implemented instance of the convention returns an error:

```
$ ./names_test
  start_fen count-only -> MXQ_ERR_ARG_BUFFER_TOO_SMALL len=47 required=48
```

and the runner's own wrapper hedges on it (`mxq_rules_facade.cpp:113`): `if (rc != MXQ_OK && rc != MXQ_ERR_ARG_BUFFER_TOO_SMALL) return rc;`. Two independently generated bindings will not agree unless the header says. **Correction:** state in the buffer-convention paragraph that the count-only probe returns `MXQ_ERR_ARG_BUFFER_TOO_SMALL` with `*out_count` set (matching the implemented behaviour), and make every counted-output function's comment reference that one paragraph.

### Finding 1.3 — the first-illegal index now has two homes — **should-fix**

The scaffold's resolution of its own reported defect 5 puts the index in `MxqError`:

> `mxq.h:463` — "`uint64_t detail_index; /* meaningful for MXQ_ERR_RULES_INVALID_HISTORY: the index of the first illegal move */`"

but `mxq_rules_evaluate` already has the contract's dedicated parameter:

> `mxq.h:1043` — "the function returns MXQ_ERR_RULES_INVALID_HISTORY and sets `*out_first_illegal_index` to its index"

Nothing says whether both are set, whether they must agree, or which is authoritative when `err` is NULL. That is a *new* ambiguity introduced by the fix, not one inherited from the contract. **Correction:** state that `MxqError.detail_index` carries the same value whenever `err` is non-NULL, and that `*out_first_illegal_index` is authoritative where the parameter exists.

### Finding 1.4 — `MxqEnginePlan.threads` behaviour is undocumented at both ends — **should-fix**

`MxqEngineBudget.active_processor_count` is documented only as "what Threads is initialised from". Executed:

```
cpus = 0            … threads=1
cpus = UINT32_MAX   … threads=4294967295
```

Zero is silently substituted with 1, and an absurd count is passed through as "the applied Threads value" (`mxq.h:639`). Since the contract requires `mxq_engine_prepare` to "recompute the same plan", any clamp `prepare` later applies will make `plan` and `prepare` disagree. **Correction:** document in `mxq.h` that a zero `active_processor_count` yields `threads == 1`, and add an explicit upper bound constant (`MXQ_ENGINE_MAX_THREADS`) that both `plan` and `prepare` clamp to.

### Finding 1.5 — `struct_size` write-back is undocumented — **should-fix**

```
  out ss=size+64   -> MXQ_OK, reported struct_size=40 (sizeof=40)
```

The core overwrites the caller's `struct_size` on every out struct with the number of bytes it actually wrote. That is sensible and is what makes the append-only rule usable, but `mxq.h:20-22` only says the *caller* sets it before the call. Bindings cannot rely on undocumented behaviour. **Correction:** add to the conventions block: "On return, an out struct's `struct_size` is the number of leading bytes the core wrote; fields beyond it were not touched."

### Finding 1.6 — `mxq_archive_supported_versions` out-parameter optionality is undocumented — **nit**

```
  supported_versions(NULL,NULL) -> MXQ_ERR_ARG_NULL
  supported_versions(&mn,NULL)  -> MXQ_OK mn=1
  supported_versions(NULL,&cur) -> MXQ_OK cur=1
```

Each is individually optional; the doc comment says nothing, unlike `mxq_rules_evaluate` and `mxq_store_import`, which do. **Correction:** add "`out_min_readable` and `out_current` are each optional, but not both NULL."

### Finding 1.7 — `mxq_status_domain` on a negative status — **nit**

```
  domain(-1)=0 name=MXQ_STATUS(unknown)
  domain(-2500)=-2000 name=MXQ_STATUS(unknown)
```

`(status / 1000) * 1000` truncates toward zero, so a negative status maps to `MXQ_DOMAIN_OK` or to a negative non-domain. No negative code exists today, so this is unreachable. **Correction:** in `mxq_status_domain`, return `MXQ_DOMAIN_INTERNAL` for `status < 0`, or state in `mxq.h` that the function's domain is `MxqStatus >= 0`.

### Finding 1.8 — `MXQ_DETAIL_CAP` is provisional but frozen into `MxqError` at API 1.0.0 — **nit**

> `mxq.h:111-113` — "MxqError.detail: a short English diagnostic. **Provisional**; docs/core-interface.md leaves the concrete capacity to be finalised against measured worst cases."

`MXQ_API_VERSION_MAJOR 1` is compiled in, and `core-interface.md:242` forbids "struct-field changes" within a major version. Changing `MXQ_DETAIL_CAP` changes `sizeof(MxqError)` and moves nothing but resizes a field in place, which is not an append-only addition. The contract's **Need to discuss** does sanction finalising it during implementation, so this is only a sequencing note. **Correction:** finalise the cap before the first binding is generated, or note in `mxq.h` that `MXQ_API_VERSION` is not frozen until it is.

---

## 2. The header's own claims

```
$ xcrun clang -fsyntax-only -std=c17 -Wall -Wextra -pedantic -I core/include t_c17.c
CLEAN
$ xcrun clang -fsyntax-only -std=c17 -Wpadded -I core/include t_c17.c
CLEAN
c99 CLEAN / c11 CLEAN / gnu17 CLEAN / c23 CLEAN   (each with -Wall -Wextra -pedantic -Wpadded)
CPP CLEAN                                          (clang++ -std=c++20, same flags)
$ xcrun clang -fsyntax-only -Weverything …
warning: include location '/usr/local/include' is unsafe for cross-compilation   # environment, not the header
```

The header is also idempotent under double inclusion (the test TU includes it twice).

**No implicit padding on any ABI.** `-Wpadded` is silent for `x86_64-pc-windows-msvc`, `i386-pc-windows-msvc`, `aarch64-pc-windows-msvc`, `x86_64-unknown-linux-gnu` and `armv7-none-eabi` as well as Apple arm64, and the record layouts are byte-identical:

```
$ clang -cc1 -triple <t> -fdump-record-layouts … && diff
LAYOUT IDENTICAL on Apple arm64 and Windows x64 MSVC ABI
```

**A pure-C translation unit links against the C++ archive:**

```
$ xcrun clang -std=c17 -Wall -Wextra -pedantic plan_test.c build/libmxqcore.a -lc++ -o plan_test
PURE-C LINK AGAINST C++ ARCHIVE: OK
```

**Swift module map: works.** A `module.modulemap` over the unmodified header compiles and runs under `-swift-version 6 -strict-concurrency=complete`. The callback typedef imports as a usable `MxqSearchCallback`, the anonymous-enum constants import as `Int32`, and the fixed-capacity arrays import as tuples without incident.

```
mxq_core_version rc=0 api=1.0.0
domain(3002)=3000   name=MXQ_ERR_RULES_ILLEGAL_MOVE
plan rc=0 hash=4096 sufficient=1
start fen (47) = rcnkncr/p1ppp1p/7/7/7/P1PPP1P/RCNKNCR w - - 0 1
layout: MxqError=160 MxqPosition=120 MxqSearchResult=168 MxqVersion=232
```

**No P/Invoke-hostile construct.** Scanned and confirmed absent: unions, anonymous unions, bitfields, `#pragma pack`, `long`, `bool`/`_Bool`, `float`/`double`, `wchar_t`, nested struct definitions, VLAs. Every enumerated field is an `int32_t` typedef. `MXQ_CALL` is `__cdecl` on Windows, the P/Invoke default.

### Finding 2.1 — argument-domain errors do not assert in debug builds — **BLOCKING**

> `core-interface.md:208` — "Programming errors — the argument domain except buffer-too-small, plus not/already-initialized and read-only-session violations — **assert in debug builds**, return their code in release builds, and never change state."
> `mxq.h:141-145` repeats this verbatim as a claim about this header.

The implementation does not. `mxq::begin_out` and `mxq::check_in` (`core/src/mxq_internal.cpp:53-83`) return `MXQ_ERR_ARG_NULL` / `MXQ_ERR_ARG_STRUCT_SIZE` with no `assert`. Verified in a Debug build with asserts demonstrably live:

```
$ grep -c NDEBUG build-debug/build.ninja
0
$ FLAGS = -g -std=c++20 -arch arm64 -fPIC …      # no -DNDEBUG
$ ./a                                            # control: assert(0) in the same toolchain
Assertion failed: (0), function main, file a.cpp, line 2.
control assert exit=134

$ ./assert_test                                  # linked against build-debug/libmxqcore.a
Debug build, mxq_engine_plan(NULL,...)  -> MXQ_ERR_ARG_NULL      (returned; no assert fired)
Debug build, budget struct_size = 1     -> MXQ_ERR_ARG_STRUCT_SIZE (returned; no assert fired)
Debug build, mxq_core_version ss = 2    -> MXQ_ERR_ARG_STRUCT_SIZE (returned; no assert fired)
Debug build, mxq_core_version(NULL)     -> MXQ_ERR_ARG_NULL      (returned; no assert fired)
```

Blocking because `begin_out` and `check_in` are the two helpers every one of the remaining 44 functions will be built on: the miss is systemic, not local, and the header asserts the opposite. Note that `copy_bounded`, `write_string` and `percent` in the same file *do* assert, so the omission is inconsistent even internally.

**Correction:** in `mxq_internal.cpp`, add `assert(out != nullptr && "required out pointer was null");` before the `MXQ_ERR_ARG_NULL` return in `begin_out`, the same for `in` in `check_in`, and `assert(declared >= min_known && "caller struct_size predates this interface version");` before each `MXQ_ERR_ARG_STRUCT_SIZE` return. `MXQ_ERR_ARG_BUFFER_TOO_SMALL` in `write_string` correctly stays assertion-free.

### Finding 2.2 — `begin_out` / `check_in` are always called with `min_known == sizeof`, contradicting their own documented intent — **should-fix**

> `mxq_internal.hpp:51-53` — "`known` is sizeof the struct as this build declares it; the caller's declared size **may be smaller (an older frontend)** or larger (a newer one), and either is accepted as long as it covers the version-1 prefix."

Every one of the three call sites passes the full current `sizeof` as `min_known`:

```cpp
mxq::check_in(budget, …, sizeof(MxqEngineBudget), sizeof(MxqEngineBudget), err);   // mxq_engine.cpp:20-23
mxq::begin_out(out,    …, sizeof(MxqEnginePlan),   sizeof(MxqEnginePlan),   err);  // mxq_engine.cpp:27-29
mxq::begin_out(out,    …, sizeof(MxqVersion),      sizeof(MxqVersion),      err);  // mxq_core.cpp:10-13
```

Confirmed by execution — a one-byte-short struct is rejected today:

```
  budget ss=size-1 -> MXQ_ERR_ARG_STRUCT_SIZE
  budget ss=size+64-> MXQ_OK
```

Inert while every struct is at its version-1 size, and it becomes wrong the moment a field is appended: every older caller starts failing, which is exactly what `struct_size` exists to prevent. **Correction:** introduce a per-struct `MXQ_<STRUCT>_SIZE_V1` constant and pass that as `min_known` at every call site, so the guard means "covers the version-1 prefix" as documented rather than "is exactly this build's size".

### Finding 2.3 — ClangSharp will name every generated enum type after a source line number — **should-fix** (analysis; not executed — no .NET SDK in this workspace)

Every vocabulary in `mxq.h` is an *unnamed* `enum { … }` beside an `int32_t` typedef. ClangSharp derives a C# type name for an unnamed enum from its source location, so `enum {` at `mxq.h:149` becomes something like `__AnonymousEnum_mxq_L149_C1`. Adding a single comment line above shifts every subsequent enum's generated type name, producing gratuitous churn in the generated C# on edits that change nothing semantically.

I could not run `ClangSharpPInvokeGenerator` here (`which dotnet` → not found), so this is reasoned from the generator's naming rule rather than executed; it should be confirmed once the Windows toolchain is pinned.

**Correction:** give each enum a tag while keeping the `int32_t` typedef — `typedef int32_t MxqStatus; enum MxqStatusCode { … };`. That is zero ABI change, preserves the header's stated rationale (fields stay `int32_t`, so an unknown value is still a defined value of the type), and makes both generators deterministic.

### Finding 2.4 — "every struct is … Sendable in Swift" is false — **nit** (a contract defect the author did not report)

> `core-interface.md:11`, transcribed at `mxq.h:30-32` — "…so **every struct** is trivially copyable, blittable in C#, and Sendable in Swift."

Executed under `-swift-version 6 -strict-concurrency=complete`:

```
sendable.swift:15:1: error: type 'MxqCoreConfig' does not conform to the 'Sendable' protocol
```

The other twelve do conform:

```
Sendable: MxqError, MxqVersion, MxqMove, MxqPosition, MxqGameStatus, MxqGameConfig,
          MxqRecordSummary, MxqArchiveInfo, MxqEngineBudget, MxqEnginePlan,
          MxqSearchRequest, MxqSearchResult
```

`MxqCoreConfig` carries the two borrowed `const char *` paths, which the very next sentence of the header acknowledges. **Correction:** in the contract and in `mxq.h`, say "every struct except `MxqCoreConfig`, whose two borrowed path pointers are valid only for the duration of `mxq_core_init`".

---

## 3. The build and the runner

```
$ cmake -S core -B /tmp/mxq-pr26/build -G Ninja -DMXQ_WARNINGS_AS_ERRORS=ON
-- Mini Xiangqi core: fork revision 77d602e00db0527781e6abb76802bf1757f7e6fa
-- Mini Xiangqi core: variant minixiangqiaxf
-- Mini Xiangqi core: core revision 8ac078e7ec43cd398ec1eb864aa9a4d8e88b2161
-- Mini Xiangqi core: fairy-stockfish not vendored
-- Mini Xiangqi core: sqlite not vendored
$ cmake --build /tmp/mxq-pr26/build
[14/14] Linking CXX executable tests/mxq_core_tests      # zero warnings, -Werror
```

Against the real `fixtures/rules/`:

```
16 fixtures: 0 passed, 0 failed, 16 not implemented, 0 errored
0 of 85 normative expectations evaluated
$ echo $?
0
```

**Confirmed: 16 NOT IMPLEMENTED, nothing reports PASS.** The gate is structural — `main.cpp:561` returns `Verdict::NotImplemented` before `evaluate_fixture` is ever reached when `RulesFacade::open` fails, and `open` cannot succeed unless `MXQ_TEST_RULES_FACADE` is 1. I also checked the other direction: configuring with `-DMXQ_ENABLE_RULES_FACADE=ON` is an honest **link failure**, not a silent pass:

```
Undefined symbols for architecture arm64:
  "_mxq_core_init", "_mxq_core_shutdown", "_mxq_rules_evaluate", "_mxq_rules_legal_moves"
```

I built 24 malformed fixtures of my own and ran them. **20 were reported ERROR**; exit 1.

```
ERROR  b01-invalid-json     invalid JSON: byte 27: expected a member name
ERROR  b02-empty            invalid JSON: byte 0: unexpected end of document
ERROR  mx-rep-001           id "mx-rep-001" does not match the file name "b03-id-mismatch"
ERROR  b04-missing-rationale fixture: missing member "rationale"
ERROR  b05-unknown-member   fixture: unknown member "extra"
ERROR  b06-bad-state        …"won" is not an accepted state
ERROR  b07-ongoing-with-reason / b08-null-reason  reason must be null exactly when the state is ongoing
ERROR  b09-prefix-too-long / b17 / b18            fixture.boundary.prefix_len: outside the move history
ERROR  b10-duplicate        invalid JSON: duplicate member name "id"
ERROR  b11-move-not-string  fixture.moves[0]: expected string, found number
ERROR  b12-in-check-string  fixture.assertions.in_check: expected boolean, found string
ERROR  b13-applied-missing  fixture.assertions.applied[0]: missing member "in_check"
ERROR  b14-assertions-array fixture.assertions: expected object, found array
ERROR  b15-bad-reason       …"resignation" is not an accepted reason
ERROR  b19-root-array       the document is not an object
ERROR  b20-trailing         trailing content after the document
ERROR  b24-deep             nesting is deeper than the reader allows
NOT IMPL  b16-occurrence-overflow    <- see 3.1
NOT IMPL  b21-malformed-move         <- see 3.3
NOT IMPL  b22-wrong-variant          <- see 3.3
NOT IMPL  b23-empty-area
```

A directory named `b25-directory.json` was correctly ignored (regular files only).

Exit codes are right for a CI gate:

```
malformed dir exit=1      real fixtures exit=0      missing dir exit=2
empty dir     exit=2      bad arg        exit=2      --help exit=0
unwritable --junit exit=2
```

### Finding 3.1 — undefined behaviour in the fixture loader on an out-of-range number, and the value is then accepted — **should-fix**

`core/tests/mxq_fixture.cpp:101-107`:

```cpp
bool integer(const JsonValue &v, int64_t &out, const std::string &where) {
    const double d = v.number();
    if (d != std::floor(d)) { return fail(where + ": expected an integer"); }
    out = static_cast<int64_t>(d);
```

`floor(inf) == inf`, so an out-of-range literal passes the integrality test and is cast. Built with `-fsanitize=address,undefined`:

```
$ build-san/tests/mxq_core_tests --fixtures /tmp/mxq-pr26/bad
core/tests/mxq_fixture.cpp:106:36: runtime error: inf is outside the range of
representable values of type 'long long'
SUMMARY: UndefinedBehaviorSanitizer: undefined-behavior …
```

Worse than the UB: the fixture (`"at_occurrence": 1e400`) was **not** reported as an error — it came through as `NOT IMPL`. `prefix_len` survives only by accident, because the saturated result then fails the separate range check. `at_occurrence` has no range check at all. The loader's own header comment says "this loader is strict: an unknown member, a missing member, or a member of the wrong type is a load error rather than something quietly ignored"; an unrepresentable number is quietly accepted. The same runner over the real fixtures is clean under ASan+UBSan.

**Correction:** in `Loader::integer`, reject before casting — `if (!(d >= -9007199254740992.0 && d <= 9007199254740992.0) || d != std::floor(d)) return fail(where + ": expected an integer");` — and add a range check for `at_occurrence` (`0 <= n`, and no larger than `moves.size() + 1`).

### Finding 3.2 — an unreadable directory entry is handled order-dependently — **should-fix**

`core/tests/main.cpp:486-496` reuses one `std::error_code` across the loop and inspects it only after the loop, so only the *last* entry's status survives.

```
$ ls sym/  → mx-rep-001.json  zz-dangling.json -> /definitely/not/here
mxq_core_tests: cannot read /tmp/mxq-pr26/sym: No such file or directory
real exit=2                       # the directory is fine; the entry is not — and the whole run aborts

$ ls sym2/ → aa-dangling.json -> /definitely/not/here  mx-rep-001.json
1 fixtures: 0 passed, 0 failed, 1 not implemented, 0 errored
real exit=0                       # the same broken entry, silently dropped
```

Whether an unreadable fixture aborts the run or vanishes from it depends on where its name sorts. For a harness whose whole job is to be the independent authority, silently dropping a fixture is the more dangerous half. **Correction:** declare the error code inside the loop, and on failure push a `Verdict::Error` result for that entry (`entry.path()`, message `ec.message()`) instead of touching the outer state; keep the outer `ec` for `directory_iterator` construction only.

### Finding 3.3 — the loader does not validate `variant` or move syntax — **should-fix**

`fixtures/rules/README.md`: "`variant` — the ruleset identity the position is defined against; **always `minixiangqi`**" and "`moves` — … in canonical coordinate notation (`<from><to>`, e.g. `b1b4`)". Neither is checked: my `b22-wrong-variant` (`"variant": "chess"`) and `b21-malformed-move` (`"moves": ["zz99", …]`) both loaded successfully. `zz99` will become a FAIL rather than an ERROR once the facade lands, misattributing a fixture-schema violation to the core.

**Correction:** in `fixture_load`, add `if (out.variant != "minixiangqi") return load.fail("fixture.variant: only \"minixiangqi\" is defined");` and a `^[a-g][1-7][a-g][1-7]$` check — the taxonomy's own definition at `mxq.h:205` — applied to every string in `moves`, `legal_moves`, `rejected_moves` and `applied[].move`.

### Finding 3.4 — `ctest` reports the suite green while nothing was evaluated — **should-fix**

> `main.cpp:20-23` — "NOT IMPLEMENTED does not fail the run … but it is stated on its own summary line and is emitted as a skipped test case in the JUnit report, **so no CI dashboard shows this suite as green-and-complete**."

The JUnit half is true (`skipped="16"`, verified). But `ctest` is the invocation `core/CMakeLists.txt:12` and `core/README.md` both document, and it shows exactly what the comment says cannot happen:

```
$ ctest --test-dir /tmp/mxq-pr26/build --output-on-failure
100% tests passed, 0 tests failed out of 1
```

**Correction:** have the runner return `77` when every fixture was NOT IMPLEMENTED, and add `set_tests_properties(rules_fixtures PROPERTIES SKIP_RETURN_CODE 77)` in `core/tests/CMakeLists.txt`, so `ctest` reports the test as Skipped. Otherwise drop the claim from `main.cpp`.

### Finding 3.5 — the boundary check would spuriously fail an `ongoing` fixture carrying a `boundary` — **nit**

`main.cpp:320-328` fails a fixture when the boundary prefix reports the *same* state as the final position. For a fixture whose asserted state is `ongoing`, the prefix is also `ongoing`, so it fails by construction. The loader permits that combination. No current fixture triggers it — I checked all 16; the seven with a non-null boundary all assert a terminal or claimable state. **Correction:** reject `boundary` on an `ongoing` fixture in `fixture_load`, since a boundary pins when an outcome attaches and an ongoing fixture has none.

### Finding 3.6 — unevaluated checks are counted as evaluated on FAIL — **nit**

`main.cpp:591-593` adds `r.checks` to `checks_evaluated` for any FAIL, including one where `facade.legal_moves` itself failed and the legal-move and rejected-move expectations were never compared. **Correction:** count checks as they are performed rather than from `check_count()`.

---

## 4. `mxq_engine_plan`

I re-derived the arithmetic from `engine-integration.md:105-107` independently, in C, and compared field by field against the core's output across every boundary and a sweep of every anchor ±3 bytes.

```
$ ./plan_test
--- 4 GiB cap ---
64 GiB avail / 64 GiB phys          -> hash=4096 suff=1  budget=4294967296
phys exactly 8 GiB (50% == cap)     -> hash=4096 suff=1  budget=4294967296
phys 8 GiB - 2 (just below cap)     -> hash=4032 suff=1  budget=4294967295
--- 50% of physical binding ---
phys 4 GiB                          -> hash=2048  |  phys 1 GiB -> hash=512  |  phys 1 GiB - 1 -> hash=448
--- reserve: greater of 20% or 128 MiB ---
avail 640 MiB (20% == 128 MiB)      -> reserve=134217728
avail 640 MiB - 1                   -> reserve=134217728   (20% floors below the minimum)
avail 641 MiB (20% > 128 MiB)       -> reserve=134427443
avail 128 MiB exactly               -> usable=0, hash=0, suff=0
--- 64 MiB rounding ---
usable 383 MiB -> hash=320 | usable 384 MiB - 1 -> hash=320 | usable 384 MiB -> hash=384
--- 256 MiB minimum ---
usable 256 MiB exactly  -> hash=256 suff=1
usable 256 MiB - 1      -> hash=192 suff=0
--- zero and extreme probes ---
zero probe              -> reserve=134217728 usable=0 budget=0 hash=0 suff=0
avail 64 GiB, phys 0    -> budget=0 hash=0 suff=0
UINT64_MAX both         -> hash=4096 suff=1        (no overflow)
--- exhaustive sweep around every boundary ---
  swept 3268 combinations, 0 mismatches

3298 cases, 0 mismatches against the independently derived reference
```

**No disagreement with `engine-integration.md` at any boundary.** The 4 GiB cap, 50 %-of-physical, `max(20 %, 128 MiB)` reserve, `max(0, available - reserve)`, 64 MiB round-down, the 256 MiB minimum and the zero probe all behave exactly as the contract states, including the tie at exactly 640 MiB where the two reserve terms are equal. `mxq::percent` is exact (`(v/100)*p + ((v%100)*p)/100 == floor(v*p/100)`) and does not overflow at `UINT64_MAX`. Argument handling is correct (`MXQ_ERR_ARG_NULL`, `MXQ_ERR_ARG_STRUCT_SIZE`), the function touches no core state, and it works before `mxq_core_init`.

The only issues here are the undocumented `threads` behaviour (finding 1.4) and the `min_known` guard (finding 2.2). The arithmetic itself is correct.

---

## 5. `pinned-inputs.json`

Every established value verified against reality.

```
$ git -C Fairy-Stockfish log -1 --format='%H %cI %s' 77d602e00db0527781e6abb76802bf1757f7e6fa
77d602e00db0527781e6abb76802bf1757f7e6fa 2026-07-27T11:01:31-07:00 Merge pull request #1 from ppppvz/minixiangqi/soldier-chase-exemption
$ git -C Fairy-Stockfish log -1 … c19b5f6c66894fdb0e88d0dd100e3885f744760a
c19b5f6c66894fdb0e88d0dd100e3885f744760a 2026-07-23T19:20:28+02:00 Update contribution support links in README
$ … 232ca36b9cdede1c0ce574ddf17b20fdc8d00a34 2026-07-27T10:46:38-07:00 Add promotedSoldiersChaseable to control soldier chase targets
$ … ebe320a563ea03fce01fc3ef0822775587cc36c4 2026-07-27T11:01:24-07:00 Fix review findings: scope the property's documented claim
```

All four revisions exist, and both recorded timestamps match the commits exactly.

```
$ wc -c < .git/minixiangqi-control/nnue/minixiangqi-12c45d5da817.nnue
 4333499
$ shasum -a 256 …
12c45d5da817e7948cc22f2f295a0781dabd379be472006360c36676f1cc09ce
```

**Byte length and SHA-256 match the actual file exactly.** No hash was invented: every unestablished value is an explicit `null` or `[]` with an `"established": false` marker and a `_note` naming why — the variant `.ini` hash, SQLite's version and hash, all four platforms' flags, the whole Windows toolchain, the static-library artifact, and each of the five unlanded fork patches with `"merge_revision": null`. The claim in the PR body holds.

Against `engine-integration.md:162-168`, the five required contents are all present. Two gaps:

### Finding 5.1 — the fork's license is not recorded — **should-fix**

> `engine-integration.md:179` — "Packaged engine binaries require recorded origin, revision, **license**, byte length, and cryptographic hash."

The manifest records the fork's repository and revision but no license, and the `fork.static_library` object has only `artifact_name` and `build_command` — no `sha256` or `byte_length` keys at all, not even as nulls. That contradicts the file's own stated policy: "Every value whose 'established' field is false is recorded as null or an empty list **rather than as a plausible-looking placeholder**… each listed rather than implied by an absence." The license is establishable today (GPL-3.0-or-later, per the repository's `LICENSE`). **Correction:** add `"license": "GPL-3.0-or-later"` under `fork`, and `"byte_length": null, "sha256": null` inside `fork.static_library`.

### Finding 5.2 — the manifest calls its field names provisional while the build already consumes three of them — **should-fix**

> `pinned-inputs.json:5` — "docs/engine-integration.md leaves the manifest's concrete field names and schema version to be fixed **when the first build consumes it**. **Nothing here has been consumed by a packaging build yet**, so the names below are a proposal, not a frozen schema."

But this same PR makes the core build consume it:

```cmake
mxq_pinned_get(MXQ_BUILD_FORK_REVISION fork revision)      # core/CMakeLists.txt:68
mxq_pinned_get(MXQ_BUILD_VARIANT_ID variant id)            # :69
mxq_pinned_get(MXQ_BUILD_NNUE_SHA256 network sha256)       # :70
```

and bakes them into `MxqVersion`, which the contract calls load-bearing rather than diagnostic:

```
$ build/tests/mxq_core_tests …
  fork revision   77d602e00db0527781e6abb76802bf1757f7e6fa
  variant         minixiangqiaxf
  network         12c45d5da817e7948cc22f2f295a0781dabd379be472006360c36676f1cc09ce
```

The condition the contract set for freezing the names is met by this PR. **Correction:** narrow `_field_names_are_provisional` to say that `fork.revision`, `variant.id` and `network.sha256` are frozen because `core/CMakeLists.txt` reads them, and that only the names no build consumes remain provisional. `mxq_pinned_get` should also reject an empty or `null` result rather than silently baking it into `MxqVersion`.

---

## 6. The seven reported contract defects, plus what was not reported

| # | Reported defect | Real? | Chosen resolution |
|---|---|---|---|
| 1 | `core-interface.md:218` vs `:236` on what is callable inside a callback | **yes** | followed 218 — **but only half of the header does; see 6.1** |
| 2 | Who resolves a Random first mover is unstated | **yes** | ambiguity flagged, but silently decided in the header — see 6.2 |
| 3 | Free Play has no `human_side` / `ai_level` / `first_mover_choice` | **yes** | `*_NONE = -1` — correct, and documented as having no serialized counterpart |
| 4 | The first-mover enum is used but never named | **yes** (`:45` names three enums and refers to "the first-mover choice") | `MxqFirstMoverChoice` — correct |
| 5 | `:195` / `:197` require a required-size and a first-illegal index but say where neither rides | **partly** — `:92` does give `mxq_rules_evaluate` an `out_first_illegal_index` parameter, so only the *other* replaying functions lack a home | both put in `MxqError`, creating a second home — see finding 1.3 |
| 6 | `MxqSearchRequest` carries only `movetime_ms` | **yes**, but this is redundancy rather than a defect — it is a deliberate cross-check the contract requires (`:130`) | kept |
| 7 | `mxq_store_history_page` has both `limit` and `cap` | **yes** | **reported but not closed — see 6.3** |

### Finding 6.1 — the callback contradiction was transcribed into `mxq.h`, not resolved — **BLOCKING**

The PR body says: "Line 218 lists four functions as callable 'including callbacks'; line 236 says only the status and blob helpers are legal inside a callback. **The scaffold follows 218.**"

The per-function comments do follow 218:

> `mxq.h:761` (`mxq_core_version`) — "Thread: any thread, including inside a search callback."
> `mxq.h:1084` (`mxq_engine_plan`) — "Thread: any thread, including inside a search callback."
> `mxq.h:1015` (`mxq_rules_start_fen`) — "Thread: any thread, including inside a search callback."
> `mxq.h:1265` (`mxq_archive_supported_versions`) — "Thread: any thread, including inside a search callback."

But the `MxqSearchCallback` documentation block follows 236, verbatim:

> `mxq.h:691-693` — "It must copy and return. **Inside it, only mxq_status_domain, mxq_status_name, mxq_blob_bytes, mxq_blob_len and mxq_blob_release are legal; every other core function returns MXQ_ERR_ARG_REENTRANT.**"

Those four functions are "every other core function". `mxq.h` therefore states, normatively and in the same file, both that they are callable inside a callback and that calling them there returns `MXQ_ERR_ARG_REENTRANT`. The header's own preamble makes both statements normative: "Each function below states the thread it may be called from … and every function that delivers a callback states which thread delivers it."

This is blocking, not cosmetic, precisely because of the property the PR body itself argues for: this header is the single input from which two bindings are generated independently. A Swift actor wrapper reading line 761 will permit `mxq_core_version` from the trampoline; a C# `[UnmanagedCallersOnly]` wrapper reading line 692 will forbid it. Nothing downstream can reconcile them, and the contradiction was carried forward rather than removed.

**On the merits, following 218 is the right resolution**, and the scaffold's judgement is sound: line 236's rationale is that the callback "must not block, because the engine thread is the resource it would deadlock", and all four functions are pure reports of compiled-in constants that touch no core state and take no lock. `mxq_engine_plan` is expressly "A pure function: it touches no core state, initialises nothing". Denying them would buy nothing and would make `mxq_status_name` legal while `mxq_core_version` — equally pure — is not.

**Correction:** replace `mxq.h:691-693` with: "Inside it, only the functions whose own documentation says 'including inside a search callback' are legal — `mxq_status_domain`, `mxq_status_name`, `mxq_blob_bytes`, `mxq_blob_len`, `mxq_blob_release`, `mxq_core_version`, `mxq_rules_start_fen`, `mxq_engine_plan` and `mxq_archive_supported_versions`, all of which are pure and take no lock; every other core function returns `MXQ_ERR_ARG_REENTRANT`." Then file the contract change against `core-interface.md:236` to match, so the two documents agree rather than the header silently overriding one line of the contract.

### Finding 6.2 — reported defect 2 was flagged but then silently decided — **should-fix**

The PR reports that who resolves a Random first mover is unstated, then the header decides it:

> `mxq.h:554-556` — "`human_side` is **the resolved side**: it is `MXQ_COLOR_RED` or `MXQ_COLOR_BLACK` in a human-versus-AI game even when `first_mover_choice` is `MXQ_FIRST_MOVER_RANDOM`"

Since `MxqGameConfig` is the *input* to `mxq_game_create`, requiring a resolved side there means the frontend resolves. That is the direction that makes the accepted ordering unenforceable by the core:

> `engine-integration.md:82` — "**Resolve** a Random first-mover choice, as part of the same creation operation and **only after preparation succeeds**."

If the frontend resolves, the core cannot enforce "only after preparation succeeds", and `game-data.md:90` ("Only successful 开始对局 creation commits the resolved human side") loses its guarantee that a failed creation cannot leak a resolved side. The other resolution — accept `MXQ_COLOR_NONE` as input when `first_mover_choice` is `MXQ_FIRST_MOVER_RANDOM` and have the core resolve inside `mxq_game_create`, reporting the result through `mxq_game_config` — satisfies both documents.

**Correction:** either take that second option, or state explicitly in `mxq.h` that the frontend resolves and raise the conflict with `engine-integration.md:82` in the same contract change that resolves finding 6.1.

### Finding 6.3 — reported defect 7 is reported but not closed in the header — **should-fix**

`mxq_store_history_page` still takes both `uint32_t limit` and `size_t cap`, and `mxq.h:1341-1344` says only that "`*out_count` is the number written rather than the total". It does not say what happens when `limit > cap` — buffer-too-small, or silently clamp to `cap`. Since the return convention for the counted-output family is itself unspecified (finding 1.2), a binding author has nothing to go on. **Correction:** add "When `cap` is smaller than `limit`, the call returns `MXQ_ERR_ARG_BUFFER_TOO_SMALL` with `MxqError.required_size` set to `limit`; it never silently returns fewer records than `limit` when more exist."

### Defects the author did not report

Collected here for the contract change; each is detailed above.

- **6.1** is itself half-unreported: the PR claims the contradiction was resolved in favour of 218; half the header follows 236.
- **1.1** — `mxq.h:759` "the only core function that is", contradicted three times in the same header.
- **1.2** — the count-only probe's return status is unspecified in both the contract and the header.
- **1.3** — the fix for reported defect 5 creates a second home for the first-illegal index.
- **2.1** — the accepted "assert in debug builds" rule is not implemented (blocking).
- **2.4** — `core-interface.md:11`'s "every struct is … Sendable in Swift" is false for `MxqCoreConfig`, demonstrated by compiling it.
- **1.8** — `MXQ_DETAIL_CAP` is provisional while `MXQ_API_VERSION` is already 1.0.0 and `:242` forbids struct-field changes within a major version.
- **5.1**, **5.2** — the manifest omits the fork license and calls its schema provisional while the build consumes it.

---

## Summary

| Severity | Count | Findings |
|---|---|---|
| **Blocking** | 2 | 6.1 (callback contradiction reproduced inside `mxq.h`), 2.1 (argument-domain errors do not assert in debug builds) |
| **Should-fix** | 13 | 1.1, 1.2, 1.3, 1.4, 1.5, 2.2, 2.3, 3.1, 3.2, 3.3, 3.4, 5.1, 5.2, 6.2, 6.3 |
| **Nit** | 6 | 1.6, 1.7, 1.8, 2.4, 3.5, 3.6 |

What the PR gets right, verified rather than taken on trust: all 53 signatures match the contract exactly; every vocabulary matches `game-data.md` constant for constant; every error code sits in the right 1000-block with no gaps; no struct carries implicit padding on any of six ABIs and the layouts are byte-identical between Apple arm64 and Windows x64; a pure-C translation unit links against the C++ archive; the Swift module map works under Swift 6 strict concurrency; the runner reports 16 NOT IMPLEMENTED with nothing passing and cannot be made to pass an unevaluated fixture; exit codes gate CI correctly; `mxq_engine_plan` agrees with an independently derived reference in 3298 cases with zero mismatches; and every established value in `pinned-inputs.json` matches reality, with no invented hash.

**DO NOT MERGE**
