#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

APP_NAME="TypeLessBuddy"
SCHEME="TypeLessBuddy"
PROJECT_PATH="${REPO_ROOT}/TypeLessBuddy.xcodeproj"
RELEASE_DIR="${REPO_ROOT}/dist"
RELEASE_BUILD_DIR="${RELEASE_DIR}/build"
RELEASE_DERIVED_DATA_DIR="${RELEASE_DIR}/DerivedData"
STAGING_DIR="${RELEASE_DIR}/dmg"
VOLUME_NAME="${APP_NAME}"
APP_BUILD_PATH="${RELEASE_BUILD_DIR}/Release/${APP_NAME}.app"
APP_PATH="${RELEASE_DIR}/${APP_NAME}.app"
DMG_PATH="${RELEASE_DIR}/${APP_NAME}.dmg"
TEMP_DMG_PATH="${RELEASE_DIR}/${APP_NAME}-temp.dmg"
MOUNT_ROOT="/Volumes/${VOLUME_NAME}"

SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
APPLE_ID="${APPLE_ID:-}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-}"
APPLE_APP_PASSWORD="${APPLE_APP_PASSWORD:-}"

function require_command() {
  local command_name="$1"
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Missing required command: ${command_name}" >&2
    exit 1
  fi
}

function cleanup() {
  if mount | grep -q "${MOUNT_ROOT}"; then
    hdiutil detach "${MOUNT_ROOT}" -quiet || true
  fi
}

trap cleanup EXIT

require_command xcodebuild
require_command hdiutil
require_command osascript

mkdir -p "${RELEASE_DIR}"
rm -rf "${STAGING_DIR}" "${DMG_PATH}" "${TEMP_DMG_PATH}" "${APP_PATH}" "${RELEASE_BUILD_DIR}" "${RELEASE_DERIVED_DATA_DIR}"

echo "Building ${APP_NAME}.app..."
xcodebuild \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME}" \
  -configuration Release \
  -derivedDataPath "${RELEASE_DERIVED_DATA_DIR}" \
  SYMROOT="${RELEASE_BUILD_DIR}" \
  build

if [[ ! -d "${APP_BUILD_PATH}" ]]; then
  echo "Expected app bundle not found at ${APP_BUILD_PATH}" >&2
  exit 1
fi

cp -R "${APP_BUILD_PATH}" "${APP_PATH}"

if [[ -n "${SIGNING_IDENTITY}" ]]; then
  echo "Signing ${APP_NAME}.app with ${SIGNING_IDENTITY}..."
  codesign \
    --force \
    --deep \
    --options runtime \
    --timestamp \
    --sign "${SIGNING_IDENTITY}" \
    "${APP_PATH}"
fi

echo "Preparing DMG staging directory..."
mkdir -p "${STAGING_DIR}"
cp -R "${APP_PATH}" "${STAGING_DIR}/"
ln -s /Applications "${STAGING_DIR}/Applications"

SIZE_MB="$(
  du -sm "${STAGING_DIR}" \
    | awk '{ print $1 + 20 }'
)"

echo "Creating writable DMG..."
hdiutil create \
  -volname "${VOLUME_NAME}" \
  -srcfolder "${STAGING_DIR}" \
  -fs HFS+ \
  -format UDRW \
  -size "${SIZE_MB}m" \
  "${TEMP_DMG_PATH}" \
  >/dev/null

echo "Mounting DMG for Finder layout..."
hdiutil attach "${TEMP_DMG_PATH}" -mountpoint "${MOUNT_ROOT}" -noautoopen -quiet

osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "${VOLUME_NAME}"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {120, 120, 700, 410}
    set theViewOptions to the icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 128
    set position of item "${APP_NAME}.app" of container window to {150, 150}
    set position of item "Applications" of container window to {430, 150}
    close
    open
    update without registering applications
    delay 2
  end tell
end tell
APPLESCRIPT

echo "Finalizing compressed DMG..."
hdiutil detach "${MOUNT_ROOT}" -quiet
hdiutil convert "${TEMP_DMG_PATH}" -format UDZO -imagekey zlib-level=9 -o "${DMG_PATH}" >/dev/null
rm -f "${TEMP_DMG_PATH}"

if [[ -n "${SIGNING_IDENTITY}" ]]; then
  echo "Signing DMG..."
  codesign \
    --force \
    --timestamp \
    --sign "${SIGNING_IDENTITY}" \
    "${DMG_PATH}"
fi

if [[ -n "${APPLE_ID}" && -n "${APPLE_TEAM_ID}" && -n "${APPLE_APP_PASSWORD}" ]]; then
  require_command xcrun

  echo "Submitting DMG for notarization..."
  xcrun notarytool submit "${DMG_PATH}" \
    --apple-id "${APPLE_ID}" \
    --team-id "${APPLE_TEAM_ID}" \
    --password "${APPLE_APP_PASSWORD}" \
    --wait

  echo "Stapling notarization ticket..."
  xcrun stapler staple "${DMG_PATH}"
fi

echo "Done: ${DMG_PATH}"
