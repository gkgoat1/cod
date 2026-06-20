set -euo pipefail
echo "Installing opencode..."
URL="https://github.com/anomalyco/opencode/releases/latest/download/opencode-linux-x64.tar.gz"
BIN_DIR="$HOME/.local/bin"
APP_DIR="$HOME/.local/opencode"
TARGET="$BIN_DIR/opencode"
ARCHIVE="$(mktemp /tmp/opencode-linux-x64.XXXXXX.tar.gz)"
EXTRACT_DIR="$(mktemp -d /tmp/opencode-install.XXXXXX)"
mkdir -p "$BIN_DIR" "$APP_DIR"
cleanup() {
  rm -rf "$ARCHIVE" "$EXTRACT_DIR"
}
trap cleanup EXIT

echo "Downloading latest opencode from $URL..."
curl -L --fail --retry 2 --max-time 180 -o "$ARCHIVE" "$URL"

echo "Extracting opencode..."
tar -xzf "$ARCHIVE" -C "$EXTRACT_DIR"
if [ ! -f "$EXTRACT_DIR/opencode" ]; then
  echo "Error: opencode archive did not contain a root opencode executable" >&2
  exit 1
fi
cp "$EXTRACT_DIR/opencode" "$TARGET"
chmod 755 "$TARGET"
"$TARGET" --version
echo "opencode is ready: $TARGET"
