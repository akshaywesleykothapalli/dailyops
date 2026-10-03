#!/bin/zsh
# Build DailyOps (Release), sign it, and package a drag-to-install DMG.
set -euo pipefail
cd "$(dirname "$0")/.."

# Signing identity resolution: CODESIGN_IDENTITY env var wins, then
# Developer ID Application (Gatekeeper-friendly on other Macs), then an
# Apple Development cert (recipients right-click → Open once), then ad-hoc.
find_identity() {
  security find-identity -v -p codesigning | { grep -o "\"$1: [^\"]*\"" || true; } | head -1 | tr -d '"'
}
IDENTITY="${CODESIGN_IDENTITY:-$(find_identity "Developer ID Application")}"
[[ -z "$IDENTITY" ]] && IDENTITY=$(find_identity "Apple Development")
[[ -z "$IDENTITY" ]] && IDENTITY="-"
echo "Signing as: $IDENTITY"
APP="build/Build/Products/Release/DailyOps.app"
DMG="build/DailyOps.dmg"

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode-beta.app ]]; then
  export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
fi

xcodegen generate
xcodebuild -project DailyOps.xcodeproj -scheme DailyOps \
  -configuration Release -arch arm64 -derivedDataPath build build -quiet
echo "BUILD OK"

codesign --force --deep --options runtime --timestamp \
  --entitlements DailyOpsApp/DailyOps.entitlements --sign "$IDENTITY" "$APP"
codesign --verify --deep "$APP"

STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "DailyOps" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
# Sign the DMG container itself so Gatekeeper can evaluate the download
# before it's even opened.
if [[ "$IDENTITY" != "-" ]]; then
  codesign --force --timestamp --sign "$IDENTITY" "$DMG"
fi
echo "Created $DMG ($(du -h "$DMG" | cut -f1))"

# Notarize when possible: needs a Developer ID signature plus a stored
# credential profile (one-time: xcrun notarytool store-credentials
# dailyops-notary --apple-id <email> --team-id <team> --password <app-pw>).
if [[ "$IDENTITY" == Developer\ ID* ]]; then
  if xcrun notarytool history --keychain-profile dailyops-notary >/dev/null 2>&1; then
    echo "Notarizing (this can take a few minutes)…"
    xcrun notarytool submit "$DMG" --keychain-profile dailyops-notary --wait
    xcrun stapler staple "$DMG"
    echo "Notarized and stapled."
  else
    echo "NOTE: skipping notarization — no 'dailyops-notary' keychain profile."
  fi
fi
