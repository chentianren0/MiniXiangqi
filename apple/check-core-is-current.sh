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

resources="$root/apple/MiniXiangqi/Resources"
variant_source="$root/core/assets/minixiangqi-variants.ini"
variant_staged="$resources/minixiangqi-variants.ini"
if [ ! -f "$variant_staged" ]; then
  echo "error: the bundled variant configuration has not been staged." >&2
  echo "note: run ./apple/build-core-xcframework.sh, then build again." >&2
  exit 1
fi
if ! cmp -s "$variant_source" "$variant_staged"; then
  echo "error: the bundled variant configuration does not match core/assets." >&2
  echo "note: run ./apple/build-core-xcframework.sh, then build again." >&2
  exit 1
fi

# The bundled networks derive from core/assets exactly as the variant
# configuration does. Their names, counts and bytes are all load-bearing: a
# correctly named damaged file must not pass merely because it is present.
# Since a bundled network's name can change, Resources can also hold a previous
# network or an extra network, and a recreate would leave it there.
# apple/MiniXiangqi is a file-system-synchronized group, so every file would be
# bundled and would ship — dead weight at best, and at worst a network this
# project has no licence to distribute. The runtime would not complain, because
# the bridge prefers the pinned basename. So this asserts the Windows packaging
# build's rule on the app's own resources: exactly the two pinned networks, one
# for each game the core can search, and anything else stops the build and says
# which.
mini_variant_id=$(plutil -extract variant.id raw -o - "$root/pinned-inputs.json")
mini_nnue_name=$(plutil -extract "network.$mini_variant_id.filename" raw -o - "$root/pinned-inputs.json")
xiangqi_nnue_name=$(plutil -extract network.xiangqi.filename raw -o - "$root/pinned-inputs.json")

if [ "$mini_nnue_name" = "$xiangqi_nnue_name" ]; then
  echo "error: pinned-inputs.json gives both games the same bundled network name, $mini_nnue_name." >&2
  exit 1
fi

network_count=0
found_mini=0
found_xiangqi=0
unexpected_networks=""
for network in "$resources"/*.nnue; do
  [ -e "$network" ] || continue
  network_count=$((network_count + 1))
  staged_name=$(basename "$network")
  case "$staged_name" in
    "$mini_nnue_name") found_mini=1 ;;
    "$xiangqi_nnue_name") found_xiangqi=1 ;;
    *) unexpected_networks="$unexpected_networks $staged_name" ;;
  esac
done
unexpected_networks=${unexpected_networks# }

if [ "$network_count" -eq 0 ]; then
  echo "error: the bundled NNUE networks $mini_nnue_name and $xiangqi_nnue_name have not been staged." >&2
  echo "note: run ./apple/build-core-xcframework.sh, which verifies them against pinned-inputs.json and stages them from core/assets." >&2
  exit 1
fi
if [ "$network_count" -ne 2 ] || [ "$found_mini" -ne 1 ] || [ "$found_xiangqi" -ne 1 ]; then
  echo "error: the app must bundle exactly $mini_nnue_name and $xiangqi_nnue_name; found $network_count NNUE file(s)." >&2
  if [ -n "$unexpected_networks" ]; then
    echo "error: unexpected bundled NNUE network(s): $unexpected_networks" >&2
  fi
  echo "note: run ./apple/build-core-xcframework.sh, which removes unexpected networks before staging both pinned ones." >&2
  exit 1
fi

verify_staged_network() {
  verify_variant=$1
  verify_name=$2
  verify_path="$resources/$verify_name"
  verify_length=$(plutil -extract "network.$verify_variant.byte_length" raw -o - \
                          "$root/pinned-inputs.json")
  verify_sha256=$(plutil -extract "network.$verify_variant.sha256" raw -o - \
                          "$root/pinned-inputs.json")

  actual_length=$(wc -c < "$verify_path" | tr -d ' ')
  if [ "$actual_length" != "$verify_length" ]; then
    echo "error: the bundled network $verify_name is $actual_length bytes; pinned-inputs.json pins $verify_length." >&2
    echo "note: run ./apple/build-core-xcframework.sh, then build again." >&2
    exit 1
  fi
  actual_sha256=$(shasum -a 256 "$verify_path" | cut -d' ' -f1)
  if [ "$actual_sha256" != "$verify_sha256" ]; then
    echo "error: the bundled network $verify_name does not match the SHA-256 pinned-inputs.json pins." >&2
    echo "note: run ./apple/build-core-xcframework.sh, then build again." >&2
    exit 1
  fi
}

verify_staged_network "$mini_variant_id" "$mini_nnue_name"
verify_staged_network xiangqi "$xiangqi_nnue_name"
