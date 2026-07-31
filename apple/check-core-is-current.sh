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
# as the variant configuration does. It is nonetheless demanded rather than
# recreated, and the reason is what can be wrong with it rather than where it
# comes from: recreating answers "absent", and absent is no longer the only bad
# state. Since the bundled network's name changed, Resources can also hold the
# PREVIOUS network, or two networks, and a recreate would leave both there.
# apple/MiniXiangqi is a file-system-synchronized group, so both would be bundled
# and both would ship — dead weight at best, and at worst a network this project
# has no licence to distribute. The runtime would not complain, because the
# bridge prefers the pinned basename. So this asserts the Windows packaging
# build's rule on the app's own resources: exactly one network, under the name
# pinned-inputs.json pins, and anything else stops the build and says which.
nnue_name=$(plutil -extract network.filename raw -o - "$root/pinned-inputs.json")
resources="$root/apple/MiniXiangqi/Resources"
staged_networks=""
for network in "$resources"/*.nnue; do
  [ -e "$network" ] || continue
  staged_networks="$staged_networks $(basename "$network")"
done
staged_networks=${staged_networks# }

if [ -z "$staged_networks" ]; then
  echo "error: the bundled NNUE network $nnue_name has not been staged." >&2
  echo "note: run ./apple/build-core-xcframework.sh, which verifies it against pinned-inputs.json and stages it from core/assets." >&2
  exit 1
fi
if [ "$staged_networks" != "$nnue_name" ]; then
  echo "error: the app's resources hold [$staged_networks]; pinned-inputs.json pins exactly one, $nnue_name." >&2
  echo "note: run ./apple/build-core-xcframework.sh, which removes any other network before staging the pinned one." >&2
  exit 1
fi
