#!/usr/bin/env bash
# Local unsigned (ad-hoc) universal Release build.
# Out: build/dist/Jot.app, build/dist/Jot-<version>.zip
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Jot/Info.plist)"
derived="${root}/build/derived"
out="${root}/build/dist"
app="${derived}/Build/Products/Release/Jot.app"
zip="${out}/Jot-${version}.zip"

rm -rf "$derived"
mkdir -p "$out"

# Universal, ad-hoc signed.
xcodebuild \
  -project Jot.xcodeproj \
  -scheme Jot \
  -configuration Release \
  -derivedDataPath "$derived" \
  -destination 'generic/platform=macOS' \
  ARCHS='arm64 x86_64' \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY='-' \
  CODE_SIGNING_REQUIRED=NO \
  build

[[ -d "$app" ]] || { echo "error: build produced no app at ${app}" >&2; exit 1; }

rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"

rm -rf "${out}/Jot.app"
ditto "$app" "${out}/Jot.app"

echo "Packed ${zip}"
echo "App     ${out}/Jot.app"
