#!/bin/sh
# A digest of everything the shared core is built from.
#
# One definition, read by apple/build-core-xcframework.sh when it records the
# fingerprint and by apple/check-core-is-current.sh when it compares — so the
# two can never disagree about what was hashed.

set -eu

root=$(cd "$(dirname "$0")/.." && pwd)

# The vendored engine is included: re-vendoring the fork is exactly the kind of
# change that must not slip through. -print0 and -0 so a path with a space
# cannot split an entry.
find "$root/core/src" "$root/core/include" "$root/core/assets" \
     "$root/core/third_party" "$root/core/CMakeLists.txt" \
     "$root/apple/build-core-xcframework.sh" \
     -type f -print0 2>/dev/null \
  | LC_ALL=C sort -z \
  | xargs -0 shasum -a 256 \
  | shasum -a 256 \
  | cut -d' ' -f1
