# Releasing Diffline

Two distribution channels, both driven by `build.sh` (locally or from `.github/workflows/build.yml`).
Bundle ID: `com.patlaplante.Diffline`. Personal settings (`TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `TAP_DIR`) are read
from `~/.config/mac-app-kit/defaults.env` or `./.release.env` — both git-ignored, never committed.

## 1. Direct download (Developer ID + notarization)

Same flow as `mdview/bundle.sh`.

```sh
# one-time: store notarization credentials (app-specific password from appleid.apple.com)
xcrun notarytool store-credentials notarize-profile --apple-id you@example.com --team-id "$TEAM_ID"

./build.sh --universal --sign devid --notarize    # → build/Diffline-<version>.zip
```

Needs the *Developer ID Application* certificate in the keychain (create it at
developer.apple.com/account/resources/certificates and install it, or export the `.p12` mdview's CI uses).

`Tools/release.sh` runs that build, creates the GitHub release for the tag, and updates the Homebrew cask
in `patbonecrusher/homebrew-tap` (`Casks/diffline.rb`) — install with `brew install --cask patbonecrusher/tap/diffline`.

## 2. Mac App Store

### One-time setup (developer.apple.com / App Store Connect)

1. **Certificates** → create and install two certificates:
   - *Apple Distribution* (signs the app)
   - *Mac Installer Distribution* (signs the `.pkg`)
2. **Identifiers** → register App ID `com.patlaplante.Diffline` (macOS, no extra capabilities).
3. **Profiles** → *Mac App Store Connect* profile for that App ID; download it to
   `Resources/Diffline.provisionprofile` (git-ignored).
4. **App Store Connect → Apps → +** → New macOS app, bundle ID `com.patlaplante.Diffline`, SKU e.g. `diffline`.
5. **Users and Access → Integrations → App Store Connect API** → generate a key with the *App Manager* role.
   Save `AuthKey_<KEYID>.p8` to `~/.appstoreconnect/private_keys/`; note the Key ID and Issuer ID.

### Each release

```sh
# bump CFBundleShortVersionString / CFBundleVersion in Resources/Info.plist, then:
ASC_KEY_ID=XXXXXXXXXX ASC_ISSUER_ID=xxxxxxxx-xxxx-… \
  ./build.sh --universal --sign appstore --pkg --upload
```

This produces a sandboxed, distribution-signed `.app` with the embedded provisioning profile, wraps it in a
signed `.pkg`, validates it and uploads it. Then in App Store Connect: attach the processed build to a
version, fill in screenshots (1280×800 or larger), description, category (Developer Tools), privacy
(no data collected), and submit for review.

What the app declares (already in `Resources/`):

- `Diffline.entitlements` — App Sandbox, user-selected file read/write (open, merge and save), app-scoped
  bookmarks (the Recent list). No network entitlement.
- `Info.plist` — `ITSAppUsesNonExemptEncryption = NO` (skips the export-compliance question),
  `LSApplicationCategoryType`, a Finder service (`NSServices`), generic document types so two items can be dropped on the Dock icon, minimum macOS 14.
- `--sign appstore` adds `com.apple.application-identifier` and `com.apple.developer.team-identifier`
  to the entitlements, matching what Xcode embeds.

The app uses only public API and no third-party code, so the automated
binary checks should pass. `CFBundleVersion` must strictly increase between uploads for the same
`CFBundleShortVersionString`.

## GitHub Actions

Pushing a tag `v*` runs both jobs; *Run workflow* lets you run the Developer ID job alone or with the
App Store job. Repository secrets:

| Secret | Used by | Value |
| --- | --- | --- |
| `MACOS_CERTIFICATE`, `MACOS_CERTIFICATE_PWD` | developer-id | base64 `.p12` of the Developer ID Application cert (same as mdview) |
| `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD` | developer-id | notarytool credentials (same as mdview) |
| `MACOS_DIST_CERTIFICATE`, `MACOS_DIST_CERTIFICATE_PWD` | app-store | base64 `.p12` containing *both* Apple Distribution and Mac Installer Distribution certs |
| `MAC_PROVISIONING_PROFILE` | app-store | base64 of the Mac App Store provisioning profile |
| `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_API_KEY` | app-store | App Store Connect API key id, issuer id, base64 of the `.p8` |

```sh
base64 -i cert.p12 | pbcopy      # etc.
gh secret set MACOS_CERTIFICATE --repo patbonecrusher/diffline
```

## Local testing of the sandbox

`./build.sh --sign dev --open` signs with the Apple Development certificate and the real sandbox
entitlements, which is the closest you can get to the App Store build without the distribution certs.

## Store assets

`Marketing/` holds the App Store icon (`AppIcon-1024.png`, also embedded in the build's `.icns`, which is
what App Store Connect actually uses for macOS) and 2560×1600 screenshots. To regenerate screenshots:
build with `--sign dev`, open a sample, capture the window with `screencapture -o -l <windowID>`, then
`swiftc -O -o compose Marketing/compose.swift && ./compose capture.png Marketing/screenshot-x.png [dark]`.

## Listing automation

`Tools/asc.py` drives the App Store Connect API (needs `uv`; deps are declared inline):

```sh
export ASC_KEY_ID=… ASC_ISSUER_ID=…
Tools/asc.py status          # what's filled in, builds, attached build
Tools/asc.py all             # metadata + screenshots + price + review contact + latest build
Tools/asc.py submit          # create the review submission
```

App Privacy ("no data collected") has no public API and must be set once in the web UI.
