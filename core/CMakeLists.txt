# Build for the shared core.
#
# Two targets: the static library `mxq_core`, which is what each frontend links,
# and the executable `mxq_core_tests`, which is the one shared C++ test runner
# docs/architecture.md requires — it runs on every development platform without
# a frontend and executes the approved fixtures identically everywhere.
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
       "Build the fixture runner against a rules facade that exists. Off until \
the pinned Fairy-Stockfish fork is vendored and the facade is implemented; \
while it is off, every fixture reports NOT IMPLEMENTED rather than passing."
       OFF)

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
mxq_pinned_get(MXQ_BUILD_NNUE_SHA256 network sha256)

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

add_library(mxq_warnings INTERFACE)
if(MSVC)
  target_compile_options(mxq_warnings INTERFACE /W4 /permissive-)
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
# The static library
# --------------------------------------------------------------------------
#
# Only the functions the contract marks callable from any thread without a core
# instance are implemented so far: the status and blob helpers, mxq_core_version,
# mxq_rules_start_fen, mxq_archive_supported_versions, and mxq_engine_plan,
# whose arithmetic the contract defines precisely so that it is testable without
# an engine. The remaining declarations in mxq.h are deliberately left undefined
# rather than stubbed: the accepted error taxonomy has no not-implemented code,
# and inventing one to return would be inventing contract vocabulary.

add_library(mxq_core STATIC
  src/mxq_abi.cpp
  src/mxq_archive.cpp
  src/mxq_blob.cpp
  src/mxq_core.cpp
  src/mxq_engine.cpp
  src/mxq_internal.cpp
  src/mxq_rules.cpp
  src/mxq_status.cpp
)
add_library(mxq::core ALIAS mxq_core)

target_include_directories(mxq_core
  PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
  PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
    "${MXQ_GENERATED_DIR}"
)
target_link_libraries(mxq_core PRIVATE mxq_warnings)
set_target_properties(mxq_core PROPERTIES
  CXX_VISIBILITY_PRESET hidden
  VISIBILITY_INLINES_HIDDEN ON
  OUTPUT_NAME mxqcore
)

# --------------------------------------------------------------------------
# Vendored third-party inputs
# --------------------------------------------------------------------------
#
# Neither the pinned Fairy-Stockfish fork nor the vendored SQLite amalgamation
# is part of this scaffold. Each drops into core/third_party/<name>/ carrying
# its own CMakeLists.txt that defines the aliased target named below, and is
# picked up here with no rearrangement of anything above: the loop links it into
# mxq_core privately, which is what keeps both invisible through mxq.h, as
# docs/architecture.md requires. See core/third_party/README.md.

foreach(mxq_dep IN ITEMS fairy-stockfish sqlite)
  if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/third_party/${mxq_dep}/CMakeLists.txt")
    add_subdirectory("third_party/${mxq_dep}")
    target_link_libraries(mxq_core PRIVATE "mxq::${mxq_dep}")
    message(STATUS "Mini Xiangqi core: vendored ${mxq_dep}")
  else()
    message(STATUS "Mini Xiangqi core: ${mxq_dep} not vendored")
  endif()
endforeach()

# --------------------------------------------------------------------------
# Tests
# --------------------------------------------------------------------------

include(CTest)
if(BUILD_TESTING)
  add_subdirectory(tests)
endif()
