# The pinned Pikafish jieqi fork's rules slice, built as a static library.
#
# This file is ours, not the fork's. Everything under upstream/ is a verbatim
# copy of the pinned revision and is never edited here; see README.md for the
# vendoring record, for what the slice is and is not, and for how it is re-cut.
# mxq_pikafish_link_closure.cpp beside this file is ours too, and it is the one
# translation unit in the target that is not the fork's — it carries the three
# definitions the slice references and the three .cpp files it does not take
# would have supplied.
#
# core/CMakeLists.txt adds this directory only when MXQ_ENABLE_RULES_FACADE is
# ON, so the default configuration neither compiles nor links any of it.
#
# NOTHING REFERENCES THIS TARGET YET except the core's jieqi smoke-test runner.
# The library is linked into mxq_core all the same, and therefore travels into
# MiniXiangqiCore.xcframework, because the framework build is the one place the
# slice's cross-platform reality is proven: the iOS SDK, the Simulator slice,
# and the arm64 and arm64e device architectures. That evidence belongs to the
# stage that vendors the sources rather than to the bridge stage that would
# otherwise be the first to discover a platform the slice does not compile on.
# It costs the app nothing: a static archive's members are pulled in only to
# resolve a reference, and until the bridge lands there is no reference, so not
# one byte of this engine reaches the shipped binary.

cmake_minimum_required(VERSION 3.24)

set(MXQ_PF_UPSTREAM "${CMAKE_CURRENT_SOURCE_DIR}/upstream")
set(MXQ_PF_SRC "${MXQ_PF_UPSTREAM}/src")

# --------------------------------------------------------------------------
# Sources
# --------------------------------------------------------------------------
#
# Three translation units, and that is the whole slice. The fork builds
# thirty-four of them into an engine; this vendoring takes the three that decide
# the rules — the position, the move generator and the attack tables — and none
# of the search, evaluation, NNUE, protocol or thread machinery around them.
# What is here is what a rules authority needs and nothing else.
#
# Listed explicitly rather than globbed, for the same reason the other vendored
# engines list theirs: a glob would silently change what the core links when the
# snapshot is re-cut, and the pinned inputs are meant to be reviewable. Here it
# matters more than usual, because the snapshot IS a selection: a re-cut that
# accidentally widened it would otherwise start compiling the search.

set(MXQ_PF_SOURCES
  bitboard.cpp
  movegen.cpp
  position.cpp
)
list(TRANSFORM MXQ_PF_SOURCES PREPEND "${MXQ_PF_SRC}/")

foreach(mxq_pf_source IN LISTS MXQ_PF_SOURCES)
  if(NOT EXISTS "${mxq_pf_source}")
    message(FATAL_ERROR
      "vendored Pikafish source missing: ${mxq_pf_source}. The snapshot under "
      "upstream/ is incomplete; re-cut it as described in README.md.")
  endif()
endforeach()

add_library(mxq_pikafish STATIC
  ${MXQ_PF_SOURCES}
  "${CMAKE_CURRENT_SOURCE_DIR}/mxq_pikafish_link_closure.cpp"
)
add_library(mxq::pikafish ALIAS mxq_pikafish)

# --------------------------------------------------------------------------
# Language and interface
# --------------------------------------------------------------------------
#
# The fork compiles as C++17 — src/Makefile:432 passes -std=c++17 at the pinned
# revision — and the core as C++20. They are separate targets, so each keeps its
# own standard; the engine's headers compile cleanly when a C++20 core
# translation unit includes them, once the one C++20 deprecation the fork's
# C++17 headers trip is suppressed on the interface below.

set_target_properties(mxq_pikafish PROPERTIES
  CXX_STANDARD 17
  CXX_STANDARD_REQUIRED ON
  CXX_EXTENSIONS OFF
  POSITION_INDEPENDENT_CODE ON
  OUTPUT_NAME mxqpikafish
)

# PUBLIC, but only within this project: core/CMakeLists.txt links this target
# into mxq_core with $<LINK_ONLY:>, so neither this include directory nor the
# defines below reach a single core translation unit — which is deliberate and
# is explained where that link is written. The runner that does include these
# headers links the target normally and so agrees with it.
target_include_directories(mxq_pikafish PUBLIC "${MXQ_PF_SRC}")

# --------------------------------------------------------------------------
# The namespace rename, which is the reason this target can exist at all
# --------------------------------------------------------------------------
#
# Both engines this core embeds are Stockfish derivatives. Fairy-Stockfish and
# Pikafish declare the SAME namespace, `Stockfish`, and inside it the same class
# names with the same signatures: Position::init, Bitboards::init,
# Position::set, Position::fen, MoveList, and dozens more. Their bodies are
# entirely different games — a 12x10-capable variant engine and a jieqi engine
# with hidden pieces — and their tables have different shapes.
#
# Two static archives holding identical strong symbols do not fail to link. The
# linker takes the first definition it resolves each reference against and
# discards the rest, so LINK ORDER decides which engine's body runs, silently.
# The failure this prevents is not a link error and not a crash at the seam: it
# is one engine's code reading the other engine's tables, in a build that
# compiled, linked and started cleanly. On the two boards involved that reads as
# wrong legal moves rather than as a fault.
#
# So the whole namespace is renamed on the command line. It is a preprocessor
# rename of one identifier, which is why it can be applied to sources that are a
# verbatim copy: every `Stockfish` token in these files — declaration, use and
# qualification alike — becomes `PikafishJieqi`, consistently, and no vendored
# byte changes. It costs nothing at run time either, which was measured rather
# than assumed: each of the three objects compiled with and without the define
# has the same section sizes and the same __text bytes, so the rename moves
# symbol names and no instruction.
#
# PUBLIC because agreement is the point. A consumer that included these headers
# without the define would emit `Stockfish::` references against a library that
# exports `PikafishJieqi::` ones, and the two would not meet. Making the rename
# an interface property of the target is what removes the possibility of a
# consumer disagreeing with the library about which engine it is calling.
#
# Fairy-Stockfish is deliberately NOT the one renamed. It is the older embedding,
# its bridge and its tests name `Stockfish::` throughout, and the engine that
# arrives second is the one that pays.

target_compile_definitions(mxq_pikafish PUBLIC Stockfish=PikafishJieqi)

# --------------------------------------------------------------------------
# Defines
# --------------------------------------------------------------------------
#
# These are the fork's own, read from src/Makefile at the pinned revision rather
# than assumed, and narrowed to what a rules slice compiles:
#
#   debug = no          -> NDEBUG        (Makefile:629-630)
#   bits = 64           -> IS_64BIT      (Makefile:673-674)
#   popcnt = yes        -> USE_POPCNT    (Makefile:686-690)
#   prefetch = no       -> NO_PREFETCH   (Makefile:678-683)
#
# NDEBUG is not set here. The core's build type sets it — every configuration
# but Debug — and docs/testing.md wants a debug run to observe assertions, which
# includes this engine's own pos_is_ok.
#
# NO_PREFETCH is the fork's own portable profile and it is chosen rather than
# inherited: the slice does not take misc.cpp, so the prefetch body is ours
# (mxq_pikafish_link_closure.cpp), and ours is the no-op the NO_PREFETCH profile
# defines. Setting the define is what keeps the profile and the body describing
# the same build. It has a second effect worth having: types.h reaches for
# <xmmintrin.h> under MSVC when prefetch is enabled, which is an x86-only header
# and a hard stop on Windows ARM64 — the same trap the Fairy-Stockfish
# CMakeLists documents from having hit it.
#
# The fork's SIMD defines are deliberately absent. USE_NEON, USE_NEON_DOTPROD,
# USE_AVX2 and their relatives select instruction sets for NNUE evaluation, and
# no NNUE translation unit is in this slice — the NNUE headers are here only
# because position.h includes the feature set for its accumulator field, and no
# code in them is instantiated. Carrying USE_NEON_DOTPROD would additionally
# raise the ISA floor to armv8.2-a for code that is not compiled, which is a
# deployment decision taken for nothing.

target_compile_definitions(mxq_pikafish PUBLIC NO_PREFETCH)

# IS_64BIT is defined here only where the fork's Makefile defines it. types.h
# defines it itself on `_WIN64 && _MSC_VER`, "No Makefile used", where it also
# pulls in <intrin.h> for _BitScanForward64 — so defining it on the command line
# there too is a C4005 macro redefinition on every translation unit. The
# condition below is that rule read from the other side, and the two halves
# together define it exactly once everywhere. This is the same split
# Fairy-Stockfish's build makes, for the same reason and against the same lines.
if(CMAKE_SIZEOF_VOID_P EQUAL 8 AND NOT MSVC)
  target_compile_definitions(mxq_pikafish PUBLIC IS_64BIT)
endif()

# Architecture-dependent instruction selection, which for this slice is popcount
# and nothing else: Bitboard is a 128-bit integer here and popcount is on the
# hot path of move generation. Anything not recognised falls back to the fork's
# portable 16-bit table — correct everywhere, slower — rather than to a guess
# about the target's instruction set.
set(MXQ_PF_ARCH "${CMAKE_SYSTEM_PROCESSOR}")
if(CMAKE_OSX_ARCHITECTURES)
  list(LENGTH CMAKE_OSX_ARCHITECTURES mxq_pf_osx_arch_count)
  if(mxq_pf_osx_arch_count GREATER 1)
    message(FATAL_ERROR
      "the vendored jieqi engine selects instruction-set defines per "
      "architecture and cannot be built as a universal binary in one pass; "
      "configure once per architecture "
      "(CMAKE_OSX_ARCHITECTURES=${CMAKE_OSX_ARCHITECTURES}).")
  endif()
  set(MXQ_PF_ARCH "${CMAKE_OSX_ARCHITECTURES}")
endif()

if(MXQ_PF_ARCH MATCHES "^(arm64|aarch64|ARM64)$" AND MSVC)
  # ARM64 under MSVC takes the portable profile. USE_POPCNT is a HEADER request
  # and which header depends on the compiler rather than on the target:
  # types.h:83 reaches for <nmmintrin.h> under _MSC_VER, an x86 header that
  # names ARM64 in the error it refuses that target with. Under Apple clang the
  # same define takes __builtin_popcountll and is right. No build here has
  # compiled this slice with MSVC on ARM64; the branch exists so that the first
  # one does not hit a trap the neighbouring engine already documented.
  set(MXQ_PF_ARCH_PROFILE "general-64 on arm64/MSVC (portable: popcount by table, no prefetch)")
elseif(MXQ_PF_ARCH MATCHES "^(arm64|arm64e|aarch64|ARM64)$")
  # The fork's ARCH=apple-silicon profile, less the NNUE SIMD it also sets:
  # popcnt, no SSE. arm64e is the same ISA baseline and better (armv8.3-a), and
  # no -march is passed that could lower it.
  target_compile_definitions(mxq_pikafish PUBLIC USE_POPCNT)
  set(MXQ_PF_ARCH_PROFILE "apple-silicon (arm64/arm64e: popcnt)")
elseif(MXQ_PF_ARCH MATCHES "^(x86_64|AMD64|amd64)$")
  target_compile_definitions(mxq_pikafish PUBLIC USE_POPCNT)
  if(NOT MSVC)
    # Makefile:690 for a non-arm popcnt target.
    target_compile_options(mxq_pikafish PRIVATE -msse3 -mpopcnt)
  endif()
  set(MXQ_PF_ARCH_PROFILE "x86-64-sse3-popcnt")
else()
  set(MXQ_PF_ARCH_PROFILE "general (portable, popcount by table, no prefetch)")
endif()

# --------------------------------------------------------------------------
# Compile options
# --------------------------------------------------------------------------
#
# The core's mxq_warnings target is deliberately NOT linked here, exactly as it
# is not linked into the other two vendored engines. Its warning set, and
# MXQ_WARNINGS_AS_ERRORS with it, is a standard the core holds itself to;
# applying it to a snapshot we do not edit would make an upstream style choice
# fail our build. The fork's own flags, from src/Makefile at the pinned
# revision, are used instead — and under them the slice compiles with no
# diagnostic at all as C++17.
#
# mxq_pikafish_link_closure.cpp takes the same flags although it is ours. It is
# three definitions completing this snapshot and it is read beside it; giving
# one file in the target a different standard and a different warning set would
# buy nothing and would make the target two things.

if(NOT MSVC)
  target_compile_options(mxq_pikafish PRIVATE
    -Wall -Wcast-qual -fno-exceptions)
else()
  target_compile_options(mxq_pikafish PRIVATE /W3)
endif()

# The one warning that has to be suppressed on the INTERFACE rather than
# privately, and it is the same one the neighbouring engine suppresses for the
# same reason. The fork is C++17 and types.h and bitboard.h do arithmetic on
# differently typed enums — Square with File, Rank with File — which C++20
# deprecated. The core and its runners are C++20, so a translation unit of ours
# that includes these headers is warned about the fork's code rather than its
# own, and with MXQ_WARNINGS_AS_ERRORS it would fail to compile because of it.
# The engine's own sources never see it; they are built as C++17.
#
# Scoped to the specific deprecation rather than a blanket -w or /w, so a file
# of ours that includes an engine header keeps every other warning the project
# sets. Three spellings because the same deprecation has three names across the
# compilers this project builds with, and the probe is what keeps the list safe:
# a compiler that does not know a flag never receives it.
include(CheckCXXCompilerFlag)
foreach(mxq_pf_flag -Wno-deprecated-enum-enum-conversion
                    -Wno-deprecated-anon-enum-enum-conversion
                    /wd5054)
  string(MAKE_C_IDENTIFIER "MXQ_PF_HAVE${mxq_pf_flag}" mxq_pf_flag_var)
  check_cxx_compiler_flag("${mxq_pf_flag}" ${mxq_pf_flag_var})
  if(${mxq_pf_flag_var})
    target_compile_options(mxq_pikafish INTERFACE
      "$<$<COMPILE_LANGUAGE:CXX>:${mxq_pf_flag}>")
  endif()
endforeach()

# --------------------------------------------------------------------------
# Link dependencies
# --------------------------------------------------------------------------
#
# The slice starts no thread and holds no lock — search and the thread pool are
# the half that is not here — but numa.h and thread_win32_osx.h are in the
# header closure and reach std::thread, so the target declares the dependency
# its headers create rather than relying on a platform where it happens to be
# folded into the standard library.

set(THREADS_PREFER_PTHREAD_FLAG ON)
find_package(Threads REQUIRED)
target_link_libraries(mxq_pikafish PUBLIC Threads::Threads)

message(STATUS "Mini Xiangqi core: Pikafish jieqi arch profile ${MXQ_PF_ARCH_PROFILE}")
