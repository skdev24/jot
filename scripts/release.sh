#!/usr/bin/env bash
# Signed, notarized, stapled universal release of Jot.
#
#   scripts/release.sh [--dmg] [--skip-notarize] [--unsigned]
#
# Out (build/dist/): Jot.app, Jot-<v>.zip, [Jot-<v>.dmg], [appcast.xml], SHA256SUMS
#
# Required (signed):
#   DEVELOPER_ID_APPLICATION   "Developer ID Application: Name (TEAMID)" or its SHA-1
#   NOTARY_PROFILE             notarytool keychain profile, or all of:
#   APPLE_API_KEY_ID / APPLE_API_ISSUER / APPLE_API_KEY_PATH (.p8)
# Optional:
#   NOTARY_KEYCHAIN            keychain holding NOTARY_PROFILE
#   JOT_ENTITLEMENTS           entitlements plist for the app (default: reuse build's)
#   SPARKLE_PRIVATE_KEY        EdDSA private key (base64, from generate_keys -x)
#   SPARKLE_KEY_FILE           ...or a file containing it
#   SPARKLE_KEYCHAIN=1         ...or use the key generate_keys stored in the login keychain
#   SPARKLE_BIN                dir with sign_update / generate_appcast
#   JOT_REPO                   owner/repo for appcast URLs (default: GITHUB_REPOSITORY, then origin)
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

die()  { echo "error: $*" >&2; exit 1; }
warn() { echo "warning: $*" >&2; }
step() { echo; echo "==> $*"; }

usage() { awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; }

unsigned=0 dmg=0 notarize=1
while (($#)); do
  case "$1" in
    --unsigned)      unsigned=1 ;;
    --dmg)           dmg=1 ;;
    --skip-notarize) notarize=0 ;;
    -h|--help)       usage; exit 0 ;;
    *)               usage >&2; die "unknown option: $1" ;;
  esac
  shift
done

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Jot/Info.plist)"
build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Jot/Info.plist)"
out="${root}/build/dist"
zip="${out}/Jot-${version}.zip"
dmg_path="${out}/Jot-${version}.dmg"
work="${root}/build/release"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# --- helpers -----------------------------------------------------------------

sha() { shasum -a 256 "$1" | awk '{print $1}'; }

gh_output() { [[ -n "${GITHUB_OUTPUT:-}" ]] && echo "$1=$2" >> "$GITHUB_OUTPUT"; return 0; }

# owner/repo for download URLs.
repo_slug() {
  if [[ -n "${JOT_REPO:-}" ]]; then echo "$JOT_REPO"; return; fi
  if [[ -n "${GITHUB_REPOSITORY:-}" ]]; then echo "$GITHUB_REPOSITORY"; return; fi
  local url
  url="$(git remote get-url origin 2>/dev/null || true)"
  url="${url%.git}"
  case "$url" in
    *github.com[:/]*) echo "${url##*github.com[:/]}" ;;
  esac
}

# Locate a Sparkle CLI tool: SPARKLE_BIN, PATH, then SPM artifacts.
sparkle_tool() {
  local name="$1" dir
  for dir in "${SPARKLE_BIN:-}" \
             "${work}/derived/SourcePackages/artifacts/sparkle/Sparkle/bin" \
             "${root}/build/derived/SourcePackages/artifacts/sparkle/Sparkle/bin"; do
    [[ -n "$dir" && -x "${dir}/${name}" ]] && { echo "${dir}/${name}"; return; }
  done
  command -v "$name" 2>/dev/null || true
}

# Sparkle key source -> sparkle_key_args (empty array = keychain).
sparkle_enabled=0
sparkle_key_args=()
setup_sparkle_key() {
  if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
    local f="${tmp}/sparkle_ed25519"
    (umask 077; printf '%s\n' "$SPARKLE_PRIVATE_KEY" > "$f")
    sparkle_key_args=(--ed-key-file "$f")
  elif [[ -n "${SPARKLE_KEY_FILE:-}" ]]; then
    [[ -r "$SPARKLE_KEY_FILE" ]] || die "SPARKLE_KEY_FILE not readable: $SPARKLE_KEY_FILE"
    sparkle_key_args=(--ed-key-file "$SPARKLE_KEY_FILE")
  elif [[ "${SPARKLE_KEYCHAIN:-}" == 1 ]]; then
    sparkle_key_args=()
  else
    return 0
  fi
  sparkle_enabled=1
}

write_sums() {
  step "SHA-256"
  (cd "$out" && shasum -a 256 "$(basename "$zip")" ${dmg_name:+"$dmg_name"}) | tee "${out}/SHA256SUMS"
  gh_output version "$version"
  gh_output zip "$zip"
  gh_output zip_sha256 "$(sha "$zip")"
  if [[ -n "${dmg_name:-}" ]]; then
    gh_output dmg "$dmg_path"
    gh_output dmg_sha256 "$(sha "$dmg_path")"
  fi
}

print_cask() {
  cat <<EOF

Cask (packaging/homebrew/jot.rb):
  version "${version}"
  sha256 "$(sha "$zip")"
EOF
}

# --- unsigned fallback ------------------------------------------------------

if ((unsigned)); then
  step "Unsigned build (ad-hoc) via package.sh"
  "${root}/scripts/package.sh"
  dmg_name=""
  write_sums
  gh_output signed false
  # Never feed an ad-hoc build to Sparkle: it would fail team-ID validation.
  echo "note: unsigned build; no appcast generated."
  print_cask
  exit 0
fi

# --- preflight: fail before a long build ------------------------------------

step "Preflight"
missing=()
[[ -n "${DEVELOPER_ID_APPLICATION:-}" ]] || missing+=("DEVELOPER_ID_APPLICATION")

notary_args=()
if ((notarize)); then
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    notary_args=(--keychain-profile "$NOTARY_PROFILE")
    [[ -n "${NOTARY_KEYCHAIN:-}" ]] && notary_args+=(--keychain "$NOTARY_KEYCHAIN")
  elif [[ -n "${APPLE_API_KEY_ID:-}${APPLE_API_ISSUER:-}${APPLE_API_KEY_PATH:-}" ]]; then
    [[ -n "${APPLE_API_KEY_ID:-}" ]]   || missing+=("APPLE_API_KEY_ID")
    [[ -n "${APPLE_API_ISSUER:-}" ]]   || missing+=("APPLE_API_ISSUER")
    [[ -n "${APPLE_API_KEY_PATH:-}" ]] || missing+=("APPLE_API_KEY_PATH")
    if [[ -n "${APPLE_API_KEY_PATH:-}" && ! -r "${APPLE_API_KEY_PATH}" ]]; then
      die "APPLE_API_KEY_PATH not readable: ${APPLE_API_KEY_PATH}"
    fi
    notary_args=(--key "${APPLE_API_KEY_PATH:-}" --key-id "${APPLE_API_KEY_ID:-}" --issuer "${APPLE_API_ISSUER:-}")
  else
    missing+=("NOTARY_PROFILE (or APPLE_API_KEY_ID + APPLE_API_ISSUER + APPLE_API_KEY_PATH)")
  fi
fi

if ((${#missing[@]})); then
  printf 'error: missing required env:\n' >&2
  printf '  - %s\n' "${missing[@]}" >&2
  die "set them (see docs/RELEASING.md), or run with --unsigned"
fi

security find-identity -v -p codesigning | grep -qF -- "$DEVELOPER_ID_APPLICATION" \
  || die "signing identity not in keychain: ${DEVELOPER_ID_APPLICATION}"

if [[ -n "${JOT_ENTITLEMENTS:-}" && ! -r "$JOT_ENTITLEMENTS" ]]; then
  die "JOT_ENTITLEMENTS not readable: ${JOT_ENTITLEMENTS}"
fi

setup_sparkle_key
slug="$(repo_slug)"
if ((sparkle_enabled)); then
  [[ -n "$slug" ]] || die "Sparkle key given but repo unknown (set JOT_REPO=owner/repo)"
  ((notarize)) || warn "--skip-notarize: appcast will be skipped"
else
  warn "no Sparkle key (SPARKLE_PRIVATE_KEY / SPARKLE_KEY_FILE / SPARKLE_KEYCHAIN=1): no appcast"
fi

echo "Jot ${version} (${build_number})"
echo "identity: ${DEVELOPER_ID_APPLICATION}"
((notarize)) || warn "--skip-notarize: output will NOT pass Gatekeeper"

# --- build ------------------------------------------------------------------

step "Build (universal Release)"
rm -rf "$work"
mkdir -p "$work" "$out"

# Ad-hoc first so Xcode embeds entitlements; we re-sign inside-out below.
xcodebuild \
  -project Jot.xcodeproj \
  -scheme Jot \
  -configuration Release \
  -derivedDataPath "${work}/derived" \
  -destination 'generic/platform=macOS' \
  ARCHS='arm64 x86_64' \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY='-' \
  CODE_SIGNING_REQUIRED=NO \
  build

built="${work}/derived/Build/Products/Release/Jot.app"
[[ -d "$built" ]] || die "build produced no app at ${built}"

app="${out}/Jot.app"
rm -rf "$app"
ditto "$built" "$app"

lipo -archs "${app}/Contents/MacOS/Jot" | grep -q arm64  || die "app is missing arm64"
lipo -archs "${app}/Contents/MacOS/Jot" | grep -q x86_64 || die "app is missing x86_64"

# --- sign (inside-out, no --deep) --------------------------------------------

step "Codesign"

sign() { codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$@"; }

# App entitlements: explicit file, else what the build embedded.
ents="${tmp}/Jot.entitlements"
if [[ -n "${JOT_ENTITLEMENTS:-}" ]]; then
  cp "$JOT_ENTITLEMENTS" "$ents"
else
  codesign -d --entitlements - --xml "$app" > "$ents" 2>/dev/null || true
fi
if [[ -s "$ents" ]]; then
  # Debug-only entitlement; notarization rejects it.
  /usr/libexec/PlistBuddy -c 'Delete :com.apple.security.get-task-allow' "$ents" >/dev/null 2>&1 || true
else
  rm -f "$ents"
fi

# Sparkle 2: XPC services, Autoupdate, Updater.app, then the framework.
sparkle="${app}/Contents/Frameworks/Sparkle.framework"
if [[ -d "$sparkle" ]]; then
  sv="${sparkle}/Versions/B"
  [[ -d "${sv}/XPCServices/Installer.xpc" ]]  && sign "${sv}/XPCServices/Installer.xpc"
  [[ -d "${sv}/XPCServices/Downloader.xpc" ]] && sign --preserve-metadata=entitlements "${sv}/XPCServices/Downloader.xpc"
  [[ -e "${sv}/Autoupdate" ]]                 && sign "${sv}/Autoupdate"
  [[ -d "${sv}/Updater.app" ]]                && sign "${sv}/Updater.app"
  sign "$sparkle"
else
  warn "Sparkle.framework not embedded; skipping its nested signing"
fi

# Any other embedded frameworks / dylibs / helpers.
if [[ -d "${app}/Contents/Frameworks" ]]; then
  while IFS= read -r -d '' item; do
    [[ "$item" == "$sparkle" ]] && continue
    sign "$item"
  done < <(find "${app}/Contents/Frameworks" -mindepth 1 -maxdepth 1 \
             \( -name '*.framework' -o -name '*.dylib' -o -name '*.app' -o -name '*.xpc' \) -print0)
fi
for dir in "${app}/Contents/XPCServices" "${app}/Contents/Helpers" "${app}/Contents/Library/LoginItems"; do
  [[ -d "$dir" ]] || continue
  while IFS= read -r -d '' item; do sign "$item"; done \
    < <(find "$dir" -mindepth 1 -maxdepth 1 -print0)
done

# The app last.
if [[ -f "$ents" ]]; then
  sign --entitlements "$ents" "$app"
else
  sign "$app"
fi

codesign --verify --deep --strict --verbose=2 "$app"
codesign -dv --verbose=2 "$app" 2>&1 | grep -E '^(Authority|TeamIdentifier|Timestamp|Runtime)' || true

# --- notarize + staple -------------------------------------------------------

# notarize <file>: submit, wait, fail with the log on rejection.
notarize_file() {
  local file="$1" json="${tmp}/notary.json" status id
  echo "submitting $(basename "$file")..."
  xcrun notarytool submit "$file" "${notary_args[@]}" --wait --output-format json > "$json" \
    || { cat "$json" >&2; die "notarytool submit failed"; }
  status="$(plutil -extract status raw -o - "$json" 2>/dev/null || echo unknown)"
  id="$(plutil -extract id raw -o - "$json" 2>/dev/null || echo '')"
  echo "notary: ${status} (${id})"
  if [[ "$status" != "Accepted" ]]; then
    [[ -n "$id" ]] && xcrun notarytool log "$id" "${notary_args[@]}" >&2 || true
    die "notarization ${status} for $(basename "$file")"
  fi
}

if ((notarize)); then
  step "Notarize app"
  ditto -c -k --keepParent "$app" "${tmp}/Jot-notarize.zip"
  notarize_file "${tmp}/Jot-notarize.zip"
  xcrun stapler staple "$app"
  xcrun stapler validate "$app"
  spctl --assess --type execute -vv "$app"
fi

# --- package -----------------------------------------------------------------

step "Zip"
rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"
echo "$zip"

dmg_name=""
if ((dmg)); then
  step "DMG"
  stage="${tmp}/dmg"
  mkdir -p "$stage"
  ditto "$app" "${stage}/Jot.app"
  ln -s /Applications "${stage}/Applications"
  rm -f "$dmg_path"
  hdiutil create -volname "Jot" -srcfolder "$stage" -ov -format UDZO "$dmg_path"
  codesign --force --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$dmg_path"
  if ((notarize)); then
    notarize_file "$dmg_path"
    xcrun stapler staple "$dmg_path"
    xcrun stapler validate "$dmg_path"
  fi
  dmg_name="$(basename "$dmg_path")"
  echo "$dmg_path"
fi

write_sums
gh_output signed true
gh_output notarized "$( ((notarize)) && echo true || echo false )"

# --- Sparkle -----------------------------------------------------------------

if ((sparkle_enabled && notarize)); then
  step "Sparkle"
  sign_update="$(sparkle_tool sign_update)"
  generate_appcast="$(sparkle_tool generate_appcast)"
  [[ -n "$sign_update" && -n "$generate_appcast" ]] \
    || die "sign_update/generate_appcast not found (set SPARKLE_BIN to Sparkle's bin/)"

  # EdDSA signature, for the log.
  "$sign_update" ${sparkle_key_args[@]+"${sparkle_key_args[@]}"} "$zip"

  # One-archive feed: served from releases/latest/download/appcast.xml.
  feed="${tmp}/feed"
  mkdir -p "$feed"
  cp "$zip" "$feed/"
  "$generate_appcast" \
    ${sparkle_key_args[@]+"${sparkle_key_args[@]}"} \
    --download-url-prefix "https://github.com/${slug}/releases/download/v${version}/" \
    --link "https://github.com/${slug}" \
    -o "${out}/appcast.xml" \
    "$feed"
  grep -q 'sparkle:edSignature' "${out}/appcast.xml" || die "appcast.xml has no EdDSA signature"
  gh_output appcast "${out}/appcast.xml"
  echo "${out}/appcast.xml"
fi

print_cask
echo
echo "Done: Jot ${version} (${build_number})"
