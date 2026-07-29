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
# Two architectures. macOS on Apple silicon runs arm64e, and the app is built
# for it; arm64 is carried alongside so the same framework serves a plain arm64
# build — the command-line test runner, an Intel-free arm64 host, or a CI
# machine — without a second package. They are built separately and joined with
# lipo, because the vendored engine selects its instruction-set defines per
# architecture and its build refuses to produce both in one pass.
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

architectures="arm64 arm64e"
deployment_target=26.5

for arch in $architectures; do
  build="$staging/macosx-$arch"
  cmake -S "$root/core" -B "$build" -G Ninja \
        -DMXQ_ENABLE_RULES_FACADE=ON \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_OSX_SYSROOT=macosx \
        -DCMAKE_OSX_ARCHITECTURES="$arch" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="$deployment_target" \
        >/dev/null
  cmake --build "$build" --target mxq_core
done

# One library per architecture, then one universal library. The core is three
# static libraries — the facade, the vendored engine, and the vendored SQLite —
# and an XCFramework carries one, so they are combined here rather than left
# for every consumer to link in the right order.
merge_slice() {
  arch=$1
  build="$staging/macosx-$arch"
  merged="$staging/libMiniXiangqiCore-$arch.a"
  rm -f "$merged"
  libtool -static -no_warning_for_no_symbols -o "$merged" \
          "$build/libmxqcore.a" \
          "$build/third_party/fairy-stockfish/libmxqfairystockfish.a" \
          "$build/third_party/sqlite/libmxqsqlite.a"
  echo "$merged"
}

slices=""
for arch in $architectures; do
  slices="$slices $(merge_slice "$arch")"
done

universal="$staging/libMiniXiangqiCore.a"
rm -f "$universal"
# shellcheck disable=SC2086
lipo -create $slices -output "$universal"

# The headers the XCFramework publishes: the repository's single public C
# surface, and the module map that makes it importable from Swift.
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
           -library "$universal" -headers "$headers" \
           -output "$output" >/dev/null

# A stable path to the published headers, for targets that compile against the
# core's module without linking it — the unit tests, which resolve every symbol
# through their host application. The slice directory inside an XCFramework is
# named after the architectures it carries, so nothing outside this script
# should have to spell it.
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
