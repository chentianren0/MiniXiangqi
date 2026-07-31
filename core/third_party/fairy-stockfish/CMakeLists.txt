# The pinned Fairy-Stockfish fork, built as a static library the core links.
#
# This file is ours, not the fork's. Everything under upstream/ is a verbatim
# copy of the pinned revision and is never edited here; see README.md for the
# vendoring record and for what changes when the fork's own static-library
# target lands.
#
# core/CMakeLists.txt adds this directory only when MXQ_ENABLE_RULES_FACADE is
# ON, so the default configuration neither compiles nor links any of it.

cmake_minimum_required(VERSION 3.24)

set(MXQ_FS_UPSTREAM "${CMAKE_CURRENT_SOURCE_DIR}/upstream")
set(MXQ_FS_SRC "${MXQ_FS_UPSTREAM}/src")

# --------------------------------------------------------------------------
# Sources
# --------------------------------------------------------------------------
#
# Listed explicitly rather than globbed: a glob would silently change what the
# core links when the vendored snapshot is re-cut, and the pinned inputs are
# meant to be reviewable. The engine's own main(), its Python bindings
# (pyffish.cpp) and its JavaScript bindings (ffishjs.cpp) are not in the
# snapshot at all, so they cannot appear here.

set(MXQ_FS_SOURCES
  benchmark.cpp
  bitbase.cpp
  bitboard.cpp
  endgame.cpp
  evaluate.cpp
  material.cpp
  misc.cpp
  movegen.cpp
  movepick.cpp
  parser.cpp
  partner.cpp
  pawns.cpp
  piece.cpp
  position.cpp
  psqt.cpp
  search.cpp
  thread.cpp
  timeman.cpp
  tt.cpp
  tune.cpp
  uci.cpp
  ucioption.cpp
  variant.cpp
  xboard.cpp
  syzygy/tbprobe.cpp
  nnue/evaluate_nnue.cpp
  nnue/features/half_ka_v2.cpp
  nnue/features/half_ka_v2_variants.cpp
)
list(TRANSFORM MXQ_FS_SOURCES PREPEND "${MXQ_FS_SRC}/")

foreach(mxq_fs_source IN LISTS MXQ_FS_SOURCES)
  if(NOT EXISTS "${mxq_fs_source}")
    message(FATAL_ERROR
      "vendored Fairy-Stockfish source missing: ${mxq_fs_source}. The snapshot "
      "under upstream/ is incomplete; re-cut it as described in README.md.")
  endif()
endforeach()

add_library(mxq_fairy_stockfish STATIC ${MXQ_FS_SOURCES})
add_library(mxq::fairy-stockfish ALIAS mxq_fairy_stockfish)

# --------------------------------------------------------------------------
# Language and interface
# --------------------------------------------------------------------------
#
# The fork compiles as C++17 and the core as C++20. They are separate targets,
# so each keeps its own standard; the engine's headers are C++17 and compile
# cleanly when a C++20 core translation unit includes them.

set_target_properties(mxq_fairy_stockfish PROPERTIES
  CXX_STANDARD 17
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
  POSITION_INDEPENDENT_CODE ON
  OUTPUT_NAME mxqfairystockfish
)

# PUBLIC, but only within this project: core/CMakeLists.txt links this target
# into mxq_core PRIVATE, so neither the include directory nor the defines reach
# anything that consumes mxq_core. That is what keeps the engine invisible
# through mxq.h, per docs/architecture.md.
target_include_directories(mxq_fairy_stockfish PUBLIC "${MXQ_FS_SRC}")

# --------------------------------------------------------------------------
# Defines
# --------------------------------------------------------------------------
#
# These reproduce the fork's own `make ARCH=apple-silicon nnue=no` flag set,
# derived from src/Makefile at the pinned revision rather than assumed:
#
#   largeboards != no  -> LARGEBOARDS            (Makefile:339-340)
#   precomputedmagics  -> PRECOMPUTED_MAGICS     (Makefile:99, 341-343)
#   all != no          -> ALLVARS                (Makefile:352-354)
#   nnue = no          -> NNUE_EMBEDDING_OFF     (Makefile:347-349)
#   bits = 64          -> IS_64BIT               (Makefile:549-551)
#   popcnt = yes       -> USE_POPCNT             (Makefile:564-566)
#   neon = yes         -> USE_NEON               (Makefile:630-631)
#
# They must be PUBLIC. LARGEBOARDS changes the width of Bitboard and the value
# of SQUARE_NB, so a core translation unit that includes an engine header and
# does not see the same define would disagree with the library about the layout
# of every position. Making them interface properties of the target is what
# removes the possibility of that mismatch.
#
# LARGEBOARDS, PRECOMPUTED_MAGICS and ALLVARS are not needed by a 7x7 board —
# `minixiangqi` is registered outside the LARGEBOARDS guard in variant.cpp — but
# they are kept because this is the flag set under which the fork's own suite
# and the approved fixtures were exercised in this workspace. Dropping them
# would make that evidence no longer describe the binary we ship. Narrowing them
# is a measurement, not a cleanup, and belongs with the packaging build that
# fills in pinned-inputs.json's per-platform engine_flags.
#
# NNUE_EMBEDDING_OFF is a product decision rather than a copy of a default: the
# network is bundled as a file and hash-verified, per docs/engine-integration.md,
# so no network is compiled into the binary.

target_compile_definitions(mxq_fairy_stockfish PUBLIC
  LARGEBOARDS
  PRECOMPUTED_MAGICS
  ALLVARS
  NNUE_EMBEDDING_OFF
)

# IS_64BIT is defined here only where the fork's Makefile defines it. types.h
# defines it itself on the one target the Makefile never drives — `_WIN64 &&
# _MSC_VER`, "No Makefile used", where it must also pull in <intrin.h> for
# _BitScanForward64 — so defining it on the command line there too is a C4005
# macro redefinition on every translation unit of the engine, ours included.
# The condition below is the same rule read from the other side, and the two
# halves together define it exactly once everywhere.
if(CMAKE_SIZEOF_VOID_P EQUAL 8 AND NOT MSVC)
  target_compile_definitions(mxq_fairy_stockfish PUBLIC IS_64BIT)
endif()

# Architecture-dependent instruction selection. Anything not recognised falls
# back to the fork's portable profile — correct everywhere, slower — rather than
# to a guess about the target's instruction set.
set(MXQ_FS_ARCH "${CMAKE_SYSTEM_PROCESSOR}")
if(CMAKE_OSX_ARCHITECTURES)
  list(LENGTH CMAKE_OSX_ARCHITECTURES mxq_fs_osx_arch_count)
  if(mxq_fs_osx_arch_count GREATER 1)
    message(FATAL_ERROR
      "the vendored engine selects instruction-set defines per architecture and "
      "cannot be built as a universal binary in one pass; configure once per "
      "architecture (CMAKE_OSX_ARCHITECTURES=${CMAKE_OSX_ARCHITECTURES}).")
  endif()
  set(MXQ_FS_ARCH "${CMAKE_OSX_ARCHITECTURES}")
endif()

if(MXQ_FS_ARCH MATCHES "^(arm64|aarch64|ARM64)$")
  # The fork's ARCH=apple-silicon profile: popcnt and neon, no SSE.
  target_compile_definitions(mxq_fairy_stockfish PUBLIC USE_POPCNT USE_NEON)
  set(MXQ_FS_ARCH_PROFILE "apple-silicon (arm64: popcnt, neon)")
elseif(MXQ_FS_ARCH MATCHES "^(x86_64|AMD64|amd64)$")
  target_compile_definitions(mxq_fairy_stockfish PUBLIC USE_POPCNT)
  if(NOT MSVC)
    target_compile_options(mxq_fairy_stockfish PRIVATE -msse3 -mpopcnt)
  endif()
  set(MXQ_FS_ARCH_PROFILE "x86-64-sse3-popcnt")
else()
  # general-64/general-32: prefetch = no in the fork's Makefile.
  target_compile_definitions(mxq_fairy_stockfish PUBLIC NO_PREFETCH)
  set(MXQ_FS_ARCH_PROFILE "general (portable, no popcnt, no prefetch)")
endif()

# --------------------------------------------------------------------------
# Compile options
# --------------------------------------------------------------------------
#
# The core's mxq_warnings target is deliberately NOT linked here. Its warning
# set, and MXQ_WARNINGS_AS_ERRORS with it, is a standard the core holds itself
# to; applying it to a vendored snapshot we do not edit would make an upstream
# style choice fail our build. The fork's own warning flags are used instead.
#
# What that leaves visible when the ENGINE'S OWN sources compile: C4267 and
# C4324 in them, and C4996 for std::getenv in uci.cpp. All are the fork's code
# at the pinned revision, all are read-only here, and none can fail this build,
# because /WX never reaches this target. Noise to scroll past, not debt to us.
#
# A separate set is emitted while OUR translation units compile, because they
# include engine headers, and those targets DO link mxq_warnings: the first
# Windows CI run reported C5054 and C4244 against types.h and bitboard.h with
# mxq_core.vcxproj and mxq_search_tests.vcxproj named as the project. The
# counts vary with the configuration and are not worth recording; which codes
# reach whose translation units is. C5054 is handled by the INTERFACE
# suppression below. C4244 is deliberately not: it is a narrowing conversion
# rather than a deprecation, and silencing it on the interface would blind our
# own code to narrowing in exactly the files that include an engine header.
# With MXQ_WARNINGS_AS_ERRORS off — which it is everywhere, CI included — it
# costs nothing; turning that option on is the decision that would have to
# settle it, and it is not settled here.

if(NOT MSVC)
  target_compile_options(mxq_fairy_stockfish PRIVATE
    -Wall -Wcast-qual -fno-exceptions)
else()
  target_compile_options(mxq_fairy_stockfish PRIVATE /W3)
endif()

# The one warning that has to be suppressed on the INTERFACE rather than
# privately. The fork is C++17 and its headers do arithmetic and bitwise
# operations on differently typed enums throughout types.h and bitboard.h, which
# C++20 deprecated. The core is C++20, so every core translation unit that
# includes an engine header is warned about the fork's code rather than its own —
# and with MXQ_WARNINGS_AS_ERRORS it would fail to compile because of it. The
# engine's own sources never see the warning; they are built as C++17.
#
# This is scoped to the specific deprecation, not a blanket -w or /w, so a core
# file that includes an engine header keeps every other warning the project
# sets.
#
# Both spellings of the same suppression are listed, because the same
# deprecation has two names: Clang and GCC call it
# -Wdeprecated-enum-enum-conversion, MSVC calls it C5054. Only the Clang
# spelling was here at first, so MSVC was left reporting the fork's C++17
# headers at our own translation units — which the first green Windows CI run
# showed and nobody had looked for. The probe below is what keeps the list
# safe: a compiler that does not know a flag never receives it.
include(CheckCXXCompilerFlag)
foreach(mxq_fs_flag -Wno-deprecated-enum-enum-conversion
                    -Wno-deprecated-anon-enum-enum-conversion
                    /wd5054)
  string(MAKE_C_IDENTIFIER "MXQ_FS_HAVE${mxq_fs_flag}" mxq_fs_flag_var)
  check_cxx_compiler_flag("${mxq_fs_flag}" ${mxq_fs_flag_var})
  if(${mxq_fs_flag_var})
    target_compile_options(mxq_fairy_stockfish INTERFACE
      "$<$<COMPILE_LANGUAGE:CXX>:${mxq_fs_flag}>")
  endif()
endforeach()

# --------------------------------------------------------------------------
# Link dependencies
# --------------------------------------------------------------------------

set(THREADS_PREFER_PTHREAD_FLAG ON)
find_package(Threads REQUIRED)
target_link_libraries(mxq_fairy_stockfish PUBLIC Threads::Threads)

message(STATUS "Mini Xiangqi core: Fairy-Stockfish arch profile ${MXQ_FS_ARCH_PROFILE}")
