#!/bin/sh
# A digest of everything the shared core is built from.
#
# One definition, read by build-core-xcframework.sh when it records the
# fingerprint and by check-core-is-current.sh when it compares — so the
# two can never disagree about what was hashed.

set -eu

root=$(cd "$(dirname "$0")" && pwd)

# The vendored engine is included: re-vendoring the fork is exactly the kind of
# change that must not slip through. -print0 and -0 so a path with a space
# cannot split an entry.
# The per-file lines carry paths, and the final hash must not: the same
# sources checked out at another root — a worktree — are the same core, so the
# paths are made tree-relative before the digest of digests.
# core/cmake is in the list because mxq_build_config.h.in is compiled into the
# core: it is where every pinned name, byte length and hash reaches the bridges
# as a macro, so a change to it changes the library without changing anything
# else here.
# The asset pack's two sources are in the list because the generator writes the
# pack with them: a format change is a pack that must be written again, and
# nothing else here would notice one.
find "$root/core/src" "$root/core/include" "$root/core/assets" \
     "$root/core/cmake" \
     "$root/core/third_party" "$root/core/CMakeLists.txt" \
     "$root/pinned-inputs.json" \
     "$root/build-core-xcframework.sh" \
     "$root/MiniXiangqi/Core/AssetPack.swift" \
     "$root/AssetPackTool" \
     -type f -print0 2>/dev/null \
  | LC_ALL=C sort -z \
  | xargs -0 shasum -a 256 \
  | sed "s|  $root/|  |" \
  | shasum -a 256 \
  | cut -d' ' -f1
