# Build for the shared core.
#
# Two targets always, and a third on request: the static library `mxq_core`,
# which is what the Apple frontend links; the executable `mxq_core_tests`, which
# is the one shared C++ test runner docs/architecture.md requires — it runs on
# every development platform without a frontend and executes the approved
# fixtures identically everywhere; and, behind MXQ_BUILD_SHARED_LIBRARY, the
# shared library `mxq_core_shared`, which is the same C ABI in a form a
# non-C++ frontend can load. The Windows frontend is C# and consumes the core
# through P/Invoke, which needs a DLL rather than an archive.
#
# Configure and build from the repository root:
#
#   cmake -S core -B core/.build -G Ninja
#   cmake --build core/.build
#   ctest --test-dir core/.build --output-on-failure
#
# This project is deliberately standalone and is not wired into the Xcode
# project under apple/; that integration comes later.

cmake_minimum_required(VERSION 3.24)

project(MiniXiangqiCore
        VERSION 1.0.0
        DESCRIPTION "Mini Xiangqi shared core"
        LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE RelWithDebInfo CACHE STRING "" FORCE)
endif()

# The repository root: fixtures/ and pinned-inputs.json live there, not under
# core/. fixtures/ is the independent authority the core is validated against
# rather than an implementation detail of the core it validates.
get_filename_component(MXQ_REPO_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/.." ABSOLUTE)

option(MXQ_WARNINGS_AS_ERRORS "Treat compiler warnings as errors" OFF)
option(MXQ_ENABLE_RULES_FACADE
       "Compile and link the vendored Fairy-Stockfish fork into the core, and \
build the fixture runner against a rules facade that exists. Off by default: \
the engine is a multi-minute build, and nothing else in the core needs it. \
While it is off, third_party/fairy-stockfish is not added at all and every \
fixture reports NOT IMPLEMENTED rather than passing."
       OFF)

option(MXQ_BUILD_SHARED_LIBRARY
       "Also build the C ABI as a shared library, for a frontend that loads the \
core at runtime instead of linking it: mxqcore.dll on Windows, which the C# \
frontend reaches through P/Invoke, and libmxqcore.dylib on macOS, where it is \
built as the portability check on the export surface. No other platform's \
shared library has been built, so none is claimed. Off by default: the Apple \
frontend links the static library, the test runners link the static library, \
and building both compiles every source twice."
       OFF)

# Whether the facade's own entry points exist in src/. They do, and this has
# been ON since the commit that implemented them; it survives only as the seam
# the test runners' MXQ_TEST_RULES_FACADE is computed from, so that "the engine
# is not in this build" and "the facade is not written" stay separable in the
# generator expressions below. It is not a user-facing option.
set(MXQ_RULES_FACADE_IMPLEMENTED ON)

# --------------------------------------------------------------------------
# Pinned inputs
# --------------------------------------------------------------------------
#
# The engine profile MxqVersion reports is load-bearing rather than diagnostic,
# so it is read from the repository's manifest rather than written a second time
# here. docs/architecture.md: CI must not receive undocumented inputs; pinned
# revisions and asset hashes come from the repository's manifests.

set(MXQ_PINNED_INPUTS "${MXQ_REPO_ROOT}/pinned-inputs.json")
if(NOT EXISTS "${MXQ_PINNED_INPUTS}")
  message(FATAL_ERROR "pinned-inputs.json not found at ${MXQ_PINNED_INPUTS}")
endif()
file(READ "${MXQ_PINNED_INPUTS}" MXQ_PINNED_INPUTS_JSON)

function(mxq_pinned_get out_var)
  string(JSON value ERROR_VARIABLE err GET "${MXQ_PINNED_INPUTS_JSON}" ${ARGN})
  if(err)
    message(FATAL_ERROR "pinned-inputs.json: ${ARGN}: ${err}")
  endif()
  set(${out_var} "${value}" PARENT_SCOPE)
endfunction()

mxq_pinned_get(MXQ_BUILD_FORK_REVISION fork revision)
mxq_pinned_get(MXQ_BUILD_VARIANT_ID variant id)
mxq_pinned_get(MXQ_BUILD_BASE_VARIANT_ID variant base_variant)
mxq_pinned_get(MXQ_VARIANT_INI_FILENAME variant filename)

# The second variant the core can search: built-in `xiangqi`, the 9x10 game.
# Its identifier is the engine's own registration name rather than anything this
# repository chooses, which is why it is spelled here and not pinned — and it is
# also the key its network is pinned under, so the spelling is checked by the
# reads below failing if it is ever wrong.
set(MXQ_BUILD_XIANGQI_VARIANT_ID "xiangqi")

# One network per variant, each keyed in the manifest by the variant it serves.
# The app's variant reads its entry through variant.id rather than through a
# second spelling of the same name, so the keying is load-bearing here too.
mxq_pinned_get(MXQ_BUILD_NNUE_SHA256 network ${MXQ_BUILD_VARIANT_ID} sha256)
mxq_pinned_get(MXQ_BUILD_NNUE_FILENAME network ${MXQ_BUILD_VARIANT_ID} filename)
mxq_pinned_get(MXQ_BUILD_NNUE_BYTE_LENGTH network ${MXQ_BUILD_VARIANT_ID} byte_length)
mxq_pinned_get(MXQ_BUILD_XIANGQI_NNUE_SHA256 network ${MXQ_BUILD_XIANGQI_VARIANT_ID} sha256)
mxq_pinned_get(MXQ_BUILD_XIANGQI_NNUE_FILENAME network ${MXQ_BUILD_XIANGQI_VARIANT_ID} filename)
mxq_pinned_get(MXQ_BUILD_XIANGQI_NNUE_BYTE_LENGTH network ${MXQ_BUILD_XIANGQI_VARIANT_ID} byte_length)

# The core's own revision. Absent a git checkout — an exported source tree, for
# instance — it is reported as "unknown" rather than guessed.
set(MXQ_BUILD_CORE_REVISION "unknown")
find_package(Git QUIET)
if(GIT_FOUND AND EXISTS "${MXQ_REPO_ROOT}/.git")
  execute_process(
    COMMAND "${GIT_EXECUTABLE}" rev-parse HEAD
    WORKING_DIRECTORY "${MXQ_REPO_ROOT}"
    OUTPUT_VARIABLE MXQ_GIT_HEAD
    OUTPUT_STRIP_TRAILING_WHITESPACE
    ERROR_QUIET)
  if(MXQ_GIT_HEAD)
    set(MXQ_BUILD_CORE_REVISION "${MXQ_GIT_HEAD}")
  endif()
endif()

set(MXQ_GENERATED_DIR "${CMAKE_CURRENT_BINARY_DIR}/generated")
configure_file("${CMAKE_CURRENT_SOURCE_DIR}/cmake/mxq_build_config.h.in"
               "${MXQ_GENERATED_DIR}/mxq_build_config.h"
               @ONLY)

message(STATUS "Mini Xiangqi core: fork revision ${MXQ_BUILD_FORK_REVISION}")
message(STATUS "Mini Xiangqi core: variant ${MXQ_BUILD_VARIANT_ID}")
message(STATUS "Mini Xiangqi core: core revision ${MXQ_BUILD_CORE_REVISION}")

# --------------------------------------------------------------------------
# Warning configuration, shared by every target this project defines
# --------------------------------------------------------------------------
#
# The settled policy, after the first MSVC build of the core:
#
#   - Everything MSVC reports about OUR sources is fixed in the source, not
#     silenced. /W4 /permissive- found three real things — a shadowed `rc` and
#     a switch that dispatched on nothing in mxq_store.cpp, and a Bitboard
#     compared against a literal 0 in mxq_engine_bridge.cpp — and each is
#     corrected where it is written, so both compilers read the same code.
#   - _CRT_SECURE_NO_WARNINGS is the one exception, and it is not a
#     suppression of anything ISO says. C4996 there is the Microsoft CRT
#     deprecating Standard C library functions in favour of its own _s
#     variants; the four test files reach it through std::getenv, which C++ has
#     never deprecated and which is the only portable spelling. This macro
#     turns off exactly that family and leaves C4996 alive for genuinely
#     [[deprecated]] APIs, which /wd4996 would not.
#   - The vendored engine's own warnings are not ours: third_party targets do
#     not link this one, so MXQ_WARNINGS_AS_ERRORS cannot fail the build on
#     upstream code we do not edit. See core/third_party/*/CMakeLists.txt.

add_library(mxq_warnings INTERFACE)
if(MSVC)
  target_compile_options(mxq_warnings INTERFACE /W4 /permissive-)
  target_compile_definitions(mxq_warnings INTERFACE _CRT_SECURE_NO_WARNINGS)
  if(MXQ_WARNINGS_AS_ERRORS)
    target_compile_options(mxq_warnings INTERFACE /WX)
  endif()
else()
  target_compile_options(mxq_warnings INTERFACE -Wall -Wextra -Wpedantic)
  if(MXQ_WARNINGS_AS_ERRORS)
    target_compile_options(mxq_warnings INTERFACE -Werror)
  endif()
endif()

# --------------------------------------------------------------------------
# The library
# --------------------------------------------------------------------------
#
# Implemented so far: the status and blob helpers, the pure queries that take
# no core instance, core lifecycle with the store opened at initialisation,
# the session-free rules facade (behind MXQ_ENABLE_RULES_FACADE), the
# clock/identity provider the deterministic-identity flag configures, the
# archive codec's read and write sides, store-attached sessions with their
# per-mutation commits, the four archiving paths that end a game, the History
# read surface, the interchange pair with the import preview, and the search
# facade — mxq_engine_prepare/teardown/query, the mxq_search_ group, and
# mxq_core_cancel_all's quiescing half — in mxq_search.cpp.
#
# mxq_session.cpp is gated with the engine like mxq_engine_bridge.cpp: a
# session answers every one of its queries by replaying its move line through
# the rules facade, so without the facade the mxq_game_ functions cannot exist
# and are absent from the library rather than stubbed. mxq_search.cpp is gated
# the same way and for the stronger reason — it drives the engine itself — so
# the mxq_engine_ and mxq_search_ functions are likewise absent without it.
# mxq_core_cancel_all alone stays in mxq_core.cpp on both configurations,
# because a core without an engine has a true answer to it: no work is
# outstanding. mxq_store_api.cpp and mxq_interchange.cpp are not gated as a
# whole, because part of what they hold is a pure store operation that can
# answer without an engine — export decodes a row and writes it out again, and
# a document is not a position. The functions in them that need a session or a
# live state, mxq_store_import included, are guarded inside the file, exactly
# as mxq_archive_validate is inside mxq_archive.cpp.

set(MXQ_CORE_SOURCES
  src/mxq_abi.cpp
  src/mxq_archive.cpp
  src/mxq_archive_json.cpp
  src/mxq_archive_write.cpp
  src/mxq_blob.cpp
  src/mxq_core.cpp
  src/mxq_engine.cpp
  src/mxq_identity.cpp
  src/mxq_interchange.cpp
  src/mxq_internal.cpp
  src/mxq_notation.cpp
  src/mxq_rules.cpp
  src/mxq_sha256.cpp
  src/mxq_store.cpp
  src/mxq_store_api.cpp
  $<$<BOOL:${MXQ_ENABLE_RULES_FACADE}>:${CMAKE_CURRENT_SOURCE_DIR}/src/mxq_engine_bridge.cpp>
  $<$<BOOL:${MXQ_ENABLE_RULES_FACADE}>:${CMAKE_CURRENT_SOURCE_DIR}/src/mxq_search.cpp>
  $<$<BOOL:${MXQ_ENABLE_RULES_FACADE}>:${CMAKE_CURRENT_SOURCE_DIR}/src/mxq_session.cpp>
  src/mxq_status.cpp
)

add_library(mxq_core STATIC ${MXQ_CORE_SOURCES})
add_library(mxq::core ALIAS mxq_core)
set(MXQ_CORE_TARGETS mxq_core)

# The shared library is the same translation units compiled a second time with
# MXQ_BUILD_SHARED defined, which is the switch mxq.h already carries: it turns
# MXQ_API into __declspec(dllexport) under MSVC and leaves it as the
# default-visibility attribute elsewhere.
#
# The alternative — CMake's WINDOWS_EXPORT_ALL_SYMBOLS — was rejected, and not
# on taste. The header declares the export macro on all 61 functions and on
# nothing else, so the macro produces a DLL whose exported surface is exactly
# the contract in docs/core-interface.md. Exporting all symbols would instead
# publish every non-static symbol the link pulled in, which here means the whole
# vendored Fairy-Stockfish fork and the whole SQLite amalgamation — components
# docs/architecture.md requires to stay invisible through mxq.h. It would also
# be Windows-only machinery for a decision the header already makes portably,
# and it does not export data symbols at all. The macro costs one compile
# definition; the flag would cost the boundary.
if(MXQ_BUILD_SHARED_LIBRARY)
  add_library(mxq_core_shared SHARED ${MXQ_CORE_SOURCES})
  add_library(mxq::core_shared ALIAS mxq_core_shared)
  target_compile_definitions(mxq_core_shared PRIVATE MXQ_BUILD_SHARED)
  list(APPEND MXQ_CORE_TARGETS mxq_core_shared)

  # Both libraries are named mxqcore, and on Windows a DLL's import library is
  # also mxqcore.lib — the same file the static library writes. They are kept
  # apart by directory rather than by name, because the name is what the C#
  # bindings' DllImport resolves and it is not ours to decorate.
  set_target_properties(mxq_core_shared PROPERTIES
    ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/shared"
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/shared"
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/shared"
  )
  message(STATUS "Mini Xiangqi core: shared library in ${CMAKE_CURRENT_BINARY_DIR}/shared")
endif()

foreach(mxq_target IN LISTS MXQ_CORE_TARGETS)
  target_include_directories(${mxq_target}
    PUBLIC
      $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    PRIVATE
      "${CMAKE_CURRENT_SOURCE_DIR}/src"
      "${MXQ_GENERATED_DIR}"
  )
  target_link_libraries(${mxq_target} PRIVATE mxq_warnings)

  # The facade's entry points are compiled out unless the engine is present, so
  # the switch must reach the compiler and not only CMake. Without this the
  # library builds and links cleanly while mxq_rules_evaluate and
  # mxq_rules_legal_moves simply do not exist in it — which surfaces as an
  # undefined symbol in whatever links it, a long way from the cause.
  if(MXQ_ENABLE_RULES_FACADE)
    target_compile_definitions(${mxq_target} PRIVATE MXQ_ENABLE_RULES_FACADE=1)
  endif()

  set_target_properties(${mxq_target} PROPERTIES
    CXX_VISIBILITY_PRESET hidden
    VISIBILITY_INLINES_HIDDEN ON
    OUTPUT_NAME mxqcore
  )
endforeach()

# --------------------------------------------------------------------------
# Vendored third-party inputs
# --------------------------------------------------------------------------
#
# Each vendored input lives in core/third_party/<name>/ and carries its own
# CMakeLists.txt defining the aliased target named below. The loop links it into
# mxq_core privately, which is what keeps it invisible through mxq.h, as
# docs/architecture.md requires. See core/third_party/README.md.
#
# Both inputs are vendored. The fork is additionally gated on
# MXQ_ENABLE_RULES_FACADE, so the default configuration does not compile it: it
# is a multi-minute build and nothing else in the core needs it. SQLite is not
# gated: the store is part of the core on every configuration, and the
# amalgamation compiles in seconds.

set(MXQ_OPTIONAL_DEPS fairy-stockfish)
foreach(mxq_dep IN ITEMS fairy-stockfish sqlite)
  if(NOT EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/third_party/${mxq_dep}/CMakeLists.txt")
    message(STATUS "Mini Xiangqi core: ${mxq_dep} not vendored")
  elseif(mxq_dep IN_LIST MXQ_OPTIONAL_DEPS AND NOT MXQ_ENABLE_RULES_FACADE)
    message(STATUS "Mini Xiangqi core: ${mxq_dep} vendored but not built "
                   "(MXQ_ENABLE_RULES_FACADE is OFF)")
  else()
    add_subdirectory("third_party/${mxq_dep}")
    foreach(mxq_target IN LISTS MXQ_CORE_TARGETS)
      target_link_libraries(${mxq_target} PRIVATE "mxq::${mxq_dep}")
    endforeach()
    message(STATUS "Mini Xiangqi core: vendored ${mxq_dep}")
  endif()
endforeach()

# A shared library exports what its objects say is exportable, and the vendored
# components are compiled as their own targets: hiding mxq_core_shared's own
# symbols says nothing about theirs. On Windows nothing is exported without
# __declspec(dllexport), so the DLL is already exactly mxq.h's 61 functions and
# this changes nothing there. Where the default is the opposite — Mach-O, and
# ELF by the same rule — the library also publishes every sqlite3_ entry point
# and much of the engine, components docs/architecture.md requires to stay
# invisible through mxq.h. Applied only while building a shared library, so
# that the Apple frontend's static build compiles the same objects it always
# did. Measured with nm on macOS: without it the library exported the whole
# sqlite3_ surface alongside mxq.h's own functions; with it, mxq.h's own and
# nothing else.
if(MXQ_BUILD_SHARED_LIBRARY)
  foreach(mxq_vendored IN ITEMS mxq_fairy_stockfish mxq_sqlite)
    if(TARGET ${mxq_vendored})
      set_target_properties(${mxq_vendored} PROPERTIES
        C_VISIBILITY_PRESET hidden
        CXX_VISIBILITY_PRESET hidden
        VISIBILITY_INLINES_HIDDEN ON
      )
    endif()
  endforeach()
endif()

# --------------------------------------------------------------------------
# The bundled variant configuration
# --------------------------------------------------------------------------
#
# assets/minixiangqi-variants.ini defines minixiangqiaxf, the target variant, and
# is a packaging input rather than a build input: docs/engine-integration.md
# fixes its name and its identifier, and pinned-inputs.json pins its SHA-256. It
# is exposed here as a path so that the engine probe below, and the rules facade
# after it, load the same file the app bundles rather than a second copy.

set(MXQ_VARIANT_INI "${CMAKE_CURRENT_SOURCE_DIR}/assets/minixiangqi-variants.ini")
if(NOT EXISTS "${MXQ_VARIANT_INI}")
  message(FATAL_ERROR "bundled variant configuration not found at ${MXQ_VARIANT_INI}")
endif()
# The manifest pins the configuration's bytes as it pins the network's, and
# the same rule applies: nothing consumed on trust. An edit to the file and
# its pinned hash must travel together or configuration stops here.
mxq_pinned_get(MXQ_VARIANT_INI_SHA256 variant sha256)
file(SHA256 "${MXQ_VARIANT_INI}" mxq_variant_ini_sha256)
if(NOT mxq_variant_ini_sha256 STREQUAL MXQ_VARIANT_INI_SHA256)
  message(FATAL_ERROR
          "the bundled variant configuration at ${MXQ_VARIANT_INI} does not "
          "match the SHA-256 pinned-inputs.json pins; edit the file and its "
          "pin in the same change")
endif()

# --------------------------------------------------------------------------
# The staged engine test assets
# --------------------------------------------------------------------------
#
# Both networks are in this repository: assets/, beside the variant
# configuration they are loaded with, under the names they are loaded as. A name
# has to begin with the identifier of the variant it is for or the engine
# silently disables NNUE, so a committed name is already the loaded name and
# staging is a copy rather than a rename. MXQ_NNUE_SOURCE and
# MXQ_XIANGQI_NNUE_SOURCE survive as overrides — pointing a build at a candidate
# network is how the next one gets tried before it is committed — and each
# defaults to the committed file rather than to anything a build has to be told
# about.
#
# The filenames come from pinned-inputs.json rather than from a second spelling
# here: replacing a network is then the manifest and the bytes, which is what
# docs/engine-integration.md's handling policy asks of a future net.
#
# With the engine enabled this stages two asset directories in the build tree,
# byte length and SHA-256 verified against the manifest before a byte is copied:
#
#   test-assets            the variant configuration plus the Mini Xiangqi
#                          network, for focused single-game tests.
#   test-assets-xiangqi    the variant configuration plus both networks, which is
#                          the shape a two-game frontend and engine configuration use:
#                          EvalFile is a list and the engine selects from it by
#                          basename. windows/build-core-dll.ps1 copies this one
#                          into the distribution's asset directory.
#
# That verification is not ceremony for files that are version-controlled: it is
# the same gate every other consumer applies, and it is what catches an override
# pointed at the wrong bytes. A missing or mismatched network stages nothing and
# records why; the search tests then FAIL with that message rather than skipping
# silently, because a suite that silently skipped its engine would report green
# on exactly the regression it exists to catch. No unverified byte is ever
# staged.

# Verify one network's bytes against its pins. Sets <out_problem> to a sentence
# naming what is wrong, or to the empty string when the file is good.
function(mxq_verify_network out_problem source byte_length sha256)
  set(problem "")
  if(NOT EXISTS "${source}")
    set(problem
        "the NNUE network was not found at ${source}; it belongs in core/assets under the name pinned-inputs.json pins, or point the matching source variable at other bytes")
  else()
    file(SIZE "${source}" actual_size)
    file(SHA256 "${source}" actual_sha256)
    if(NOT actual_size EQUAL byte_length)
      set(problem
          "the NNUE network at ${source} is ${actual_size} bytes; pinned-inputs.json pins ${byte_length}")
    elseif(NOT actual_sha256 STREQUAL sha256)
      set(problem
          "the NNUE network at ${source} does not match the SHA-256 pinned-inputs.json pins")
    endif()
  endif()
  set(${out_problem} "${problem}" PARENT_SCOPE)
endfunction()

if(MXQ_ENABLE_RULES_FACADE)
  set(MXQ_NNUE_SOURCE
      "${CMAKE_CURRENT_SOURCE_DIR}/assets/${MXQ_BUILD_NNUE_FILENAME}"
      CACHE FILEPATH
      "The pinned NNUE network bytes staged for engine-dependent tests")
  set(MXQ_XIANGQI_NNUE_SOURCE
      "${CMAKE_CURRENT_SOURCE_DIR}/assets/${MXQ_BUILD_XIANGQI_NNUE_FILENAME}"
      CACHE FILEPATH
      "The pinned built-in-xiangqi NNUE network bytes staged for engine-dependent tests")
  set(MXQ_TEST_ASSETS_DIR "${CMAKE_CURRENT_BINARY_DIR}/test-assets")
  set(MXQ_TEST_XIANGQI_ASSETS_DIR "${CMAKE_CURRENT_BINARY_DIR}/test-assets-xiangqi")
  set(MXQ_TEST_NNUE_STAGED 0)

  # These directories are configuration output, not a cache. Clear an earlier
  # successful staging before verification so a missing, damaged or renamed
  # input cannot leave old bytes for a later build or distribution to consume.
  file(REMOVE_RECURSE "${MXQ_TEST_ASSETS_DIR}"
                      "${MXQ_TEST_XIANGQI_ASSETS_DIR}")

  mxq_verify_network(MXQ_TEST_NNUE_PROBLEM "${MXQ_NNUE_SOURCE}"
                     ${MXQ_BUILD_NNUE_BYTE_LENGTH} "${MXQ_BUILD_NNUE_SHA256}")
  if(MXQ_TEST_NNUE_PROBLEM STREQUAL "")
    mxq_verify_network(MXQ_TEST_NNUE_PROBLEM "${MXQ_XIANGQI_NNUE_SOURCE}"
                       ${MXQ_BUILD_XIANGQI_NNUE_BYTE_LENGTH}
                       "${MXQ_BUILD_XIANGQI_NNUE_SHA256}")
  endif()

  # Both or neither: a damaged or absent pinned network stages nothing at all,
  # for either variant, and the suite fails loudly on the staging problem. That
  # is deliberately louder than the loss because the two-game app ships and
  # searches with both; staging only the good half would make an incomplete
  # distribution look valid.
  if(MXQ_TEST_NNUE_PROBLEM STREQUAL "")
    file(MAKE_DIRECTORY "${MXQ_TEST_ASSETS_DIR}")
    file(COPY_FILE "${MXQ_VARIANT_INI}"
         "${MXQ_TEST_ASSETS_DIR}/${MXQ_VARIANT_INI_FILENAME}"
         ONLY_IF_DIFFERENT)
    file(COPY_FILE "${MXQ_NNUE_SOURCE}"
         "${MXQ_TEST_ASSETS_DIR}/${MXQ_BUILD_NNUE_FILENAME}"
         ONLY_IF_DIFFERENT)

    file(MAKE_DIRECTORY "${MXQ_TEST_XIANGQI_ASSETS_DIR}")
    file(COPY_FILE "${MXQ_VARIANT_INI}"
         "${MXQ_TEST_XIANGQI_ASSETS_DIR}/${MXQ_VARIANT_INI_FILENAME}"
         ONLY_IF_DIFFERENT)
    file(COPY_FILE "${MXQ_NNUE_SOURCE}"
         "${MXQ_TEST_XIANGQI_ASSETS_DIR}/${MXQ_BUILD_NNUE_FILENAME}"
         ONLY_IF_DIFFERENT)
    file(COPY_FILE "${MXQ_XIANGQI_NNUE_SOURCE}"
         "${MXQ_TEST_XIANGQI_ASSETS_DIR}/${MXQ_BUILD_XIANGQI_NNUE_FILENAME}"
         ONLY_IF_DIFFERENT)

    set(MXQ_TEST_NNUE_STAGED 1)
    message(STATUS "Mini Xiangqi core: NNUE staged for tests as "
                   "${MXQ_BUILD_NNUE_FILENAME} and "
                   "${MXQ_BUILD_XIANGQI_NNUE_FILENAME}")
  else()
    message(WARNING "Mini Xiangqi core: ${MXQ_TEST_NNUE_PROBLEM}; engine-dependent search tests will FAIL")
  endif()
else()
  # Referenced unconditionally by tests/CMakeLists.txt; without the engine the
  # search runner reports NOT IMPLEMENTED and never reads these.
  set(MXQ_TEST_ASSETS_DIR "")
  set(MXQ_TEST_XIANGQI_ASSETS_DIR "")
  set(MXQ_TEST_NNUE_STAGED 0)
  set(MXQ_TEST_NNUE_PROBLEM "the engine is not in this build")
endif()

# --------------------------------------------------------------------------
# Tests
# --------------------------------------------------------------------------

include(CTest)
if(BUILD_TESTING)
  add_subdirectory(tests)
endif()
