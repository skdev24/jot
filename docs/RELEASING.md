# Releasing Jot

Releases are built by `.github/workflows/release.yml` when a `v*` tag is pushed. It runs
`scripts/release.sh`, which produces a universal, Developer ID–signed, hardened-runtime,
notarized and stapled `Jot.app`, then uploads these to the GitHub release:

| Asset | Purpose |
| --- | --- |
| `Jot-<version>.zip` | Download, Homebrew cask, and Sparkle update archive |
| `Jot-<version>.dmg` | Drag-to-Applications installer (notarized and stapled) |
| `appcast.xml` | Sparkle feed, EdDSA-signed |
| `SHA256SUMS` | Checksums |

If the signing secrets are missing (on a fork, for example), the workflow still publishes an
**unsigned** ad-hoc zip and says so in the release notes. Unsigned releases never get an appcast.

## One-time setup

### 1. Developer ID certificate

1. In the Apple Developer portal, create a **Developer ID Application** certificate (only the
   Account Holder can do this), then install it in your login keychain.
2. In Keychain Access > My Certificates, select *Developer ID Application: Name (TEAMID)*,
   including its private key, and export it as `.p12` with a strong password.
3. `base64 -i DeveloperID.p12 | pbcopy`, then paste the result as the `MACOS_CERTIFICATE` secret.

### 2. Notary credentials

Create an App Store Connect API key: App Store Connect > Users and Access > Integrations >
App Store Connect API > Team Keys, with the *Developer* role. Download `AuthKey_<KEYID>.p8`
(you can only download it once) and note the Key ID and the Issuer ID.

For local releases you can store a keychain profile instead:

```sh
xcrun notarytool store-credentials jot-notary \
  --key AuthKey_<KEYID>.p8 --key-id <KEYID> --issuer <ISSUER-UUID>
# or: --apple-id you@example.com --team-id TEAMID --password <app-specific-password>
```

### 3. Sparkle EdDSA key

Use the tools from the pinned Sparkle release (`SPARKLE_VERSION` in `release.yml`), or from
`<DerivedData>/SourcePackages/artifacts/sparkle/Sparkle/bin/` after an SPM resolve:

```sh
./bin/generate_keys            # creates the key in your login keychain, prints the public key
./bin/generate_keys -p         # prints the public key again
./bin/generate_keys -x sparkle_private_key   # exports the private key, for CI
```

- Put the **public** key in `Jot/Info.plist` as `SUPublicEDKey`. See [Info.plist keys](#infoplist-keys).
- Put the contents of `sparkle_private_key` in the `SPARKLE_PRIVATE_KEY` secret, then delete the file.
- Back up the private key. If you lose it, existing installs can't verify any later update.

### 4. GitHub secrets

Add these under Settings > Secrets and variables > Actions:

| Secret | Value |
| --- | --- |
| `MACOS_CERTIFICATE` | base64 of the Developer ID `.p12` |
| `MACOS_CERTIFICATE_PASSWORD` | the `.p12` password |
| `DEVELOPER_ID_APPLICATION` | *(optional)* `Developer ID Application: Name (TEAMID)`; detected from the cert if unset |
| `APPLE_API_KEY_ID` | App Store Connect API Key ID |
| `APPLE_API_ISSUER` | App Store Connect Issuer ID |
| `APPLE_API_KEY` | contents of `AuthKey_<KEYID>.p8` (raw or base64) |
| `SPARKLE_PRIVATE_KEY` | output of `generate_keys -x` |

You can also set the repository **variable** `XCODE_VERSION` (for example `16.4`) to pin Xcode
on the runner.

### Info.plist keys

`Jot/Info.plist` must contain these keys:

| Key | Value |
| --- | --- |
| `CFBundleShortVersionString` | marketing version, e.g. `1.1`; must equal the tag without its `v` |
| `CFBundleVersion` | build number; **must increase every release** because Sparkle compares it |
| `LSMinimumSystemVersion` | `15.0` (copied into the appcast) |
| `SUFeedURL` | `https://github.com/skdev24/jot/releases/latest/download/appcast.xml` |
| `SUPublicEDKey` | public key from `generate_keys` |

`SUFeedURL` relies on GitHub's *latest* release, so drafts and prereleases are never offered as
updates. Each release's `appcast.xml` lists only that release.

## Cutting a release

```sh
V=1.1
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $V" Jot/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(( $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Jot/Info.plist) + 1 ))" Jot/Info.plist
(cd editor && npm ci && npm test && npm run build)   # the bundle must be committed
git commit -am "Release $V"
git tag "v$V"
git push origin main "v$V"
```

Then watch the **Release** workflow. The job fails early if the tag and Info.plist disagree, or if
the editor bundle in `Jot/Editor/Web/` is stale. At the end it prints the zip's sha256 and the cask stanza (the
job summary also has them).

### Local release (optional)

```sh
export DEVELOPER_ID_APPLICATION="Developer ID Application: Name (TEAMID)"
export NOTARY_PROFILE=jot-notary            # or APPLE_API_KEY_ID / APPLE_API_ISSUER / APPLE_API_KEY_PATH
export SPARKLE_KEYCHAIN=1                   # or SPARKLE_PRIVATE_KEY / SPARKLE_KEY_FILE
export JOT_REPO="skdev24/jot"
scripts/release.sh --dmg                    # writes to build/dist/
gh release create "v$V" build/dist/Jot-$V.zip build/dist/Jot-$V.dmg build/dist/appcast.xml build/dist/SHA256SUMS --generate-notes
```

`scripts/release.sh --unsigned` runs `scripts/package.sh` (ad-hoc zip) plus checksums, with no
credentials.

## Homebrew tap

Casks live in a separate tap repo named **`skdev24/homebrew-jot`**, and `packaging/homebrew/jot.rb` in this repo
is the template for it.

1. Create `skdev24/homebrew-jot` once, and copy `packaging/homebrew/jot.rb` into it as `Casks/jot.rb`.
2. For each release, set `version` and `sha256` from the workflow output (or from `build/dist/SHA256SUMS`):

   ```sh
   brew style --fix Casks/jot.rb
   brew audit --cask --strict --online skdev24/jot/jot
   git commit -am "jot $V" && git push
   ```

Users install with `brew install --cask skdev24/jot/jot`. The cask sets `auto_updates true`, so
Sparkle handles upgrades. `brew zap` never removes the notes in `~/Documents/Jot`.

## Verifying

```sh
xcrun stapler validate Jot.app
spctl -a -vv Jot.app                         # accepted, source=Notarized Developer ID
codesign --verify --deep --strict --verbose=2 Jot.app
codesign -dv --verbose=2 Jot.app 2>&1 | grep -E 'Authority|TeamIdentifier|Runtime'
lipo -archs Jot.app/Contents/MacOS/Jot       # x86_64 arm64
spctl -a -vv -t install Jot-$V.dmg
xcrun stapler validate Jot-$V.dmg
shasum -a 256 -c SHA256SUMS
curl -sL https://github.com/skdev24/jot/releases/latest/download/appcast.xml | grep -E 'sparkle:(version|shortVersionString|edSignature)'
```

Finally, install the previous release, choose *Check for Updates…*, and confirm that it updates
to the new version.
