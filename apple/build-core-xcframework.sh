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
# The core is three static libraries — the facade, the vendored engine and the
# vendored SQLite — and an XCFramework carries one, so they are combined per
# architecture with libtool and then joined across architectures with lipo,
# rather than left for every consumer to link in the right order.
build_platform() {
  sdk=$1
  system=$2
  architectures=$3

  slices=""
  for arch in $architectures; do
    build="$staging/$sdk-$arch"
    set -- -S "$root/core" -B "$build" -G Ninja \
           -DMXQ_ENABLE_RULES_FACADE=ON \
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
            "$build/third_party/fairy-stockfish/libmxqfairystockfish.a" \
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
# every run is the one that keeps the path stable.
slice=$(cd "$output" && ls -d macos-* | head -1)
ln -sfn "MiniXiangqiCore.xcframework/$slice/Headers" "$(dirname "$output")/CoreHeaders"

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

echo "built $output"
lipo -info "$output"/*/libMiniXiangqiCore.a
