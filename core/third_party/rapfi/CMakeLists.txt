# The pinned Rapfi fork, built as a static library the core links.
#
# This file is ours, not the fork's. Everything under upstream/ is a verbatim
# copy of the pinned revision and is never edited here; see README.md for the
# vendoring record and the re-cut recipe.
#
# core/CMakeLists.txt adds this directory only when MXQ_ENABLE_GOMOKU_FACADE is
# ON, so the default configuration neither compiles nor links any of it.

cmake_minimum_required(VERSION 3.24)

# lz4 and xxhash are C. The core project declares CXX alone, because that is
# what the core itself is written in.
enable_language(C)

# NEON dotprod is armv8.2-a and safe on A12 and newer, so whether it may be
# selected is the Apple deployment target's answer rather than this file's. It is
# declared here so that the arm64 branch below reads a variable this build
# defines rather than one it hopes was set; nothing sets it today, and
# pinned-inputs.json records the decision as unanswered for want of a
# measurement rather than for want of a floor.
option(MXQ_RAPFI_NEON_DOTPROD
       "Select NEON dotprod on arm64 targets. Requires every supported device \
to be A12 or newer, which the app's deployment target does guarantee; off until \
a measurement says what it buys."
       OFF)

set(MXQ_RAPFI_UPSTREAM "${CMAKE_CURRENT_SOURCE_DIR}/upstream")
set(MXQ_RAPFI_SRC "${MXQ_RAPFI_UPSTREAM}/Rapfi")
set(MXQ_RAPFI_EXTERNAL "${MXQ_RAPFI_SRC}/external")

# --------------------------------------------------------------------------
# The bundled externals
# --------------------------------------------------------------------------
#
# Three of the fork's eight vendored externals reach this snapshot; the other
# five are included only from inside a COMMAND_MODULES guard and are not in it.
# Each one's own CMakeLists.txt is a build description of the fork's, excluded
# from the snapshot for the same reason the fork's top-level one is, so the two
# header-only targets and the one C library are declared here instead. All three
# are trivial, and their upstream files say the same thing these lines do.
#
# lz4 is required rather than optional: every NNUE weight file is an LZ4 frame,
# and Compressor::Type::LZ4_DEFAULT is how the engine opens one.

add_library(mxq_rapfi_cpptoml INTERFACE)
target_include_directories(mxq_rapfi_cpptoml INTERFACE
                           "${MXQ_RAPFI_EXTERNAL}/cpptoml/include")

add_library(mxq_rapfi_simde INTERFACE)
target_include_directories(mxq_rapfi_simde INTERFACE
                           "${MXQ_RAPFI_EXTERNAL}/simde/include")

add_library(mxq_rapfi_lz4 STATIC
  "${MXQ_RAPFI_EXTERNAL}/lz4/src/lz4_all.c"
  "${MXQ_RAPFI_EXTERNAL}/lz4/src/xxhash.c"
)
target_include_directories(mxq_rapfi_lz4 PUBLIC
                           "${MXQ_RAPFI_EXTERNAL}/lz4/include")
set_target_properties(mxq_rapfi_lz4 PROPERTIES
  POSITION_INDEPENDENT_CODE ON
  OUTPUT_NAME mxqrapfilz4
)

# --------------------------------------------------------------------------
# Sources
# --------------------------------------------------------------------------
#
# Listed explicitly rather than globbed: a glob would silently change what the
# core links when the vendored snapshot is re-cut, and the pinned inputs are
# meant to be reviewable. This is the fork's own library split — its CORE_SOURCES
# at the pinned revision, which is everything the executable compiles except
# main.cpp, command/gomocup.cpp and the command modules — so a source here is a
# source the fork's rapfi_engine target carries.

set(MXQ_RAPFI_SOURCES
  command/argutils.cpp
  command/benchmark.cpp
  command/command.cpp
  command/dbcommand.cpp

  core/compressor.cpp
  core/hash.cpp
  core/iohelper.cpp
  core/utils.cpp
  core/platform.cpp
  core/version.cpp

  database/dbclient.cpp
  database/dbconfig.cpp
  database/dbutils.cpp
  database/dbtypes.cpp
  database/renlib.cpp
  database/yxdbstorage.cpp

  eval/eval.cpp
  eval/evalconfig.cpp
  eval/evaluator.cpp
  eval/mix9svqnnue.cpp
  eval/mix10nnue.cpp

  game/board.cpp
  game/movegen.cpp
  game/pattern.cpp

  search/hashtable.cpp
  search/movepick.cpp
  search/opening.cpp
  search/searchcommon.cpp
  search/searchconfig.cpp
  search/searchengine.cpp
  search/searchoutput.cpp
  search/searchthread.cpp
  search/timecontrol.cpp
  search/ab/history.cpp
  search/ab/search.cpp
  search/mcts/node.cpp
  search/mcts/search.cpp

  config.cpp
  internalConfig.cpp
)
list(TRANSFORM MXQ_RAPFI_SOURCES PREPEND "${MXQ_RAPFI_SRC}/")

foreach(mxq_rapfi_source IN LISTS MXQ_RAPFI_SOURCES)
  if(NOT EXISTS "${mxq_rapfi_source}")
    message(FATAL_ERROR
      "vendored Rapfi source missing: ${mxq_rapfi_source}. The snapshot under "
      "upstream/ is incomplete; re-cut it as described in README.md.")
  endif()
endforeach()

add_library(mxq_rapfi STATIC ${MXQ_RAPFI_SOURCES})
add_library(mxq::rapfi ALIAS mxq_rapfi)

# --------------------------------------------------------------------------
# Language and interface
# --------------------------------------------------------------------------
#
# The fork compiles as C++17 and the core as C++20. They are separate targets,
# so each keeps its own standard; the engine's headers are C++17 and compile
# cleanly when a C++20 core translation unit includes them.
#
# Exceptions are ON, unlike the Fairy-Stockfish target beside this one, and that
# is not a style difference: this engine's config parsing, weight loading and
# large-page allocation all report failure by throwing, and the evaluator maker
# is a try/catch over UnsupportedRuleError and UnsupportedBoardSizeError. Built
# with -fno-exceptions it would not compile, and if it did it could not report.

set_target_properties(mxq_rapfi PROPERTIES
  CXX_STANDARD 17
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
  POSITION_INDEPENDENT_CODE ON
  OUTPUT_NAME mxqrapfi
)

# PUBLIC, but only within this project: core/CMakeLists.txt links this target
# into mxq_core PRIVATE, so neither the include directory nor the defines reach
# anything that consumes mxq_core. That is what keeps the engine invisible
# through mxq.h, per docs/architecture.md.
target_include_directories(mxq_rapfi PUBLIC "${MXQ_RAPFI_SRC}")
target_link_libraries(mxq_rapfi PUBLIC
  mxq_rapfi_cpptoml
  mxq_rapfi_simde
  mxq_rapfi_lz4
)

# --------------------------------------------------------------------------
# Defines
# --------------------------------------------------------------------------
#
# These reproduce the fork's own CMake options at the pinned revision, read from
# its CMakeLists.txt rather than assumed:
#
#   NOT NO_MULTI_THREADING -> MULTI_THREADING   (Rapfi/CMakeLists.txt:495-497)
#   USE_NEON               -> USE_NEON          (:513-515)
#   USE_NEON_DOTPROD       -> USE_NEON_DOTPROD  (:516-518)
#   USE_SSE                -> USE_SSE           (:501-503)
#
# COMMAND_MODULES is deliberately absent, and it is load-bearing rather than
# tidy: the module sources are not in this snapshot, and three files switch on
# the define to reach externals that are not in it either — core/compressor.cpp
# for zip, command/argutils.{h,cpp} for cxxopts. Defining it would fail to
# compile.
#
# MULTI_THREADING is required rather than a margin. Without it the fork collapses
# startThinking() to a synchronous call that returns only when the search is over
# (searchengine.h:189-191), which would make the facade's asynchronous search and
# its cooperative cancellation impossible to express.
#
# They must be PUBLIC. USE_NEON selects a different NativeInstType in
# eval/simd/isa.h and with it a different set of inline vector operations, so a
# core translation unit that includes an engine header and did not see the same
# define would disagree with the library about the types in it.

target_compile_definitions(mxq_rapfi PUBLIC MULTI_THREADING)

# Architecture-dependent instruction selection. Anything not recognised falls
# back to the engine's scalar profile — correct everywhere, slower — rather than
# to a guess about the target's instruction set.
set(MXQ_RAPFI_ARCH "${CMAKE_SYSTEM_PROCESSOR}")
if(CMAKE_OSX_ARCHITECTURES)
  list(LENGTH CMAKE_OSX_ARCHITECTURES mxq_rapfi_osx_arch_count)
  if(mxq_rapfi_osx_arch_count GREATER 1)
    message(FATAL_ERROR
      "the vendored engine selects instruction-set defines per architecture and "
      "cannot be built as a universal binary in one pass; configure once per "
      "architecture (CMAKE_OSX_ARCHITECTURES=${CMAKE_OSX_ARCHITECTURES}).")
  endif()
  set(MXQ_RAPFI_ARCH "${CMAKE_OSX_ARCHITECTURES}")
endif()

if(MXQ_RAPFI_ARCH MATCHES "^(arm64|arm64e|aarch64|ARM64)$")
  # NEON is baseline on every arm64 target, and it is selected explicitly rather
  # than left to the fork's host probe: that probe is skipped under
  # CMAKE_CROSSCOMPILING and, when it does run, can fail on Apple Clang and
  # silently produce a scalar build.
  target_compile_definitions(mxq_rapfi PUBLIC USE_NEON)
  set(MXQ_RAPFI_ARCH_PROFILE "arm64 (NEON)")

  # NEON dotprod is armv8.2-a and is safe on A12 and newer. Whether that is every
  # device this build runs on is the Apple deployment target's answer, not this
  # file's, so it is a decision the caller passes down rather than one taken here
  # from the architecture alone.
  if(MXQ_RAPFI_NEON_DOTPROD)
    target_compile_definitions(mxq_rapfi PUBLIC USE_NEON_DOTPROD)
    set(MXQ_RAPFI_ARCH_PROFILE "arm64 (NEON + dotprod)")
  endif()

  # The fork's own flag here is -march=armv8-a+simd, or armv8.2-a+dotprod with
  # dotprod on (Rapfi/CMakeLists.txt:585, :583). Neither is passed. On Apple
  # targets -march is not how the baseline is chosen — the deployment target and
  # the slice are — and arm64e requires armv8.3-a, which armv8-a+simd would
  # silently lower. NEON needs no flag on arm64: <arm_neon.h> and every intrinsic
  # the engine uses are available at the baseline. Dotprod does need one, and it
  # is spelled as the feature rather than as an architecture revision so that the
  # arm64e slice keeps its own.
  if(MXQ_RAPFI_NEON_DOTPROD AND NOT MSVC)
    target_compile_options(mxq_rapfi PRIVATE -march=armv8.2-a+dotprod)
  endif()
elseif(MXQ_RAPFI_ARCH MATCHES "^(x86_64|AMD64|amd64)$")
  # SSE2/SSSE3/SSE4.1, which is the engine's own USE_SSE profile and the floor
  # every x86_64 target meets. AVX2 is deliberately not selected: this slice is
  # the simulator's, where correctness on whatever host runs it outranks a search
  # rate nobody plays at.
  target_compile_definitions(mxq_rapfi PUBLIC USE_SSE)
  if(NOT MSVC)
    target_compile_options(mxq_rapfi PRIVATE
                           -msse -msse2 -msse3 -mssse3 -msse4 -msse4.1)
  endif()
  set(MXQ_RAPFI_ARCH_PROFILE "x86_64 (SSE4.1)")
else()
  set(MXQ_RAPFI_ARCH_PROFILE "generic (scalar)")
endif()

# --------------------------------------------------------------------------
# Compile options
# --------------------------------------------------------------------------
#
# The core's mxq_warnings target is deliberately NOT linked here, for the reason
# the Fairy-Stockfish directory beside this one gives: its warning set is a
# standard the core holds itself to, and applying it to a vendored snapshot we do
# not edit would make an upstream style choice fail our build. The fork's own
# warning flags are used instead.

if(NOT MSVC)
  target_compile_options(mxq_rapfi PRIVATE
    -Wall -Wno-unused-variable -Wno-unused-function -Wno-missing-braces
    -Wno-logical-op-parentheses -Wno-parentheses -Wno-sign-compare)
  # The fork disables floating-point contraction so that its evaluation is
  # bit-identical between GCC and Clang; the NNUE value head finishes in float,
  # and a fused multiply-add there changes search decisions. Kept, because a
  # network's measured behaviour should not depend on which compiler built it.
  target_compile_options(mxq_rapfi PRIVATE -ffp-contract=off)
else()
  target_compile_options(mxq_rapfi PRIVATE /W3)
endif()

# The one warning family that has to be suppressed on the INTERFACE rather than
# privately, mirroring the Fairy-Stockfish target beside this one for the same
# reason. This engine is C++17 and its headers do arithmetic and bitwise
# operations on differently typed enums, which C++20 deprecated. The core is
# C++20, and the bridge includes eleven of those headers while linking
# mxq_warnings — so with MXQ_WARNINGS_AS_ERRORS on, our own translation unit
# would fail to compile because of the vendored snapshot's style. The engine's
# own sources never see it; they are built as C++17.
#
# It compiles clean today, which is exactly when to write the guard: nothing
# about the snapshot promises the next one will, and the failure lands on our
# file rather than on the header it comes from.
#
# Scoped to the specific deprecation rather than a blanket -w or /w, and both
# spellings are listed because the same deprecation has two names — Clang and
# GCC call it -Wdeprecated-enum-enum-conversion, MSVC calls it C5054. The probe
# is what keeps the list safe: a compiler that does not know a flag never
# receives it.
include(CheckCXXCompilerFlag)
foreach(mxq_rapfi_flag -Wno-deprecated-enum-enum-conversion
                       -Wno-deprecated-anon-enum-enum-conversion
                       /wd5054)
  string(MAKE_C_IDENTIFIER "MXQ_RAPFI_HAVE${mxq_rapfi_flag}" mxq_rapfi_flag_var)
  check_cxx_compiler_flag("${mxq_rapfi_flag}" ${mxq_rapfi_flag_var})
  if(${mxq_rapfi_flag_var})
    target_compile_options(mxq_rapfi INTERFACE
      "$<$<COMPILE_LANGUAGE:CXX>:${mxq_rapfi_flag}>")
  endif()
endforeach()

# --------------------------------------------------------------------------
# Link dependencies
# --------------------------------------------------------------------------

set(THREADS_PREFER_PTHREAD_FLAG ON)
find_package(Threads REQUIRED)
target_link_libraries(mxq_rapfi PUBLIC Threads::Threads)

message(STATUS "Mini Xiangqi core: Rapfi arch profile ${MXQ_RAPFI_ARCH_PROFILE}")
