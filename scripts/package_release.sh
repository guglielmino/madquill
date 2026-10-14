#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/MadQuillQuickLook.xcodeproj"
SCHEME="MadQuillQuickLook"
APP_NAME="MadQuill"
CONFIGURATION="Release"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build}"
ARCHIVE_PATH="$BUILD_DIR/${APP_NAME}.xcarchive"
APP_BUNDLE_PATH="$ARCHIVE_PATH/Products/Applications/${APP_NAME}.app"
DMG_PATH="$BUILD_DIR/${APP_NAME}.dmg"

mkdir -p "$BUILD_DIR"

echo "[1/4] Generating Xcode project"
xcodegen generate >/dev/null

echo "[2/4] Archiving app"
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -archivePath "$ARCHIVE_PATH" \
  -destination "generic/platform=macOS" \
  clean archive

if [[ -n "${APPLE_DEVELOPER_IDENTITY:-}" ]]; then
  echo "[3/4] Signing app"
  /usr/bin/codesign --deep --force --verify --timestamp \
    --options runtime \
    --sign "$APPLE_DEVELOPER_IDENTITY" \
    "$APP_BUNDLE_PATH"
else
  echo "[3/4] Skipping code signing (APPLE_DEVELOPER_IDENTITY not set)"
fi

if [[ "${1:-release}" == "archive" ]]; then
  echo "Archive created at: $ARCHIVE_PATH"
  exit 0
fi

if [[ -n "${APPLE_DEVELOPER_IDENTITY:-}" ]]; then
  echo "[4/4] Creating DMG"
  rm -f "$DMG_PATH"
  hdiutil create -volname "$APP_NAME" -srcfolder "$APP_BUNDLE_PATH" -ov -format UDBZ "$DMG_PATH"
  echo "DMG created at: $DMG_PATH"
else
  echo "[4/4] Skipping DMG creation because signing identity is missing."
  echo "Set APPLE_DEVELOPER_IDENTITY to create a distributable DMG."
fi

if [[ -n "${APPLE_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" && -n "${APPLE_TEAM_ID:-}" ]]; then
  echo "Submitting notarization request"
  xcrun notarytool submit "$DMG_PATH" \
    --apple-id "$APPLE_ID" \
    --password "$APPLE_APP_PASSWORD" \
    --team-id "$APPLE_TEAM_ID" \
    --wait

  echo "Stapling notarization to DMG"
  xcrun stapler staple "$DMG_PATH"
fi
