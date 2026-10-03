#!/bin/zsh
# Build DailyOps (Release), re-sign with the real dev identity so macOS
# permission grants survive rebuilds, and install to /Applications.
set -euo pipefail
cd "$(dirname "$0")/.."

# Signing identity resolution: CODESIGN_IDENTITY env var wins, then the
# first Developer ID Application cert, then the first Apple Development
# cert, then ad-hoc. A stable identity keeps macOS permission grants
# (Accessibility, Microphone) intact across rebuilds.
find_identity() {
  security find-identity -v -p codesigning | { grep -o "\"$1: [^\"]*\"" || true; } | head -1 | tr -d '"'
}
IDENTITY="${CODESIGN_IDENTITY:-$(find_identity "Developer ID Application")}"
[[ -z "$IDENTITY" ]] && IDENTITY=$(find_identity "Apple Development")
[[ -z "$IDENTITY" ]] && IDENTITY="-"
echo "Signing as: $IDENTITY"
APP="build/Build/Products/Release/DailyOps.app"

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode-beta.app ]]; then
  export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
fi

xcodegen generate
# No output filters here: under pipefail a non-matching grep would kill
# the script silently and leave a stale build installed.
xattr -cr DailyOpsApp
xcodebuild -project DailyOps.xcodeproj -scheme DailyOps \
  -configuration Release -arch arm64 -derivedDataPath build build -quiet CODE_SIGNING_ALLOWED=NO
echo "BUILD OK"

xattr -cr "$APP"
if [[ "$IDENTITY" == "-" ]]; then
  codesign --force --deep --options runtime \
    --entitlements DailyOpsApp/DailyOps.entitlements --sign "$IDENTITY" "$APP"
else
  codesign --force --deep --options runtime --timestamp \
    --entitlements DailyOpsApp/DailyOps.entitlements --sign "$IDENTITY" "$APP"
fi
codesign --verify --deep "$APP" && echo "Signature OK: $(codesign -dv "$APP" 2>&1 | grep '^Authority' | head -1 || echo 'Ad-hoc signed')"

pkill -x "DailyOps" 2>/dev/null || true
rm -rf "/Applications/DailyOps.app"
cp -R "$APP" "/Applications/DailyOps.app"
/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f -R "/Applications/DailyOps.app" 2>/dev/null || true
touch "/Applications/DailyOps.app"
open "/Applications/DailyOps.app"
echo "Installed and launched /Applications/DailyOps.app"
