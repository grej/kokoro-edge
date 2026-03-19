#!/bin/zsh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="${DIST_DIR:-$ROOT/dist}"
VERSION="${1:-$(sed -n 's/.*current = "\(.*\)".*/\1/p' "$ROOT/Sources/KokoroEdge/Version.swift")}"
ARCHIVE_NAME="kokoro-edge-${VERSION}-macos-arm64.tar.gz"
ARCHIVE_PATH="$DIST_DIR/$ARCHIVE_NAME"
CHECKSUM_PATH="$DIST_DIR/$ARCHIVE_NAME.sha256"

mkdir -p "$DIST_DIR"

"$ROOT/Scripts/build-source.sh"

codesign --sign - --force "$ROOT/.build-xcode/stage/bin/kokoro-edge"

rm -f "$ARCHIVE_PATH" "$CHECKSUM_PATH"
tar -C "$ROOT/.build-xcode/stage" -czf "$ARCHIVE_PATH" bin lib
shasum -a 256 "$ARCHIVE_PATH" > "$CHECKSUM_PATH"

echo "Release artifact:"
echo "$ARCHIVE_PATH"
echo "Checksum:"
echo "$CHECKSUM_PATH"
