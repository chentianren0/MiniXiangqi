#!/bin/sh
# Build the shared core and package it as MiniXiangqiCore.xcframework.
#
# The Xcode project consumes the core as an XCFramework rather than as loose
# static libraries and search paths, so that the app links a real dependency
# with its own headers and module map: Xcode selects the platform slice, and
# nothing in the app's build settings has to name a path inside the core's build
# directory.
#
#   ./apple/build-core-xcframework.sh
#
# Three library sets, because the app has three destinations and an XCFramework
# carries one library per platform:
#
#   macOS          arm64 + arm64e
#   iOS device     arm64 + arm64e
#   iOS Simulator  arm64
#
# Both hardware platforms carry both architectures. Apple silicon runs arm64e
# and the app is built for it; arm64 is carried alongside so the same framework
# serves a plain arm64 build — the command-line test runner, an Intel-free arm64
# host, a CI machine — without a second package. The Simulator is not hardware
# and has no arm64e, so it carries the one architecture it can run.
#
# Every architecture is configured and compiled separately and the results are
# joined with lipo, because the vendored engine selects its instruction-set
# defines per architecture and its build refuses to produce two in one pass.
#
# Everything this writes is generated and ignored by git.

set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
staging="$root/core/.build-apple"
output="$root/apple/Generated/MiniXiangqiCore.xcframework"

: "${DEVELOPER_DIR:=/Applications/Xcode-beta.app/Contents/Developer}"
export DEVELOPER_DIR

# Xcode runs a build phase with its own PATH, which carries neither CMake nor
# Ninja, so the tools are resolved rather than assumed. A missing one is
# reported here, where it says what to install, instead of as "command not
# found" inside a build log.
PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"
export PATH
for tool in cmake ninja; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "error: $tool is required to build the shared core; install it with: brew install $tool" >&2
    exit 1
  }
done

# One deployment target for all three, because the project sets one: both
# MACOSX_DEPLOYMENT_TARGET and IPHONEOS_DEPLOYMENT_TARGET in
# apple/MiniXiangqi.xcodeproj are 26.5. A core built for a newer system than the
# app targets is what the linker warns about, so this follows the project rather
# than leading it.
deployment_target=26.5

# Configure, compile and merge one platform's library.
#
#   build_platform <sdk> <CMake system name, empty for the host> <architectures>
#
# The system name is what turns a build into a cross build: empty for macOS,
# which is the machine this runs on, and iOS for the two that are not — the
# Simulator included, since a simulator binary is an iOS binary built against
# another SDK rather than a macOS one.
#
# The core is seven static libraries — the facade, its jieqi bridge, the three
# vendored engines, the lz4 the second engine decompresses its weights with, and
# the vendored SQLite — and an XCFramework carries one, so they are combined per
# architecture with libtool and then joined across architectures with lipo,
# rather than left for every consumer to link in the right order.
#
# The bridge is a library of its own rather than part of the facade because the
# jieqi slice's namespace rename is a compile definition that must reach exactly
# one translation unit; core/CMakeLists.txt carries the reasoning. It is listed
# here for the plain reason that the app links what this script packages: a
# framework without it resolves nothing the facade asks of the jieqi engine.
build_platform() {
  sdk=$1
  system=$2
  architectures=$3

  slices=""
  for arch in $architectures; do
    build="$staging/$sdk-$arch"
    set -- -S "$root/core" -B "$build" -G Ninja \
           -DMXQ_ENABLE_RULES_FACADE=ON \
           -DMXQ_ENABLE_GOMOKU_FACADE=ON \
           -DCMAKE_BUILD_TYPE=Release \
           -DCMAKE_OSX_SYSROOT="$sdk" \
           -DCMAKE_OSX_ARCHITECTURES="$arch" \
           -DCMAKE_OSX_DEPLOYMENT_TARGET="$deployment_target"
    if [ -n "$system" ]; then
      set -- "$@" "-DCMAKE_SYSTEM_NAME=$system"
    fi
    cmake "$@" >/dev/null
    cmake --build "$build" --target mxq_core

    slice="$staging/libMiniXiangqiCore-$sdk-$arch.a"
    rm -f "$slice"
    libtool -static -no_warning_for_no_symbols -o "$slice" \
            "$build/libmxqcore.a" \
            "$build/libmxqjieqibridge.a" \
            "$build/third_party/fairy-stockfish/libmxqfairystockfish.a" \
            "$build/third_party/rapfi/libmxqrapfi.a" \
            "$build/third_party/rapfi/libmxqrapfilz4.a" \
            "$build/third_party/pikafish/libmxqpikafish.a" \
            "$build/third_party/sqlite/libmxqsqlite.a"
    slices="$slices $slice"
  done

  # lipo even for the single-architecture Simulator library, so that every
  # platform's library has the same shape and nothing downstream has to care
  # how many architectures went into it.
  #
  # One directory per platform, and the same file name in each: -create-xcframework
  # copies each library in under the name it was given, so the name here is the
  # name inside every slice. check-core-is-current.sh looks for exactly this one.
  library="$staging/$sdk/libMiniXiangqiCore.a"
  mkdir -p "$(dirname "$library")"
  rm -f "$library"
  # shellcheck disable=SC2086
  lipo -create $slices -output "$library"
}

build_platform macosx          ""  "arm64 arm64e"
build_platform iphoneos        iOS "arm64 arm64e"
build_platform iphonesimulator iOS "arm64"

# The headers the XCFramework publishes: the repository's single public C
# surface, and the module map that makes it importable from Swift. One copy,
# published with each library — mxq.h is platform-independent, and a per-slice
# header set would be three copies of one file.
headers="$staging/Headers"
rm -rf "$headers"
mkdir -p "$headers"
cp "$root/core/include/mxq.h" "$headers/"
cat > "$headers/module.modulemap" <<'MODULEMAP'
module MiniXiangqiCore {
    header "mxq.h"
    export *
}
MODULEMAP

# Repackaging every time, deliberately. The expensive part is the compile, and
# CMake already makes that incremental; packaging an existing library takes a
# moment. An earlier attempt to skip this step compared the freshly built
# library against the packaged one, which never matched — `libtool -static` is
# not byte-deterministic — so the skip was dead code that would have skipped
# staging the app's resources as well had it ever fired.
rm -rf "$output"
mkdir -p "$(dirname "$output")"
xcodebuild -create-xcframework \
           -library "$staging/macosx/libMiniXiangqiCore.a" -headers "$headers" \
           -library "$staging/iphoneos/libMiniXiangqiCore.a" -headers "$headers" \
           -library "$staging/iphonesimulator/libMiniXiangqiCore.a" -headers "$headers" \
           -output "$output" >/dev/null

# Signed if this machine can sign, and never failing if it cannot. Xcode
# validates the frameworks a project links and stops with a trust prompt at an
# unsigned one; a locally built artifact that carries this machine's development
# signature is accepted without the prompt. A machine with no identity — CI, a
# fresh checkout — still gets a working framework, and the prompt is the price.
#
# --timestamp=none: a development signature does not need Apple's timestamp
# server, and asking for it makes the build depend on the network.
identity=$(security find-identity -v -p codesigning 2>/dev/null \
             | sed -n 's/.*"\(Apple Development[^"]*\)".*/\1/p' | head -1)
if [ -n "$identity" ]; then
  if codesign --timestamp=none --sign "$identity" "$output"; then
    echo "signed $output as $identity"
  else
    echo "note: signing failed; Xcode will ask you to trust the unsigned framework." >&2
  fi
else
  echo "note: no Apple Development identity on this machine, so the framework is unsigned; Xcode's Accept Unsigned is expected for a locally built artifact."
fi

# A stable path to the published headers, for targets that compile against the
# core's module without linking it — the unit tests, which resolve every symbol
# through their host application. The slice directory inside an XCFramework is
# named after the platform and architectures it carries, so nothing outside this
# script should have to spell it. The macOS slice, deterministically: the
# headers are one file per slice and identical across all three, so which slice
# publishes the path is arbitrary, and an arbitrary choice made the same way
# every run is the one that keeps the path stable. A real copy, not a symlink:
# the Generated directory is seeded into agent worktrees by copying machinery
# that need not preserve links, and every artifact here must survive that copy.
slice=$(cd "$output" && ls -d macos-* | head -1)
headers_published="$(dirname "$output")/CoreHeaders"
rm -rf "$headers_published"
cp -R "$output/$slice/Headers" "$headers_published"

# A fingerprint of the sources this framework was built from, so the app can
# tell whether it is current. Content, not timestamps: a git checkout of
# another branch rewinds mtimes, and a check that trusted them would call a
# stale core fresh — which is the one failure this whole arrangement exists to
# prevent.
"$root/apple/core-inputs-digest.sh" > "$(dirname "$output")/core-inputs.digest"

# The bundled variant configuration the engine loads at initialisation. It is
# an app resource, staged from the one copy in core/assets that the test runner
# and the Windows frontend also read; a second committed copy would drift.
resources="$root/apple/MiniXiangqi/Resources"
mkdir -p "$resources"
cp "$root/core/assets/minixiangqi-variants.ini" "$resources/"

# The bundled NNUE networks, staged the same way and under the same policy the
# core's CMake staging enforces: nothing is consumed on trust.
#
# They come from core/assets, beside the variant configuration they are loaded
# with, under the names they are bundled as — each has to begin with its variant
# identifier, because the engine restricts NNUE to the matching variant by that
# basename and a name that does not match disables NNUE *silently* while the Use
# NNUE option still reads true. MXQ_NNUE_SOURCE and MXQ_XIANGQI_NNUE_SOURCE
# override the respective paths, which is how candidate networks are tried
# before they are committed; nothing has to set either for an ordinary build.
#
# Absence or a mismatch stops here rather than producing an app whose AI is
# quietly a different opponent. It is worth verifying a version-controlled file:
# the check is what catches an override pointed at the wrong bytes, and a
# checkout that damaged the weights would otherwise be invisible.
# plutil reads the manifest because it is on every Mac and this script is
# Apple-only.
#
# The manifest pins one network per engine variant. Mini Xiangqi's key follows
# variant.id; Xiangqi's engine identifier is the manifest's xiangqi key.
mini_variant_id=$(plutil -extract variant.id raw -o - "$root/pinned-inputs.json")
mini_nnue_name=$(plutil -extract "network.$mini_variant_id.filename" raw -o - "$root/pinned-inputs.json")
mini_nnue_source="${MXQ_NNUE_SOURCE:-$root/core/assets/$mini_nnue_name}"
mini_nnue_length=$(plutil -extract "network.$mini_variant_id.byte_length" raw -o - "$root/pinned-inputs.json")
mini_nnue_sha256=$(plutil -extract "network.$mini_variant_id.sha256" raw -o - "$root/pinned-inputs.json")

xiangqi_variant_id=xiangqi
xiangqi_nnue_name=$(plutil -extract "network.$xiangqi_variant_id.filename" raw -o - "$root/pinned-inputs.json")
xiangqi_nnue_source="${MXQ_XIANGQI_NNUE_SOURCE:-$root/core/assets/$xiangqi_nnue_name}"
xiangqi_nnue_length=$(plutil -extract "network.$xiangqi_variant_id.byte_length" raw -o - "$root/pinned-inputs.json")
xiangqi_nnue_sha256=$(plutil -extract "network.$xiangqi_variant_id.sha256" raw -o - "$root/pinned-inputs.json")

if [ "$mini_nnue_name" = "$xiangqi_nnue_name" ]; then
  echo "error: pinned-inputs.json gives both games the same bundled network name, $mini_nnue_name." >&2
  exit 1
fi

verify_network() {
  verify_source=$1
  verify_name=$2
  verify_length=$3
  verify_sha256=$4
  verify_override=$5

  if [ ! -f "$verify_source" ]; then
    echo "error: the NNUE network $verify_name was not found at $verify_source" >&2
    echo "note: it belongs in core/assets under the name pinned-inputs.json pins, or point $verify_override at other bytes." >&2
    exit 1
  fi
  actual_length=$(wc -c < "$verify_source" | tr -d ' ')
  if [ "$actual_length" != "$verify_length" ]; then
    echo "error: the NNUE network at $verify_source is $actual_length bytes; pinned-inputs.json pins $verify_length." >&2
    exit 1
  fi
  actual_sha256=$(shasum -a 256 "$verify_source" | cut -d' ' -f1)
  if [ "$actual_sha256" != "$verify_sha256" ]; then
    echo "error: the NNUE network at $verify_source does not match the SHA-256 pinned-inputs.json pins." >&2
    exit 1
  fi
}

verify_network "$mini_nnue_source" "$mini_nnue_name" "$mini_nnue_length" \
               "$mini_nnue_sha256" MXQ_NNUE_SOURCE
verify_network "$xiangqi_nnue_source" "$xiangqi_nnue_name" "$xiangqi_nnue_length" \
               "$xiangqi_nnue_sha256" MXQ_XIANGQI_NNUE_SOURCE

# The second engine's weights, under exactly the same policy and verified the
# same way. They are keyed differently in the manifest because they are bound to
# a game differently: this engine reads the rule and the board size out of a
# file's own header rather than off its name, and it takes one file per SIDE, so
# gomoku_network is a map of games each holding a list of files with a role each.
# Freestyle has one file, which serves both sides; renju has one per side.
#
# There is no override variable for these. MXQ_NNUE_SOURCE exists because trying
# a candidate network before committing it is how this project's own network was
# replaced; nothing trains these, so nothing tries a candidate.
gomoku_weight_names=""
gomoku_weight_sources=""
for gomoku_entry in gomoku-15.0 renju.0 renju.1; do
  gomoku_game=${gomoku_entry%.*}
  gomoku_index=${gomoku_entry##*.}
  gomoku_key="gomoku_network.$gomoku_game.files.$gomoku_index"
  gomoku_name=$(plutil -extract "$gomoku_key.filename" raw -o - "$root/pinned-inputs.json")
  gomoku_length=$(plutil -extract "$gomoku_key.byte_length" raw -o - "$root/pinned-inputs.json")
  gomoku_sha256=$(plutil -extract "$gomoku_key.sha256" raw -o - "$root/pinned-inputs.json")
  gomoku_source="$root/core/assets/$gomoku_name"
  verify_network "$gomoku_source" "$gomoku_name" "$gomoku_length" \
                 "$gomoku_sha256" "(no override; $gomoku_key)"
  gomoku_weight_names="$gomoku_weight_names $gomoku_name"
  gomoku_weight_sources="$gomoku_weight_sources $gomoku_source"
done
gomoku_weight_names=${gomoku_weight_names# }
gomoku_weight_sources=${gomoku_weight_sources# }

# Exactly the pinned weight files end up in Resources, so anything else goes
# first.
#
# This matters the moment a bundled network's NAME changes, which it did when
# the project's own network replaced the community one. Copying the new name
# beside the old leaves an extra file, and apple/MiniXiangqi is a
# file-system-synchronized group: every one would be bundled into the .app and
# would ship. The runtime would not notice — each bridge asks for the pinned
# basenames — which is exactly why nothing else would catch it.
#
# Two sweeps because the two engines' weights have different extensions: the
# first engine's are .nnue, and the second's are LZ4 frames named .bin.lz4 as
# they are published. An unmatched glob expands to the pattern itself in a POSIX
# shell, so the existence test is what makes "none here" a no-op rather than an
# attempt to delete a file called *.nnue.
for stale in "$resources"/*.nnue; do
  [ -e "$stale" ] || continue
  staged_name=$(basename "$stale")
  case "$staged_name" in
    "$mini_nnue_name"|"$xiangqi_nnue_name") ;;
    *)
      rm -f "$stale"
      echo "removed a network that is no longer bundled: $staged_name"
      ;;
  esac
done
for stale in "$resources"/*.bin.lz4; do
  [ -e "$stale" ] || continue
  staged_name=$(basename "$stale")
  keep=0
  for expected in $gomoku_weight_names; do
    [ "$staged_name" = "$expected" ] && keep=1
  done
  if [ "$keep" -eq 0 ]; then
    rm -f "$stale"
    echo "removed a weight file that is no longer bundled: $staged_name"
  fi
done

cp "$mini_nnue_source" "$resources/$mini_nnue_name"
cp "$xiangqi_nnue_source" "$resources/$xiangqi_nnue_name"
echo "staged the pinned networks as $mini_nnue_name and $xiangqi_nnue_name"

for gomoku_source in $gomoku_weight_sources; do
  cp "$gomoku_source" "$resources/$(basename "$gomoku_source")"
done
echo "staged the pinned weight files: $gomoku_weight_names"

echo "built $output"
lipo -info "$output"/*/libMiniXiangqiCore.a
