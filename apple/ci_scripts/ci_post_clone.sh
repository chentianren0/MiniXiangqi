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
pbxproj="$repo/apple/MiniXiangqi.xcodeproj/project.pbxproj"

# Skipping Homebrew's index refresh: both formulae are years old, and the
# refresh costs more time than the installs.
export HOMEBREW_NO_AUTO_UPDATE=1
for tool in cmake ninja; do
  command -v "$tool" >/dev/null 2>&1 || brew install "$tool"
done

# Only a cloud checkout is edited below: run by hand, the same command would
# rewrite the developer's own working tree.
if [ -n "${CI_XCODE_CLOUD:-}" ]; then
  # The project pins expectedSignature on the prebuilt framework whenever the
  # owner's Xcode links a locally signed copy, and re-records the pin on any
  # project rewrite — Xcode-owned state the repository cannot shed. This
  # machine rebuilds that framework from source with no signing identity, and
  # ProcessXCFramework refuses an unsigned artifact against a recorded pin.
  # What the framework is built FROM is already verified by the generator
  # against pinned-inputs.json, which is the stronger claim, so the pin comes
  # out of this build's own checkout.
  sed -i '' -E 's/expectedSignature = "[^"]*"; //g' "$pbxproj"
  if grep -q "expectedSignature" "$pbxproj"; then
    echo "error: an expectedSignature pin survived removal from project.pbxproj; this unsigned CI-built framework would be refused." >&2
    exit 1
  fi
fi

if [ -n "${CI_TAG:-}" ]; then
  if ! printf '%s' "$CI_TAG" | grep -Eq '^v(0|[1-9][0-9]*)(\.(0|[1-9][0-9]*)){1,2}$'; then
    echo "error: tag '$CI_TAG' does not name a version; release tags are v<major>.<minor>[.<patch>], no leading zeros." >&2
    exit 1
  fi
  version=${CI_TAG#v}
  # sed rather than agvtool: agvtool leaves MARKETING_VERSION in the project
  # file alone and instead writes CFBundleShortVersionString into the physical
  # Info.plist — a key this project keeps out of it, because versioning lives
  # in the generated plist. Every target takes the tag's version; only the app
  # is archived, and the checkout is this build's own.
  sed -i '' -E "s/MARKETING_VERSION = [^;]*;/MARKETING_VERSION = $version;/g" "$pbxproj"
  grep -Fq "MARKETING_VERSION = $version;" "$pbxproj" || {
    echo "error: stamping MARKETING_VERSION $version into project.pbxproj took no effect." >&2
    exit 1
  }
  echo "MARKETING_VERSION set to $version from tag $CI_TAG"
fi

"$repo/apple/build-core-xcframework.sh"
