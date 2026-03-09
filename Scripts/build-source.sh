#!/bin/zsh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_ROOT="${BUILD_ROOT:-$ROOT/.build-xcode}"
DERIVED_DATA="$BUILD_ROOT/DerivedData"
SOURCE_PACKAGES="$BUILD_ROOT/SourcePackages"
PACKAGE_CACHE="$BUILD_ROOT/PackageCache"
STAGE_ROOT="$BUILD_ROOT/stage"
BIN_DIR="$STAGE_ROOT/bin"
LIB_DIR="$STAGE_ROOT/lib"
PRODUCTS_DIR="$DERIVED_DATA/Build/Products/Release"

mkdir -p "$DERIVED_DATA" "$SOURCE_PACKAGES" "$PACKAGE_CACHE"

cd "$ROOT"

xcodebuild build \
  -configuration Release \
  -scheme kokoro-edge \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$DERIVED_DATA" \
  -clonedSourcePackagesDirPath "$SOURCE_PACKAGES" \
  -packageCachePath "$PACKAGE_CACHE" \
  -skipPackageUpdates

rm -rf "$BIN_DIR" "$LIB_DIR"
mkdir -p "$BIN_DIR" "$LIB_DIR"

ditto "$PRODUCTS_DIR/kokoro-edge" "$BIN_DIR/kokoro-edge"

for bundle in "$PRODUCTS_DIR"/*.bundle; do
  ditto "$bundle" "$BIN_DIR/$(basename "$bundle")"
done

for framework in "$PRODUCTS_DIR/PackageFrameworks"/*.framework; do
  ditto "$framework" "$LIB_DIR/$(basename "$framework")"
done

echo "Built source artifact:"
echo "$BIN_DIR/kokoro-edge"
