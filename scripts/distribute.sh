#!/usr/bin/env bash
# Hotbar direct distribution script
# Usage: ./scripts/distribute.sh [version]
#
# Produces a Developer ID signed, notarized and stapled DMG in build/.
# Both the .app and the .dmg are notarized+stapled, so the DMG passes
# `xcrun stapler validate` and installs offline without a Gatekeeper prompt.
#
# Requires:
#   - "Developer ID Application: ... (4YZQY4C47E)" in the login keychain
#   - create-dmg  (brew install create-dmg)
#   - notarytool credentials, either:
#       a) a keychain profile (preferred, default name "hotbar-notary"):
#            xcrun notarytool store-credentials "hotbar-notary" \
#              --key ~/.appstoreconnect/private_keys/AuthKey_XXXXXXXXXX.p8 \
#              --key-id XXXXXXXXXX --issuer <issuer-uuid>
#          override the profile name with NOTARY_PROFILE=<name>
#       b) env vars APPLE_ID + NOTARYTOOL_PASSWORD (app-specific password)

set -euo pipefail

VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$(pwd)/Sources/Hotbar/Info.plist" 2>/dev/null || echo "1.0.0")}"
SCHEME="Hotbar"
PROJECT="Hotbar.xcodeproj"
ARCHIVE_PATH="/tmp/Hotbar-${VERSION}.xcarchive"
EXPORT_PATH="/tmp/Hotbar-${VERSION}-export"
APP_PATH="${EXPORT_PATH}/Hotbar.app"
DMG_NAME="Hotbar-${VERSION}.dmg"
DMG_PATH="$(pwd)/build/${DMG_NAME}"
TEAM_ID="${TEAM_ID:-4YZQY4C47E}"
NOTARY_PROFILE="${NOTARY_PROFILE:-hotbar-notary}"
SIGN_ID="${SIGN_ID:-Developer ID Application}"

# ── notarytool credentials ───────────────────────────────────────────────────
# Resolve once, up front: a build that silently skips notarization produces an
# artifact that looks fine locally and fails on every other Mac.
NOTARY_ARGS=()
if xcrun notarytool history --keychain-profile "${NOTARY_PROFILE}" >/dev/null 2>&1; then
  NOTARY_ARGS=(--keychain-profile "${NOTARY_PROFILE}")
  echo "==> notarytool: keychain profile '${NOTARY_PROFILE}'"
elif [ -n "${APPLE_ID:-}" ] && [ -n "${NOTARYTOOL_PASSWORD:-}" ]; then
  NOTARY_ARGS=(--apple-id "${APPLE_ID}" --password "${NOTARYTOOL_PASSWORD}" --team-id "${TEAM_ID}")
  echo "==> notarytool: APPLE_ID + app-specific password"
else
  cat >&2 <<EOF
✗ No notarytool credentials found.

Set up ONE of these, then re-run:

  a) Keychain profile (preferred):
       xcrun notarytool store-credentials "${NOTARY_PROFILE}" \\
         --key ~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8 \\
         --key-id <KEYID> --issuer <ISSUER-UUID>

  b) App-specific password:
       export APPLE_ID=<your-apple-id>
       export NOTARYTOOL_PASSWORD=<app-specific-password>
EOF
  exit 1
fi

echo "==> Hotbar ${VERSION} – direct distribution build"
echo ""

# ── 1. Archive ───────────────────────────────────────────────────────────────
echo "[1/6] Archiving..."
xcodebuild archive \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -configuration Release \
  -archivePath "${ARCHIVE_PATH}" \
  -destination "generic/platform=macOS"

echo "      Archive: ${ARCHIVE_PATH}"

# ── 2. Export ────────────────────────────────────────────────────────────────
echo "[2/6] Exporting with Developer ID..."
rm -rf "${EXPORT_PATH}"
xcodebuild -exportArchive \
  -archivePath "${ARCHIVE_PATH}" \
  -exportPath "${EXPORT_PATH}" \
  -exportOptionsPlist ExportOptions.plist

echo "      App: ${APP_PATH}"

# ── 3. Notarize + staple the app ─────────────────────────────────────────────
echo "[3/6] Notarizing the app (this takes ~2 minutes)..."
NOTARIZE_ZIP="/tmp/Hotbar-${VERSION}-notarize.zip"
ditto -c -k --keepParent "${APP_PATH}" "${NOTARIZE_ZIP}"
xcrun notarytool submit "${NOTARIZE_ZIP}" "${NOTARY_ARGS[@]}" --wait
xcrun stapler staple "${APP_PATH}"
echo "      ✓ App stapled"

# ── 4. Package DMG (from the stapled app) ────────────────────────────────────
echo "[4/6] Creating DMG..."
mkdir -p "$(pwd)/build"
rm -f "${DMG_PATH}"
rm -f "$(pwd)"/build/rw.*.dmg

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
  hdiutil create -volname "Hotbar ${VERSION}" \
    -srcfolder "${EXPORT_PATH}" \
    -ov -format UDZO \
    "${DMG_PATH}"
fi
rm -f "$(pwd)"/build/rw.*.dmg
echo "      DMG: ${DMG_PATH}"

# ── 5. Sign + notarize + staple the DMG ──────────────────────────────────────
# The DMG is the thing users download, so it needs its own ticket; stapling
# the app alone leaves `stapler validate <dmg>` failing.
echo "[5/6] Signing, notarizing and stapling the DMG..."
codesign --force --sign "${SIGN_ID}" --timestamp "${DMG_PATH}"
xcrun notarytool submit "${DMG_PATH}" "${NOTARY_ARGS[@]}" --wait
xcrun stapler staple "${DMG_PATH}"
echo "      ✓ DMG stapled"

# ── 6. Verify ────────────────────────────────────────────────────────────────
echo "[6/6] Verifying..."
echo "--- codesign -dv --verbose=4 (app) ---"
codesign -dv --verbose=4 "${APP_PATH}" 2>&1
echo "--- codesign --verify --deep --strict (app) ---"
codesign --verify --deep --strict --verbose=2 "${APP_PATH}" 2>&1
echo "--- spctl --assess --type exec -vv (app) ---"
spctl --assess --type exec -vv "${APP_PATH}" 2>&1
echo "--- stapler validate (app) ---"
xcrun stapler validate "${APP_PATH}" 2>&1
echo "--- stapler validate (dmg) ---"
xcrun stapler validate "${DMG_PATH}" 2>&1

echo ""
echo "✓ Done: ${DMG_PATH}"
echo "  Notarized + stapled. Share this DMG for direct distribution."
