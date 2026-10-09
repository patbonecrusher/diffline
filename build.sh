#!/bin/zsh
# Build, bundle, sign and (optionally) notarize or package "Diffline.app".
#
#   ./build.sh                       ad-hoc signed, sandboxed app in ./build (local testing)
#   ./build.sh --open                …and launch it
#   ./build.sh --sign dev            sign with "Apple Development" (tests the sandbox for real)
#   ./build.sh --sign devid          Developer ID + hardened runtime (direct download)
#   ./build.sh --sign devid --notarize
#   ./build.sh --sign appstore --pkg           signed .pkg ready for App Store Connect
#   ./build.sh --sign appstore --pkg --upload  …and upload it (see RELEASING.md)
#
# Options: debug|release (default release), --universal (arm64 + x86_64)
#
# Environment:
#   TEAM_ID              Apple team id (or put it in .release.env / ~/.config/mac-app-kit/defaults.env, both git-ignored)
#   NOTARY_PROFILE       notarytool keychain profile (default notarize-profile), or
#   APPLE_ID / APPLE_APP_PASSWORD / APPLE_TEAM_ID for notarytool with an app-specific password, or
#   ASC_KEY_ID / ASC_ISSUER_ID to notarize with the App Store Connect API key
#   PROVISIONING_PROFILE path to the Mac App Store .provisionprofile (default Resources/Diffline.provisionprofile)
#   ASC_KEY_ID / ASC_ISSUER_ID   App Store Connect API key for --upload (the .p8 must be in ~/.appstoreconnect/private_keys)
set -euo pipefail
cd "$(dirname "$0")"

CONFIG=release
SIGN=none
NOTARIZE=0
PKG=0
UPLOAD=0
OPEN=0
UNIVERSAL=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    debug|release) CONFIG=$1 ;;
    --sign) SIGN=$2; shift ;;
    --notarize) NOTARIZE=1 ;;
    --pkg) PKG=1 ;;
    --upload) UPLOAD=1; PKG=1 ;;
    --open) OPEN=1 ;;
    --universal) UNIVERSAL=1 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
  shift
done

APP_NAME="Diffline"
BUNDLE_ID="com.patlaplante.Diffline"
# Personal defaults live outside the repo: ~/.config/mac-app-kit/defaults.env, then ./.release.env (both optional).
for f in "$HOME/.config/mac-app-kit/defaults.env" ./.release.env; do [[ -f $f ]] && source "$f"; done
: "${TEAM_ID:?set TEAM_ID (Apple team id) in the environment or .release.env}"
BUILD_DIR="$PWD/build"
APP="$BUILD_DIR/$APP_NAME.app"
PROVISIONING_PROFILE="${PROVISIONING_PROFILE:-Resources/Diffline.provisionprofile}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"

# ---------------------------------------------------------------- build
ARCH_FLAGS=()
if [[ $UNIVERSAL == 1 ]]; then ARCH_FLAGS=(--arch arm64 --arch x86_64); fi
echo "==> Building ($CONFIG$([[ $UNIVERSAL == 1 ]] && echo ", universal"))…"
swift build -c "$CONFIG" "${ARCH_FLAGS[@]}" --product Diffline
swift build -c "$CONFIG" --product MakeIcon      # host-arch only; it just runs at build time
BIN="$(swift build -c "$CONFIG" "${ARCH_FLAGS[@]}" --show-bin-path)"
HOST_BIN="$(swift build -c "$CONFIG" --show-bin-path)"

# ---------------------------------------------------------------- bundle
echo "==> Bundling…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Diffline" "$APP/Contents/MacOS/Diffline"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

ICONSET="$BUILD_DIR/AppIcon.iconset"
rm -rf "$ICONSET"
"$HOST_BIN/MakeIcon" "$ICONSET" > /dev/null
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# ---------------------------------------------------------------- sign
find_identity() {   # prints the first identity whose name matches $1 and team $2
  security find-identity -v -p codesigning | grep "$1" | grep "($2)" | head -1 | sed -E 's/.*"(.*)".*/\1/'
}
require_identity() {
  local id; id="$(find_identity "$1" "$TEAM_ID")"
  if [[ -z $id ]]; then
    echo "error: no \"$1\" certificate for team $TEAM_ID in the keychain." >&2
    echo "       Create one at https://developer.apple.com/account/resources/certificates and double-click to install." >&2
    exit 1
  fi
  echo "$id"
}

ENTITLEMENTS="$BUILD_DIR/Diffline.entitlements"
cp Resources/Diffline.entitlements "$ENTITLEMENTS"
SIGN_FLAGS=(--force --timestamp --options runtime)

case "$SIGN" in
  none)
    IDENTITY="-"
    SIGN_FLAGS=(--force)
    ;;
  dev)
    IDENTITY="$(security find-identity -v -p codesigning | grep 'Apple Development' | head -1 | sed -E 's/.*"(.*)".*/\1/')"
    [[ -n $IDENTITY ]] || { echo "error: no Apple Development certificate in keychain" >&2; exit 1; }
    SIGN_FLAGS=(--force --timestamp=none)
    ;;
  devid)
    IDENTITY="$(require_identity 'Developer ID Application')"
    ;;
  appstore)
    SIGN_FLAGS=(--force --timestamp)                       # App Store: sandbox, no hardened runtime needed
    if [[ ! -f $PROVISIONING_PROFILE ]]; then
      echo "error: Mac App Store provisioning profile not found at $PROVISIONING_PROFILE" >&2
      echo "       Create one (Profiles → Mac App Store Connect, bundle ID $BUNDLE_ID) and download it there." >&2
      exit 1
    fi
    # App Store Connect rejects the upload unless the app is signed with the exact certificate
    # embedded in the profile, so pick that one (by SHA-1) rather than guessing by name.
    IDENTITY=""
    for sha in $(security cms -D -i "$PROVISIONING_PROFILE" | python3 -c '
import plistlib, sys, hashlib
for c in plistlib.loads(sys.stdin.buffer.read())["DeveloperCertificates"]: print(hashlib.sha1(c).hexdigest().upper())'); do
      if security find-identity -v -p codesigning | grep -q "$sha"; then IDENTITY="$sha"; break; fi
    done
    if [[ -z $IDENTITY ]]; then
      echo "error: none of the certificates in $PROVISIONING_PROFILE is in the keychain (with its private key)." >&2
      echo "       Regenerate the profile with a certificate from: security find-identity -v -p codesigning" >&2
      exit 1
    fi
    cp "$PROVISIONING_PROFILE" "$APP/Contents/embedded.provisionprofile"
    # The profile requires the app to declare its identity in the entitlements, like Xcode does.
    /usr/libexec/PlistBuddy -c "Add :com.apple.application-identifier string $TEAM_ID.$BUNDLE_ID" "$ENTITLEMENTS"
    /usr/libexec/PlistBuddy -c "Add :com.apple.developer.team-identifier string $TEAM_ID" "$ENTITLEMENTS"
    ;;
  *) echo "unknown --sign mode: $SIGN (none|dev|devid|appstore)" >&2; exit 1 ;;
esac

# Downloaded files (e.g. the provisioning profile) carry com.apple.quarantine; App Store Connect rejects
# packages containing it (ITMS-91109). Strip all extended attributes before signing.
xattr -cr "$APP"

echo "==> Signing ($SIGN: $IDENTITY)…"
codesign "${SIGN_FLAGS[@]}" --sign "$IDENTITY" --entitlements "$ENTITLEMENTS" --identifier "$BUNDLE_ID" "$APP"
codesign --verify --strict --verbose=2 "$APP"
touch "$APP"
echo "==> App: $APP"

# ---------------------------------------------------------------- notarize (Developer ID)
if [[ $NOTARIZE == 1 ]]; then
  [[ $SIGN == devid ]] || { echo "error: --notarize requires --sign devid" >&2; exit 1; }
  ZIP="$BUILD_DIR/Diffline-$VERSION.zip"
  echo "==> Notarizing…"
  ditto -c -k --keepParent "$APP" "$ZIP"
  if [[ -n ${ASC_KEY_ID:-} ]]; then
    xcrun notarytool submit "$ZIP" --key "$HOME/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8" \
      --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" --wait
  elif [[ -n ${APPLE_ID:-} ]]; then
    xcrun notarytool submit "$ZIP" --apple-id "$APPLE_ID" --team-id "${APPLE_TEAM_ID:-$TEAM_ID}" \
      --password "$APPLE_APP_PASSWORD" --wait
  else
    xcrun notarytool submit "$ZIP" --keychain-profile "${NOTARY_PROFILE:-notarize-profile}" --wait
  fi
  xcrun stapler staple "$APP"
  ditto -c -k --keepParent "$APP" "$ZIP"      # re-zip with the ticket stapled
  spctl --assess --type execute --verbose=2 "$APP"
  echo "==> Notarized: $ZIP"
fi

# ---------------------------------------------------------------- package / upload (App Store)
if [[ $PKG == 1 ]]; then
  [[ $SIGN == appstore ]] || { echo "error: --pkg requires --sign appstore" >&2; exit 1; }
  INSTALLER_ID="$(security find-identity -v | grep -E '3rd Party Mac Developer Installer|Mac Installer Distribution' | grep "($TEAM_ID)" | head -1 | sed -E 's/.*"(.*)".*/\1/')"
  [[ -n $INSTALLER_ID ]] || { echo "error: no Mac Installer Distribution certificate for team $TEAM_ID" >&2; exit 1; }
  PKG_PATH="$BUILD_DIR/Diffline-$VERSION.pkg"
  echo "==> Packaging ($INSTALLER_ID)…"
  productbuild --component "$APP" /Applications --sign "$INSTALLER_ID" "$PKG_PATH"
  echo "==> Package: $PKG_PATH"

  if [[ $UPLOAD == 1 ]]; then
    : "${ASC_KEY_ID:?set ASC_KEY_ID (App Store Connect API key id)}"
    : "${ASC_ISSUER_ID:?set ASC_ISSUER_ID}"
    echo "==> Validating with App Store Connect…"
    xcrun altool --validate-app -f "$PKG_PATH" -t macos --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
    echo "==> Uploading…"
    xcrun altool --upload-app -f "$PKG_PATH" -t macos --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
    echo "==> Uploaded. Finish the submission in App Store Connect."
  fi
fi

if [[ $OPEN == 1 ]]; then open "$APP"; fi
