#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

APP_NAME="TypeLessBuddy"
SCHEME="TypeLessBuddy"
PROJECT_PATH="${REPO_ROOT}/TypeLessBuddy.xcodeproj"
CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED_DATA_DIR="${REPO_ROOT}/build/DerivedData-app"
APP_PATH="${DERIVED_DATA_DIR}/Build/Products/${CONFIGURATION}/${APP_NAME}.app"
BUILD_ARCHS="${BUILD_ARCHS:-$(uname -m)}"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "Missing required command: xcodebuild" >&2
  exit 1
fi

mkdir -p "${REPO_ROOT}/build"

echo "Building ${APP_NAME}.app (${CONFIGURATION}, ${BUILD_ARCHS})..."
xcodebuild \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -destination 'platform=macOS' \
  -derivedDataPath "${DERIVED_DATA_DIR}" \
  ARCHS="${BUILD_ARCHS}" \
  ONLY_ACTIVE_ARCH=YES \
  build

if [[ ! -d "${APP_PATH}" ]]; then
  echo "Expected app bundle not found at ${APP_PATH}" >&2
  exit 1
fi

echo "Done: ${APP_PATH}"
