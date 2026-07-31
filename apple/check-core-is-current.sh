#!/bin/sh
# Fail the build if the app is about to link a core older than the core sources.
#
# The framework is a prebuilt dependency, produced by
# apple/build-core-xcframework.sh. It cannot be produced during the build:
# ProcessXCFramework, the task that extracts the library the app links, plans
# its inputs before any phase runs, so a framework rebuilt mid-build is picked
# up only by the next one — silently, which is the whole danger. This makes the
# staleness loud instead.
#
# The comparison is by content digest rather than by modification time, because
# switching branches rewinds timestamps and would make a stale core look fresh.

set -eu

# Under Xcode PROJECT_DIR is the apple/ directory; run by hand there is no
# PROJECT_DIR, and this script's own location is the same directory.
root=$(cd "${PROJECT_DIR:-$(dirname "$0")}/.." && pwd)
recorded="$root/apple/Generated/core-inputs.digest"

if [ ! -f "$recorded" ] || [ -z "$(find "$root/apple/Generated" -name libMiniXiangqiCore.a 2>/dev/null | head -1)" ]; then
  echo "error: the shared core has not been built." >&2
  echo "note: run ./apple/build-core-xcframework.sh, then build again." >&2
  exit 1
fi

# Content, not timestamps. A git checkout of another branch rewinds mtimes, so
# a timestamp comparison would call a stale core fresh — silently, which is the
# one failure this exists to prevent.
if [ "$(cat "$recorded")" != "$("$root/apple/core-inputs-digest.sh")" ]; then
  echo "error: the shared core has changed since it was last built." >&2
  echo "note: run ./apple/build-core-xcframework.sh, then build again." >&2
  exit 1
fi

# A seeded worktree arrives with the framework but without the two artifacts
# derived beside it: the CoreHeaders symlink (worktree seeding copies files,
# not symlinks) and the staged variant configuration. Both derive from content
# the digest above just verified as current, so they are recreated rather than
# demanded.
generated="$root/apple/Generated"
if [ ! -e "$generated/CoreHeaders" ]; then
  slice=$(cd "$generated/MiniXiangqiCore.xcframework" && ls -d macos-* | head -1)
  ln -sfn "MiniXiangqiCore.xcframework/$slice/Headers" "$generated/CoreHeaders"
fi
if [ ! -f "$root/apple/MiniXiangqi/Resources/minixiangqi-variants.ini" ]; then
  mkdir -p "$root/apple/MiniXiangqi/Resources"
  cp "$root/core/assets/minixiangqi-variants.ini" "$root/apple/MiniXiangqi/Resources/"
fi

# The bundled network is the third, and it now derives from core/assets exactly
# as the variant configuration does — the digest above covers both. It is still
# demanded rather than recreated, and the reason is Xcode rather than provenance:
# the app's resources are a file-system-synchronized group, whose contents are
# enumerated when the build is planned, so a file this phase creates is picked up
# by the *next* build. Recreating it here would produce one build with no network
# in the bundle and no complaint about it, which is precisely the silence this
# check exists to break. The variant configuration is recreated above because a
# seeded worktree always arrives with it; the network arrives the same way, and
# an absent one means the staging did not happen and should be said out loud.
nnue_name=$(plutil -extract network.filename raw -o - "$root/pinned-inputs.json")
if [ ! -f "$root/apple/MiniXiangqi/Resources/$nnue_name" ]; then
  echo "error: the bundled NNUE network $nnue_name has not been staged." >&2
  echo "note: run ./apple/build-core-xcframework.sh, which verifies it against pinned-inputs.json and stages it from core/assets." >&2
  exit 1
fi
