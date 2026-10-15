#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_SPEC_PATH="$ROOT_DIR/project.yml"
PROJECT_PATH="$ROOT_DIR/MadQuillQuickLook.xcodeproj"
SCHEME="MadQuillQuickLook"
APP_NAME="MadQuill"
CONFIGURATION="Release"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build}"
ARCHIVE_PATH="$BUILD_DIR/${APP_NAME}.xcarchive"
APP_BUNDLE_NAME="${APP_BUNDLE_NAME:-MadQuillApp.app}"
APP_BUNDLE_PATH="$ARCHIVE_PATH/Products/Applications/$APP_BUNDLE_NAME"
DMG_PATH="$BUILD_DIR/${APP_NAME}.dmg"
APP_BUNDLE_FILENAME=""
APP_ENTITLEMENTS_PATH="$ROOT_DIR/MadQuillApp/MadQuillApp.entitlements"
EXT_ENTITLEMENTS_PATH="$ROOT_DIR/MarkdownQuickLookExtension/MarkdownQuickLookExtension.entitlements"
EXT_BUNDLE_NAME="${EXT_BUNDLE_NAME:-MarkdownQuickLookExtension.appex}"

if [[ ! -f "$PROJECT_SPEC_PATH" ]]; then
  echo "Project spec not found at: $PROJECT_SPEC_PATH" >&2
  exit 1
fi

mkdir -p "$BUILD_DIR"

cd "$ROOT_DIR"

if [[ "${REGENERATE_XCODE_PROJECT:-1}" == "1" || ! -d "$PROJECT_PATH" ]]; then
  echo "[1/4] Generating Xcode project"
  xcodegen generate --spec "$PROJECT_SPEC_PATH" >/dev/null
else
  echo "[1/4] Using existing Xcode project at $PROJECT_PATH"
fi

echo "[2/4] Archiving app"
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -archivePath "$ARCHIVE_PATH" \
  -destination "generic/platform=macOS" \
  CODE_SIGNING_ALLOWED=NO \
  clean archive

if [[ ! -d "$APP_BUNDLE_PATH" ]]; then
  detected_app="$(find "$ARCHIVE_PATH/Products/Applications" -maxdepth 1 -type d -name "*.app" | head -n 1 || true)"
  if [[ -n "$detected_app" ]]; then
    APP_BUNDLE_PATH="$detected_app"
  else
    echo "No .app bundle found inside archive at $ARCHIVE_PATH/Products/Applications" >&2
    exit 1
  fi
fi

APP_BUNDLE_FILENAME="$(basename "$APP_BUNDLE_PATH")"

if [[ -n "${APPLE_DEVELOPER_IDENTITY:-}" ]]; then
  if [[ "${1:-release}" == "release" && "${APPLE_DEVELOPER_IDENTITY}" != Developer\ ID\ Application:* ]]; then
    echo "Warning: APPLE_DEVELOPER_IDENTITY is not a Developer ID Application certificate." >&2
    echo "For public distribution, use: Developer ID Application: <Name> (<TEAMID>)" >&2
  fi
  echo "[3/4] Signing app"
  EXT_BUNDLE_PATH="$APP_BUNDLE_PATH/Contents/PlugIns/$EXT_BUNDLE_NAME"
  if [[ ! -d "$EXT_BUNDLE_PATH" ]]; then
    detected_appex="$(find "$APP_BUNDLE_PATH/Contents/PlugIns" -maxdepth 1 -type d -name "*.appex" | head -n 1 || true)"
    if [[ -n "$detected_appex" ]]; then
      EXT_BUNDLE_PATH="$detected_appex"
    else
      echo "No .appex bundle found inside app at $APP_BUNDLE_PATH/Contents/PlugIns" >&2
      exit 1
    fi
  fi

  /usr/bin/codesign --force --verify --timestamp \
    --options runtime \
    --entitlements "$EXT_ENTITLEMENTS_PATH" \
    --sign "$APPLE_DEVELOPER_IDENTITY" \
    "$EXT_BUNDLE_PATH"

  /usr/bin/codesign --force --verify --timestamp \
    --options runtime \
    --entitlements "$APP_ENTITLEMENTS_PATH" \
    --sign "$APPLE_DEVELOPER_IDENTITY" \
    "$APP_BUNDLE_PATH"
else
  echo "[3/4] Skipping code signing (APPLE_DEVELOPER_IDENTITY not set)"
fi

if [[ "${1:-release}" == "archive" ]]; then
  echo "Archive created at: $ARCHIVE_PATH"
  if [[ -n "${APPLE_DEVELOPER_IDENTITY:-}" ]]; then
    echo "Signed app available at: $APP_BUNDLE_PATH"
  fi
  exit 0
fi

if [[ -n "${APPLE_DEVELOPER_IDENTITY:-}" ]]; then
  echo "[4/4] Creating DMG"
  rm -f "$DMG_PATH"
  rm -rf "$BUILD_DIR/volume"

  mkdir -p "$BUILD_DIR/volume"
  cp -R "$APP_BUNDLE_PATH" "$BUILD_DIR/volume/$APP_BUNDLE_FILENAME"
  ln -s /Applications "$BUILD_DIR/volume/Applications"
  cat >"$BUILD_DIR/volume/OPEN ME FIRST - LEGGIMI.txt" <<EOF
MadQuill quick install / Installazione rapida
==============================================

EN
--
1) Drag "$APP_BUNDLE_FILENAME" into "Applications".
2) Open the app once from Applications.
3) In Finder, select a Markdown file and press Space to test Quick Look.

If preview does not appear, run:
  qlmanage -r
  qlmanage -r cache

IT
--
1) Trascina "$APP_BUNDLE_FILENAME" dentro "Applications".
2) Apri l'app una volta dalla cartella Applications.
3) In Finder, seleziona un file Markdown e premi Space per testare Quick Look.

Se l'anteprima non compare, esegui:
  qlmanage -r
  qlmanage -r cache
EOF

  cat >"$BUILD_DIR/volume/INSTALL.txt" <<EOF
MadQuill installation
=====================

1) Drag "$APP_BUNDLE_FILENAME" into "Applications".
2) Open the app once from Applications.
3) In Finder, select a Markdown file and press Space to test Quick Look.

If preview does not appear, run:
  qlmanage -r
  qlmanage -r cache
EOF

  diskutil image create from \
    --format UDZO \
    --volumeName "$APP_NAME" \
    "$BUILD_DIR/volume" \
    "$DMG_PATH" >/dev/null

  rm -rf "$BUILD_DIR/volume"
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
