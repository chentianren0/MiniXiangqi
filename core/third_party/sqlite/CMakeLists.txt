# The vendored SQLite amalgamation, built as a static library the core links.
#
# This file is ours, not SQLite's. Everything under upstream/ is a verbatim
# copy of the pinned amalgamation and is never edited here; see README.md for
# the vendoring record and pinned-inputs.json for the pin itself.
#
# Unlike the engine, this directory is not gated on any option: the store is
# part of the core on every configuration, and the amalgamation compiles in
# seconds rather than minutes.

cmake_minimum_required(VERSION 3.24)

# The core project declares only CXX; the amalgamation is C.
enable_language(C)

set(MXQ_SQLITE_UPSTREAM "${CMAKE_CURRENT_SOURCE_DIR}/upstream")

foreach(mxq_sqlite_file sqlite3.c sqlite3.h)
  if(NOT EXISTS "${MXQ_SQLITE_UPSTREAM}/${mxq_sqlite_file}")
    message(FATAL_ERROR
      "vendored SQLite file missing: ${MXQ_SQLITE_UPSTREAM}/${mxq_sqlite_file}. "
      "The amalgamation under upstream/ is incomplete; re-vendor it as "
      "described in README.md.")
  endif()
endforeach()

add_library(mxq_sqlite STATIC "${MXQ_SQLITE_UPSTREAM}/sqlite3.c")
add_library(mxq::sqlite ALIAS mxq_sqlite)

set_target_properties(mxq_sqlite PROPERTIES
  POSITION_INDEPENDENT_CODE ON
  OUTPUT_NAME mxqsqlite
)

# PUBLIC, but only within this project: core/CMakeLists.txt links this target
# into mxq_core PRIVATE, so neither the include directory nor the defines reach
# anything that consumes mxq_core. That is what keeps SQLite invisible through
# mxq.h, per docs/architecture.md.
target_include_directories(mxq_sqlite PUBLIC "${MXQ_SQLITE_UPSTREAM}")

# --------------------------------------------------------------------------
# Defines
# --------------------------------------------------------------------------
#
# The hardened compile-time option set docs/game-data.md requires of the
# vendored SQLite. Each entry is policy from the accepted contracts, not
# toolchain tuning, so the same set applies on every platform and is recorded
# in pinned-inputs.json under build_flags.<platform>.sqlite_defines.
#
#   SQLITE_OMIT_LOAD_EXTENSION   game-data.md: "without extension loading".
#                                Removes the load-extension code entirely
#                                rather than merely defaulting it off.
#   SQLITE_DQS=0                 Double-quoted string literals become errors.
#                                SQLite's own hardening recommendation; every
#                                statement the core issues is its own, so the
#                                misfeature has no legitimate caller here.
#   SQLITE_THREADSAFE=2          Multi-thread mode. core-interface.md: store
#                                operations execute on the calling thread
#                                under one internal mutex over one connection,
#                                so no connection is ever entered from two
#                                threads at once — which is exactly what mode 2
#                                requires — while SQLite's global subsystems
#                                stay protected from the engine thread that
#                                runs concurrently with store work.
#   SQLITE_OMIT_DEPRECATED       The deprecated interfaces are not compiled;
#                                nothing in the core calls them.
#   SQLITE_OMIT_SHARED_CACHE     game-data.md: one process, one connection.
#                                Shared cache is a discouraged mode with its
#                                own locking model; omitting it removes the
#                                code and its corner cases.
#   SQLITE_ENABLE_API_ARMOR      Detectable interface misuse returns
#                                SQLITE_MISUSE instead of being undefined
#                                behaviour. Defence in depth behind the core's
#                                own argument checks.
#   SQLITE_DEFAULT_FOREIGN_KEYS=1  game-data.md: foreign keys on. The open
#                                path still sets and verifies the pragma; the
#                                compiled default means a connection is never
#                                even briefly without enforcement.
#   SQLITE_DEFAULT_WAL_SYNCHRONOUS=2  game-data.md: write-ahead logging with
#                                full synchronous durability. As above, the
#                                open path sets and verifies synchronous=FULL;
#                                this pins the WAL-mode default to FULL too.

target_compile_definitions(mxq_sqlite PRIVATE
  SQLITE_OMIT_LOAD_EXTENSION
  SQLITE_DQS=0
  SQLITE_THREADSAFE=2
  SQLITE_OMIT_DEPRECATED
  SQLITE_OMIT_SHARED_CACHE
  SQLITE_ENABLE_API_ARMOR
  SQLITE_DEFAULT_FOREIGN_KEYS=1
  SQLITE_DEFAULT_WAL_SYNCHRONOUS=2
)

# The core's mxq_warnings target is deliberately NOT linked here, for the same
# reason as the engine snapshot: its warning set is a standard the core holds
# its own sources to, and applying it to vendored code we do not edit would
# make an upstream style choice fail our build. The amalgamation is compiled
# with the toolchain's default warnings.

message(STATUS "Mini Xiangqi core: SQLite amalgamation from ${MXQ_SQLITE_UPSTREAM}")
