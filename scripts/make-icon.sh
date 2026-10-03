#!/bin/zsh
# Regenerate DailyOpsApp/Resources/AppIcon.icns and Assets.xcassets from scripts/make-icon.swift.
set -euo pipefail
cd "$(dirname "$0")/.."

swift scripts/make-icon.swift

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
mkdir -p "$TMP_DIR/AppIcon.iconset"
cp DailyOpsApp/Resources/Assets.xcassets/AppIcon.appiconset/icon_*.png "$TMP_DIR/AppIcon.iconset/"
iconutil -c icns "$TMP_DIR/AppIcon.iconset" -o DailyOpsApp/Resources/AppIcon.icns

echo "Wrote DailyOps app icon at DailyOpsApp/Resources/AppIcon.icns and Assets.xcassets"
