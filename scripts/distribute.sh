#!/usr/bin/env bash
# Hotbar direct distribution script
# Usage: ./scripts/distribute.sh [version]
# Requires: Developer ID Application cert, xcrun notarytool, create-dmg
#
# One-time setup:
#   1. Xcode > Settings > Accounts > Manage Certificates > + > Developer ID Application
#   2. brew install create-dmg
#   3. Set env vars: APPLE_ID, NOTARYTOOL_PASSWORD (App-Specific Password), TEAM_ID

set -euo pipefail

VERSION="${1:-$(defaults read "$(pwd)/Sources/Hotbar/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "1.0.0")}"
SCHEME="Hotbar"
PROJECT="Hotbar.xcodeproj"
ARCHIVE_PATH="/tmp/Hotbar-${VERSION}.xcarchive"
EXPORT_PATH="/tmp/Hotbar-${VERSION}-export"
APP_PATH="${EXPORT_PATH}/Hotbar.app"
DMG_NAME="Hotbar-${VERSION}.dmg"
DMG_PATH="$(pwd)/build/${DMG_NAME}"
TEAM_ID="${TEAM_ID:-4YZQY4C47E}"

echo "==> Hotbar ${VERSION} – direct distribution build"
echo ""

# ── 1. Archive ───────────────────────────────────────────────────────────────
echo "[1/5] Archiving..."
xcodebuild archive \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -configuration Release \
  -archivePath "${ARCHIVE_PATH}" \
  -destination "generic/platform=macOS" \
  | xcbeautify 2>/dev/null || true

echo "      Archive: ${ARCHIVE_PATH}"

# ── 2. Export ────────────────────────────────────────────────────────────────
echo "[2/5] Exporting with Developer ID..."
rm -rf "${EXPORT_PATH}"
xcodebuild -exportArchive \
  -archivePath "${ARCHIVE_PATH}" \
  -exportPath "${EXPORT_PATH}" \
  -exportOptionsPlist ExportOptions.plist

echo "      App: ${APP_PATH}"

# ── 3. Notarize ──────────────────────────────────────────────────────────────
echo "[3/5] Notarizing (this takes ~2 minutes)..."

if [ -z "${APPLE_ID:-}" ] || [ -z "${NOTARYTOOL_PASSWORD:-}" ]; then
  echo "      ⚠ APPLE_ID / NOTARYTOOL_PASSWORD not set – skipping notarization"
  echo "      Set them and re-run, or run manually:"
  echo "        xcrun notarytool submit ${APP_PATH} \\"
  echo "          --apple-id YOUR_APPLE_ID \\"
  echo "          --password YOUR_APP_SPECIFIC_PASSWORD \\"
  echo "          --team-id ${TEAM_ID} --wait"
else
  # Zip the app for submission (notarytool accepts .zip or .dmg)
  NOTARIZE_ZIP="/tmp/Hotbar-${VERSION}-notarize.zip"
  ditto -c -k --keepParent "${APP_PATH}" "${NOTARIZE_ZIP}"

  xcrun notarytool submit "${NOTARIZE_ZIP}" \
    --apple-id "${APPLE_ID}" \
    --password "${NOTARYTOOL_PASSWORD}" \
    --team-id "${TEAM_ID}" \
    --wait

  echo "[4/5] Stapling notarization ticket..."
  xcrun stapler staple "${APP_PATH}"
  echo "      ✓ Stapled"
fi

# ── 4. Package DMG ───────────────────────────────────────────────────────────
echo "[4/5] Creating DMG..."
mkdir -p "$(pwd)/build"

if command -v create-dmg &>/dev/null; then
  create-dmg \
    --volname "Hotbar ${VERSION}" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 100 \
    --icon "Hotbar.app" 175 190 \
    --hide-extension "Hotbar.app" \
    --app-drop-link 425 190 \
    "${DMG_PATH}" \
    "${EXPORT_PATH}/"
else
  # Fallback: plain hdiutil DMG
  hdiutil create -volname "Hotbar ${VERSION}" \
    -srcfolder "${EXPORT_PATH}" \
    -ov -format UDZO \
    "${DMG_PATH}"
fi

echo "      DMG: ${DMG_PATH}"

# ── 5. Verify ────────────────────────────────────────────────────────────────
echo "[5/5] Verifying signature..."
codesign --verify --deep --strict --verbose=2 "${APP_PATH}" 2>&1 | tail -3
spctl --assess --type exec --verbose "${APP_PATH}" 2>&1 | tail -3

echo ""
echo "✓ Done: ${DMG_PATH}"
echo "  Share this DMG for direct distribution."
