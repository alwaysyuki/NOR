#!/bin/bash
set -euo pipefail

# ==============================================================================
# NŌR - Release Packaging Script
# Compiles a Release build of NŌR.app and creates a compressed .zip distribution
# ==============================================================================

PROJECT_NAME="Wallpaper engine"
SCHEME_NAME="Wallpaper engine"
APP_NAME="NŌR"
TEMP_BUILD_DIR="/tmp/nor-build-$(date +%s)"
RELEASE_DIR="$(pwd)/release"

echo "==> Cleaning release directory..."
rm -rf "${RELEASE_DIR}"
mkdir -p "${RELEASE_DIR}"

# Strip macOS extended attributes / quarantine flags that can interfere with codesign
echo "==> Stripping extended attributes (xattr)..."
xattr -cr . 2>/dev/null || true

echo "==> Building ${APP_NAME} (Release)..."
xcodebuild \
    -project "${PROJECT_NAME}.xcodeproj" \
    -scheme "${SCHEME_NAME}" \
    -configuration Release \
    -derivedDataPath "${TEMP_BUILD_DIR}" \
    build

APP_PATH="${TEMP_BUILD_DIR}/Build/Products/Release/${PROJECT_NAME}.app"

if [ ! -d "${APP_PATH}" ]; then
    echo "Error: Application bundle not found at ${APP_PATH}"
    rm -rf "${TEMP_BUILD_DIR}"
    exit 1
fi

echo "==> Packaging application..."
cp -R "${APP_PATH}" "${RELEASE_DIR}/${APP_NAME}.app"
xattr -cr "${RELEASE_DIR}/${APP_NAME}.app" 2>/dev/null || true

cd "${RELEASE_DIR}"
zip -r -y -q "${APP_NAME}-macOS.zip" "${APP_NAME}.app"
shasum -a 256 "${APP_NAME}-macOS.zip" > "${APP_NAME}-macOS.zip.sha256"

# Clean temporary build directory
rm -rf "${TEMP_BUILD_DIR}"

echo "=================================================================="
echo "==> Release packaging complete!"
echo "Artifact:  ${RELEASE_DIR}/${APP_NAME}-macOS.zip"
echo "Checksum:  $(cat ${RELEASE_DIR}/${APP_NAME}-macOS.zip.sha256)"
echo "=================================================================="
