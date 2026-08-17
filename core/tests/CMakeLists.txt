# The one shared C++ test runner.
#
# It links the core static library and runs without any frontend, which is what
# docs/architecture.md requires of it on every development platform. It has no
# third-party dependency and fetches nothing, so it configures and builds the
# same way on a machine that has only a compiler and CMake.

add_executable(mxq_core_tests
  main.cpp
  mxq_fixture.cpp
  mxq_json.cpp
  mxq_rules_facade.cpp
)

target_link_libraries(mxq_core_tests PRIVATE mxq::core mxq_warnings)

# fixtures/ lives at the repository root rather than under core/: it is the
# independent authority the core is validated against, not an implementation
# detail of the core it validates. The path below is only the default; the
# runner also accepts --fixtures and $MXQ_FIXTURES_DIR, which is how CI points
# it at a checkout in another location.
target_compile_definitions(mxq_core_tests PRIVATE
  MXQ_FIXTURES_DIR_DEFAULT="${MXQ_REPO_ROOT}/fixtures/rules"
  MXQ_TEST_RULES_FACADE=$<IF:$<AND:$<BOOL:${MXQ_ENABLE_RULES_FACADE}>,$<BOOL:${MXQ_RULES_FACADE_IMPLEMENTED}>>,1,0>
  # The core loads the bundled variant configuration from its asset directory.
  # The runner's store directory is a scratch path, so the two are not the same
  # place and the asset directory has to be told to it explicitly.
  MXQ_ASSETS_DIR_DEFAULT="${CMAKE_CURRENT_SOURCE_DIR}/../assets"
)

add_test(NAME rules_fixtures
         COMMAND mxq_core_tests
                 --junit "${CMAKE_CURRENT_BINARY_DIR}/rules-fixtures.xml")
set_tests_properties(rules_fixtures PROPERTIES
  LABELS "rules;fixtures"
)

# The store-foundation runner: the SQLite-backed store mxq_core_init opens,
# asserted against scratch databases, plus the deterministic-identity seam.
# It links the vendored SQLite directly so schema assertions query the closed
# database rather than trust the DDL, and it includes the core's internal
# headers on purpose — the identity provider has no public accessor, and the
# white-box read is the test's whole point. Both runs need no engine; with the
# engine compiled in, mxq_core_init also loads the variant configuration, so
# the assets default is supplied the same way as above.

add_executable(mxq_store_tests
  mxq_store_tests.cpp
)
target_link_libraries(mxq_store_tests PRIVATE mxq::core mxq::sqlite mxq_warnings)
target_include_directories(mxq_store_tests PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/../src"
)
target_compile_definitions(mxq_store_tests PRIVATE
  MXQ_ASSETS_DIR_DEFAULT="${CMAKE_CURRENT_SOURCE_DIR}/../assets"
)

add_test(NAME store_foundation COMMAND mxq_store_tests)
set_tests_properties(store_foundation PROPERTIES
  LABELS "store"
)

# The archive-codec runner: the golden and rejection corpora in
# fixtures/archive/, walked through the public C surface only. It shares the
# fixture runner's JSON reader for the expectation sidecars — that reader is
# fixture-side code and is deliberately not what the codec parses archives
# with; the core carries its own reader for that.
#
# It behaves in each configuration exactly as rules_fixtures does. With the
# engine, mxq_archive_validate exists and every expectation is evaluated;
# without it, validate is absent from the library and the runner reports its
# expectations as NOT IMPLEMENTED rather than referencing a symbol that would
# fail to link.

add_executable(mxq_archive_tests
  mxq_archive_tests.cpp
  mxq_json.cpp
)
target_link_libraries(mxq_archive_tests PRIVATE mxq::core mxq_warnings)
target_compile_definitions(mxq_archive_tests PRIVATE
  MXQ_ARCHIVE_FIXTURES_DIR_DEFAULT="${MXQ_REPO_ROOT}/fixtures/archive"
  MXQ_TEST_RULES_FACADE=$<IF:$<AND:$<BOOL:${MXQ_ENABLE_RULES_FACADE}>,$<BOOL:${MXQ_RULES_FACADE_IMPLEMENTED}>>,1,0>
  MXQ_ASSETS_DIR_DEFAULT="${CMAKE_CURRENT_SOURCE_DIR}/../assets"
  MXQ_TEST_GOMOKU_FACADE=$<IF:$<AND:$<BOOL:${MXQ_ENABLE_GOMOKU_FACADE}>,$<BOOL:${MXQ_ENABLE_RULES_FACADE}>>,1,0>
)

add_test(NAME archive_fixtures COMMAND mxq_archive_tests)
set_tests_properties(archive_fixtures PROPERTIES
  LABELS "archive;fixtures"
)

# The session runner: the store round-trip scenarios in fixtures/store/, the
# interface properties a game cannot express (a failed commit, a concurrent
# call, a tombstoned handle), and the core's own SHA-256 against the published
# vectors.
#
# Like mxq_store_tests it links the vendored SQLite directly — the failed-commit
# case takes the database's write lock from a second connection, so the failure
# arrives through the store's own path rather than through a seam that exists
# only in tests — and includes the core's internal headers on purpose, for the
# identity provider and the session's owner guard.
#
# It degrades in the engine-less configuration exactly as archive_fixtures
# does: a session replays to answer anything at all, so without the facade the
# mxq_game_ functions are absent from the library and every session expectation
# reports NOT IMPLEMENTED, while the SHA-256 vectors still run.

add_executable(mxq_session_tests
  mxq_session_tests.cpp
  mxq_json.cpp
)
target_link_libraries(mxq_session_tests PRIVATE mxq::core mxq::sqlite mxq_warnings)
target_include_directories(mxq_session_tests PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/../src"
)
target_compile_definitions(mxq_session_tests PRIVATE
  MXQ_STORE_FIXTURES_DIR_DEFAULT="${MXQ_REPO_ROOT}/fixtures/store"
  MXQ_ARCHIVE_FIXTURES_DIR_DEFAULT="${MXQ_REPO_ROOT}/fixtures/archive"
  MXQ_TEST_RULES_FACADE=$<IF:$<AND:$<BOOL:${MXQ_ENABLE_RULES_FACADE}>,$<BOOL:${MXQ_RULES_FACADE_IMPLEMENTED}>>,1,0>
  MXQ_ASSETS_DIR_DEFAULT="${CMAKE_CURRENT_SOURCE_DIR}/../assets"
  MXQ_TEST_GOMOKU_FACADE=$<IF:$<AND:$<BOOL:${MXQ_ENABLE_GOMOKU_FACADE}>,$<BOOL:${MXQ_ENABLE_RULES_FACADE}>>,1,0>
)

add_test(NAME store_sessions COMMAND mxq_session_tests)
set_tests_properties(store_sessions PROPERTIES
  LABELS "store;fixtures"
)

# The History runner: the four archiving paths in fixtures/store/terminal/,
# each driven end to end through the store and back out of it, plus the library
# properties a single game cannot express — the accepted ordering and its
# tie-break, the pagination boundaries, the revision counter, and the three
# corruption paths.
#
# It links the vendored SQLite for the same two reasons the session runner does
# and one more: the failing-ending case takes the write lock from a second
# connection, and the corruption cases write damage a live core never could. It
# includes the core's internal headers for the identity provider alone.
#
# In the engine-less configuration a game cannot be played, so none can be
# ended and every scenario reports NOT IMPLEMENTED; the empty-library case
# still runs there, because counting and paging an empty History needs no
# engine.

add_executable(mxq_history_tests
  mxq_history_tests.cpp
  mxq_json.cpp
)
target_link_libraries(mxq_history_tests PRIVATE mxq::core mxq::sqlite mxq_warnings)
target_include_directories(mxq_history_tests PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/../src"
)
target_compile_definitions(mxq_history_tests PRIVATE
  MXQ_STORE_FIXTURES_DIR_DEFAULT="${MXQ_REPO_ROOT}/fixtures/store"
  MXQ_ARCHIVE_FIXTURES_DIR_DEFAULT="${MXQ_REPO_ROOT}/fixtures/archive"
  MXQ_TEST_RULES_FACADE=$<IF:$<AND:$<BOOL:${MXQ_ENABLE_RULES_FACADE}>,$<BOOL:${MXQ_RULES_FACADE_IMPLEMENTED}>>,1,0>
  MXQ_ASSETS_DIR_DEFAULT="${CMAKE_CURRENT_SOURCE_DIR}/../assets"
  MXQ_TEST_GOMOKU_FACADE=$<IF:$<AND:$<BOOL:${MXQ_ENABLE_GOMOKU_FACADE}>,$<BOOL:${MXQ_ENABLE_RULES_FACADE}>>,1,0>
)

add_test(NAME store_history COMMAND mxq_history_tests)
set_tests_properties(store_history PROPERTIES
  LABELS "store;fixtures"
)

# The interchange runner: export and import, over the archive corpus the codec
# runner already owns.
#
# It re-runs that corpus rather than growing one of its own, because what it
# asserts is not what the codec decides but what the pipeline around it does:
# every rejection class refusing through mxq_store_import with the status the
# sidecar already fixed, and the library untouched each time. A validation that
# is right and a transaction that runs anyway would pass archive_fixtures
# completely.
#
# It links the vendored SQLite for the write lock, exactly as the History runner
# does: an import that fails at BEGIN IMMEDIATE is the only honest way to drive
# the "never partially imported" promise, and nothing in the core arranges it.
# It needs no internal headers — every case here is public surface.
#
# Without the engine an import cannot replay a move line and is absent from the
# library, and no History record can be made for an export to find; one case
# runs there, and the rest report NOT IMPLEMENTED.

add_executable(mxq_interchange_tests
  mxq_interchange_tests.cpp
  mxq_json.cpp
)
target_link_libraries(mxq_interchange_tests PRIVATE mxq::core mxq::sqlite mxq_warnings)
target_compile_definitions(mxq_interchange_tests PRIVATE
  MXQ_ARCHIVE_FIXTURES_DIR_DEFAULT="${MXQ_REPO_ROOT}/fixtures/archive"
  MXQ_TEST_RULES_FACADE=$<IF:$<AND:$<BOOL:${MXQ_ENABLE_RULES_FACADE}>,$<BOOL:${MXQ_RULES_FACADE_IMPLEMENTED}>>,1,0>
  MXQ_ASSETS_DIR_DEFAULT="${CMAKE_CURRENT_SOURCE_DIR}/../assets"
  MXQ_TEST_GOMOKU_FACADE=$<IF:$<AND:$<BOOL:${MXQ_ENABLE_GOMOKU_FACADE}>,$<BOOL:${MXQ_ENABLE_RULES_FACADE}>>,1,0>
)

add_test(NAME store_interchange COMMAND mxq_interchange_tests)
set_tests_properties(store_interchange PROPERTIES
  LABELS "store;archive;fixtures"
)

# The search-facade runner: engine preparation with every typed refusal, the
# effective-NNUE preflight in both directions, real searches over real
# sessions with the delivery ladder, cancellation, staleness, retention,
# reconfiguration serialisation, shutdown mid-search — and the bridge's variant
# axis, which is the one part of it no public entry point reaches yet.
#
# It links the vendored engine directly, and deliberately: "the applied
# Threads value", "the transposition table is released whole", and "the
# effective NNUE state is on" are claims about the engine's own globals, and a
# runner that asked the facade to report on itself would test the report
# rather than the state. The engine target's usage requirements carry the
# LARGEBOARDS define set, so the runner's view of every engine struct matches
# the library's.
#
# It includes the core's internal headers for the same kind of reason the store
# runners do: the bridge takes a variant per configuration, the C surface above
# it creates games of one variant and so can only ever ask for that one, and a
# capability nothing above can request is tested where it is offered or nowhere.
#
# It has two asset directories, both staged in the build tree and both verified
# against pinned-inputs.json at configure time. The first is the shipped shape —
# the variant configuration beside the app's network alone — and every case that
# is not about the second variant uses it, so those cases keep describing what a
# distribution actually holds. The second adds the built-in variant's network,
# which is the shape a two-variant configuration is handed. With the engine in
# the build and no verified network staged, the runner FAILS with the staging
# problem rather than skipping; without the engine it degrades to NOT
# IMPLEMENTED exactly as the session runner does.

add_executable(mxq_search_tests
  mxq_search_tests.cpp
)
target_link_libraries(mxq_search_tests PRIVATE mxq::core mxq_warnings)
target_include_directories(mxq_search_tests PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/../src"
)
if(MXQ_ENABLE_RULES_FACADE)
  target_link_libraries(mxq_search_tests PRIVATE mxq::fairy-stockfish)
endif()
# And the second engine, for the one case that asserts each engine is released
# when the other is prepared. That claim is about the two engines' own state and
# nothing through the C surface distinguishes it, so the case reads each bridge's
# released posture where that bridge keeps it — which needs both linked.
if(MXQ_ENABLE_GOMOKU_FACADE)
  target_link_libraries(mxq_search_tests PRIVATE mxq::rapfi)
endif()
# The staging problem is a sentence written for a person, and it becomes a C
# string literal on a compiler command line, which two of its characters cannot
# survive. A semicolon is a CMake list separator wherever it appears — inside an
# element of the COMPILE_DEFINITIONS property as much as in an argument — so a
# value containing one is split in two and the compiler driver is handed an
# unterminated quote. A backslash is a C escape, so a native Windows path in the
# message would silently become whatever `\n` or `\t` it happened to spell. Both
# are sanitised here rather than legislated about upstream: the message is prose,
# it loses nothing by using a comma and a forward slash, and a future sentence
# then cannot reintroduce either bug. Neither showed until CI first configured
# without a network — until then the string is empty — and the semicolon showed
# as a shell syntax error half a screen from its cause.
string(REPLACE ";" "," MXQ_TEST_NNUE_PROBLEM_TEXT "${MXQ_TEST_NNUE_PROBLEM}")
string(REPLACE "\\" "/" MXQ_TEST_NNUE_PROBLEM_TEXT "${MXQ_TEST_NNUE_PROBLEM_TEXT}")

# Every network name, byte length and variant identifier reaches the suite from
# the manifest rather than being spelled a second time in C++. The suite reads
# each staged network by name, composes the two wrong-basename cases' names from
# the identifiers, and quotes the byte lengths back when it asserts which pin
# refused a cross-loaded network — so replacing a network stays what
# pinned-inputs.json says it is: the bytes and the manifest, with nothing else
# to remember.
target_compile_definitions(mxq_search_tests PRIVATE
  MXQ_TEST_RULES_FACADE=$<IF:$<AND:$<BOOL:${MXQ_ENABLE_RULES_FACADE}>,$<BOOL:${MXQ_RULES_FACADE_IMPLEMENTED}>>,1,0>
  MXQ_TEST_ASSETS_DIR="${MXQ_TEST_ASSETS_DIR}"
  MXQ_TEST_XIANGQI_ASSETS_DIR="${MXQ_TEST_XIANGQI_ASSETS_DIR}"
  MXQ_TEST_NNUE_FILENAME="${MXQ_BUILD_NNUE_FILENAME}"
  MXQ_TEST_NNUE_BYTE_LENGTH=${MXQ_BUILD_NNUE_BYTE_LENGTH}
  MXQ_TEST_VARIANT_ID="${MXQ_BUILD_VARIANT_ID}"
  MXQ_TEST_BASE_VARIANT_ID="${MXQ_BUILD_BASE_VARIANT_ID}"
  MXQ_TEST_XIANGQI_NNUE_FILENAME="${MXQ_BUILD_XIANGQI_NNUE_FILENAME}"
  MXQ_TEST_XIANGQI_NNUE_BYTE_LENGTH=${MXQ_BUILD_XIANGQI_NNUE_BYTE_LENGTH}
  MXQ_TEST_XIANGQI_VARIANT_ID="${MXQ_BUILD_XIANGQI_VARIANT_ID}"
  MXQ_TEST_NNUE_STAGED=${MXQ_TEST_NNUE_STAGED}
  MXQ_TEST_NNUE_PROBLEM="${MXQ_TEST_NNUE_PROBLEM_TEXT}"
  MXQ_TEST_GOMOKU_FACADE=$<IF:$<AND:$<BOOL:${MXQ_ENABLE_GOMOKU_FACADE}>,$<BOOL:${MXQ_ENABLE_RULES_FACADE}>>,1,0>
  MXQ_TEST_GOMOKU_ASSETS_DIR="${MXQ_TEST_GOMOKU_ASSETS_DIR}"
)

add_test(NAME engine_search COMMAND mxq_search_tests)
set_tests_properties(engine_search PROPERTIES
  LABELS "engine;search"
)

# The second engine's bridge runner: preparation with its three preflights,
# search under each of the two games, cancellation, the rules switch, and
# teardown.
#
# It drives the bridge directly rather than a public C entry point, because at
# this stage there is no public entry point to drive: the game vocabulary the C
# surface speaks names two games and neither is played on this engine. The
# precedent is the runner above, which reaches past the C surface for the same
# reason on the variant axis. It links the vendored engine directly for the same
# reason too — "the effective evaluator is the network", "the table was released
# whole" and "the thread count is the plan's" are claims about the engine's own
# globals.
#
# One staged asset directory, verified against pinned-inputs.json at configure
# time. With the engine in the build and no verified weights staged, the runner
# FAILS with the staging problem rather than skipping; without the engine it
# reports NOT IMPLEMENTED.

add_executable(mxq_rapfi_tests
  mxq_rapfi_tests.cpp
)
target_link_libraries(mxq_rapfi_tests PRIVATE mxq::core mxq_warnings)
target_include_directories(mxq_rapfi_tests PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/../src"
)
if(MXQ_ENABLE_GOMOKU_FACADE)
  target_link_libraries(mxq_rapfi_tests PRIVATE mxq::rapfi)
endif()

# The same two characters sanitised for the same two reasons as above: a
# semicolon is a CMake list separator wherever it appears, and a backslash is a
# C escape, so a native Windows path in the staging message would silently
# become whatever it happened to spell.
string(REPLACE ";" "," MXQ_TEST_GOMOKU_NNUE_PROBLEM_TEXT "${MXQ_TEST_GOMOKU_NNUE_PROBLEM}")
string(REPLACE "\\" "/" MXQ_TEST_GOMOKU_NNUE_PROBLEM_TEXT "${MXQ_TEST_GOMOKU_NNUE_PROBLEM_TEXT}")

target_compile_definitions(mxq_rapfi_tests PRIVATE
  MXQ_TEST_GOMOKU_FACADE=$<IF:$<BOOL:${MXQ_ENABLE_GOMOKU_FACADE}>,1,0>
  MXQ_TEST_GOMOKU_ASSETS_DIR="${MXQ_TEST_GOMOKU_ASSETS_DIR}"
  MXQ_TEST_GOMOKU_NNUE_FILENAME="${MXQ_BUILD_GOMOKU_NNUE_FILENAME}"
  MXQ_TEST_GOMOKU_NNUE_BYTE_LENGTH=${MXQ_BUILD_GOMOKU_NNUE_BYTE_LENGTH}
  MXQ_TEST_RENJU_BLACK_NNUE_FILENAME="${MXQ_BUILD_RENJU_BLACK_NNUE_FILENAME}"
  MXQ_TEST_RENJU_WHITE_NNUE_FILENAME="${MXQ_BUILD_RENJU_WHITE_NNUE_FILENAME}"
  MXQ_TEST_GOMOKU_NNUE_STAGED=${MXQ_TEST_GOMOKU_NNUE_STAGED}
  MXQ_TEST_GOMOKU_NNUE_PROBLEM="${MXQ_TEST_GOMOKU_NNUE_PROBLEM_TEXT}"
)

add_test(NAME gomoku_engine COMMAND mxq_rapfi_tests)
set_tests_properties(gomoku_engine PROPERTIES
  LABELS "engine;gomoku"
)

# The placement games' adapter runner: their notation, the legality and
# adjudication the second engine answers, and the engine dispatch that reaches
# it. Everything through the public C surface — which is the difference from the
# runner above, and the whole reason both exist: that one was written when no
# public entry point reached this engine, and this one exists because now they
# all do. It links no engine directly for the same reason.
#
# It needs both asset directories. mxq_core_init loads the first engine's variant
# configuration before anything else, a preparation for a placement game reads
# the second engine's weights, and the core takes one asset directory — so the
# suite copies both stagings into one scratch directory, which is the shape a
# distribution actually ships.

add_executable(mxq_gomoku_tests
  mxq_gomoku_tests.cpp
)
target_link_libraries(mxq_gomoku_tests PRIVATE mxq::core mxq_warnings)

target_compile_definitions(mxq_gomoku_tests PRIVATE
  MXQ_TEST_GOMOKU_FACADE=$<IF:$<AND:$<BOOL:${MXQ_ENABLE_GOMOKU_FACADE}>,$<BOOL:${MXQ_ENABLE_RULES_FACADE}>>,1,0>
  MXQ_TEST_ASSETS_DIR="${MXQ_TEST_ASSETS_DIR}"
  MXQ_TEST_GOMOKU_ASSETS_DIR="${MXQ_TEST_GOMOKU_ASSETS_DIR}"
)

add_test(NAME gomoku_rules COMMAND mxq_gomoku_tests)
set_tests_properties(gomoku_rules PROPERTIES
  LABELS "rules;gomoku"
)

# The jieqi engine's smoke runner: the vendored Pikafish rules slice brought up
# beside the Fairy-Stockfish-backed core, in one process.
#
# It links the vendored slice directly, which is the same reason the two runners
# above link their engines directly. The claim it makes is about the two
# engines' own symbols — that the namespace rename keeps Bitboards::init and
# Position::init distinct where two Stockfish derivatives would otherwise define
# one of each — and no facade can be asked to report on that: reaching it needs
# this engine's C++ API, which is a door mxq.h deliberately does not have. Its
# other half asks the C surface instead, because what the game axis over this
# engine answers is exactly what mxq.h states about it.
#
# It does NOT link mxq::fairy-stockfish, and that omission is deliberate. The
# two engines' headers share their file names — position.h, movegen.h,
# bitboard.h, types.h — so a target carrying both include directories would
# resolve those spellings by search order. The first engine is reached through
# mxq.h instead, which needs no engine header at all, and mxq::core carries its
# objects into the link regardless.
#
# It needs the first engine's asset directory because mxq_core_init loads the
# bundled variant configuration before anything else. The jieqi slice needs no
# asset of any kind: it has no network, no configuration file and nothing to
# verify, which is what makes this the one engine in the tree with no staging
# step above it.
#
# Without the facade neither engine is in the build and the runner reports NOT
# IMPLEMENTED, exactly as its neighbours do.

add_executable(mxq_pikafish_tests
  mxq_pikafish_tests.cpp
)
target_link_libraries(mxq_pikafish_tests PRIVATE mxq::core mxq_warnings)
if(MXQ_ENABLE_RULES_FACADE)
  target_link_libraries(mxq_pikafish_tests PRIVATE mxq::pikafish)
endif()

target_compile_definitions(mxq_pikafish_tests PRIVATE
  MXQ_TEST_RULES_FACADE=$<IF:$<AND:$<BOOL:${MXQ_ENABLE_RULES_FACADE}>,$<BOOL:${MXQ_RULES_FACADE_IMPLEMENTED}>>,1,0>
  MXQ_ASSETS_DIR_DEFAULT="${CMAKE_CURRENT_SOURCE_DIR}/../assets"
)

add_test(NAME jieqi_engine COMMAND mxq_pikafish_tests)
set_tests_properties(jieqi_engine PROPERTIES
  LABELS "engine;jieqi"
)
