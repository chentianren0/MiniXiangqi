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

# The check is read-only. Every generated or staged artifact comes only from the
# generator (or is copied intact into a worktree); absence or drift stays red
# until the generator runs.
generated="$root/apple/Generated"
if [ ! -f "$generated/CoreHeaders/mxq.h" ] ||
   [ ! -f "$generated/CoreHeaders/module.modulemap" ]; then
  echo "error: the generated core headers have not been staged." >&2
  echo "note: run ./apple/build-core-xcframework.sh, then build again." >&2
  exit 1
fi

# The engine's assets ship as one pack, apple/MiniXiangqi/Core/AssetPack.swift,
# which the generator writes from core/assets after verifying every input
# against pinned-inputs.json and then reads back entry by entry. The check is by
# content against the digest the generator recorded beside it, for the same
# reason the core is: a pack from another branch, or a damaged one, must not
# pass because a file of the right name is present.
resources="$root/apple/MiniXiangqi/Resources"
pack_name="engine-assets.mxqpack" # AssetPack.fileName
pack="$resources/$pack_name"
recorded_pack="$root/apple/Generated/engine-assets.digest"
if [ ! -f "$pack" ] || [ ! -f "$recorded_pack" ]; then
  echo "error: the engine asset pack has not been staged." >&2
  echo "note: run ./apple/build-core-xcframework.sh, which verifies the assets against pinned-inputs.json and packs them." >&2
  exit 1
fi
if [ "$(shasum -a 256 "$pack" | cut -d' ' -f1)" != "$(cat "$recorded_pack")" ]; then
  echo "error: the engine asset pack does not match the one the generator recorded." >&2
  echo "note: run ./apple/build-core-xcframework.sh, then build again." >&2
  exit 1
fi

# And nothing beside it. apple/MiniXiangqi is a file-system-synchronized group,
# so every file in Resources ships in the .app: a network or configuration left
# here — as the files were staged before the pack existed, or by a generator
# from before it — would ship verbatim, which is what the pack exists to
# prevent. The generator removes them; this refuses a build until it has.
for staged in "$resources"/*; do
  [ -e "$staged" ] || continue
  [ "$(basename "$staged")" = "$pack_name" ] && continue
  echo "error: Resources carries a file beside the engine asset pack: $(basename "$staged")" >&2
  echo "note: run ./apple/build-core-xcframework.sh, which leaves only the pack there." >&2
  exit 1
done
