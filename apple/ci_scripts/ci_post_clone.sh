#!/bin/sh
# Xcode Cloud post-clone: make the fresh clone buildable, and give a tag-started
# build the version its tag names.
#
# A fresh clone carries neither apple/Generated/ nor apple/MiniXiangqi/Resources/
# — both are generated, and the "Check the shared core is current" build phase
# refuses to build without them — so this runs the same generator a developer
# runs. The generator needs CMake and Ninja, which the Xcode Cloud image does
# not carry; it does carry Homebrew. DEVELOPER_DIR is not set here: Xcode Cloud
# points it at the workflow's chosen Xcode, and the generator honours an
# existing value.
#
# A build started by a release tag ships the version the tag names — v2.5.0
# ships 2.5.0 — so cutting a release is pushing one tag, with no version-bump
# commit. A build started any other way (manual, branch) skips the stamping and
# ships whatever the project file says. The build number is Xcode Cloud's own
# and is not touched here.

set -eu

repo="${CI_PRIMARY_REPOSITORY_PATH:-$(cd "$(dirname "$0")/../.." && pwd)}"

# Skipping Homebrew's index refresh: both formulae are years old, and the
# refresh costs more time than the installs.
export HOMEBREW_NO_AUTO_UPDATE=1
for tool in cmake ninja; do
  command -v "$tool" >/dev/null 2>&1 || brew install "$tool"
done

if [ -n "${CI_TAG:-}" ]; then
  version=${CI_TAG#v}
  if ! printf '%s' "$version" | grep -Eq '^[0-9]+(\.[0-9]+){1,2}$'; then
    echo "error: tag '$CI_TAG' does not name a version; release tags are v<major>.<minor>[.<patch>]." >&2
    exit 1
  fi
  # sed rather than agvtool: agvtool leaves MARKETING_VERSION in the project
  # file alone and instead writes CFBundleShortVersionString into the physical
  # Info.plist — a key this project keeps out of it, because versioning lives
  # in the generated plist. Every target takes the tag's version; only the app
  # is archived, and the checkout is this build's own.
  pbxproj="$repo/apple/MiniXiangqi.xcodeproj/project.pbxproj"
  sed -i '' -E "s/MARKETING_VERSION = [^;]*;/MARKETING_VERSION = $version;/g" "$pbxproj"
  grep -q "MARKETING_VERSION = $version;" "$pbxproj" || {
    echo "error: stamping MARKETING_VERSION $version into project.pbxproj took no effect." >&2
    exit 1
  }
  echo "MARKETING_VERSION set to $version from tag $CI_TAG"
fi

"$repo/apple/build-core-xcframework.sh"
