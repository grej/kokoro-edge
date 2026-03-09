#!/bin/zsh

set -euo pipefail
setopt null_glob

SOURCE="${1:-}"
INSTALL_ROOT="${KOKORO_EDGE_INSTALL_ROOT:-$HOME/.local}"
BIN_DIR="$INSTALL_ROOT/bin"
LIB_DIR="$INSTALL_ROOT/lib"
TMP_DIR="$(mktemp -d)"
ARCHIVE_PATH="$TMP_DIR/kokoro-edge.tar.gz"
REPO="${KOKORO_EDGE_REPO:-}"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "kokoro-edge currently supports Apple Silicon only." >&2
  exit 1
fi

mkdir -p "$BIN_DIR" "$LIB_DIR"

download_latest_release() {
  if [[ -z "$REPO" ]]; then
    echo "Set KOKORO_EDGE_REPO=owner/repo or pass a release tarball path/URL to install.sh." >&2
    exit 1
  fi

  local api_url="https://api.github.com/repos/$REPO/releases/latest"
  local download_url
  download_url="$(curl -fsSL "$api_url" | sed -n 's/.*"browser_download_url":[[:space:]]*"\([^"]*kokoro-edge-[^"]*macos-arm64\.tar\.gz\)".*/\1/p' | head -n 1)"
  if [[ -z "$download_url" ]]; then
    echo "Unable to locate a kokoro-edge macOS arm64 release asset for $REPO." >&2
    exit 1
  fi

  curl -L --fail "$download_url" -o "$ARCHIVE_PATH"
}

if [[ -n "$SOURCE" ]]; then
  if [[ -f "$SOURCE" ]]; then
    cp "$SOURCE" "$ARCHIVE_PATH"
  else
    curl -L --fail "$SOURCE" -o "$ARCHIVE_PATH"
  fi
else
  download_latest_release
fi

tar -xzf "$ARCHIVE_PATH" -C "$TMP_DIR"

cp "$TMP_DIR/bin/kokoro-edge" "$BIN_DIR/kokoro-edge"
chmod +x "$BIN_DIR/kokoro-edge"

mkdir -p "$LIB_DIR"
rm -rf "$LIB_DIR"/*.framework
cp -R "$TMP_DIR/lib/." "$LIB_DIR/"
cp -R "$TMP_DIR/bin/"*.bundle "$BIN_DIR/"

if [[ -f "$HOME/.zshrc" ]]; then
  if ! grep -Fq 'export PATH="$HOME/.local/bin:$PATH"' "$HOME/.zshrc"; then
    printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$HOME/.zshrc"
    echo 'Added ~/.local/bin to PATH in ~/.zshrc'
  fi
else
  printf 'export PATH="$HOME/.local/bin:$PATH"\n' > "$HOME/.zshrc"
  echo 'Created ~/.zshrc and added ~/.local/bin to PATH'
fi

"$BIN_DIR/kokoro-edge" models pull kokoro-82m

echo "Installed kokoro-edge to $BIN_DIR/kokoro-edge"
