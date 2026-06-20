set -euo pipefail
echo "Installing Prism Launcher..."
RELEASE_API="https://api.github.com/repos/PrismLauncher/PrismLauncher/releases/latest"
FALLBACK_URL="https://github.com/PrismLauncher/PrismLauncher/releases/download/11.0.2/PrismLauncher-Linux-Qt6-Portable-11.0.2.tar.gz"
APP_ROOT="$HOME/.local/prism"
BIN_DIR="$HOME/.local/bin"
EXTRACT_DIR="$APP_ROOT/portable"
LAUNCHER="$BIN_DIR/prismlauncher"
mkdir -p "$APP_ROOT" "$BIN_DIR"

URL="${'$'}{PRISM_URL:-}"
if [ -z "$URL" ]; then
  RELEASE_JSON="$APP_ROOT/latest-release.json"
  if curl -L --fail --max-time 30 -H "User-Agent: prism-bootstrap/1" -o "$RELEASE_JSON" "$RELEASE_API"; then
    URL="$(tr ',' '\n' < "$RELEASE_JSON" | sed -n 's/.*"browser_download_url": "\(https:[^"]*PrismLauncher-Linux-Qt6-Portable-[^"]*\.tar\.gz\)".*/\1/p' | sed -n '1p')"
    if [ -z "$URL" ]; then
      URL="$(tr ',' '\n' < "$RELEASE_JSON" | sed -n 's/.*"browser_download_url": "\(https:[^"]*PrismLauncher-Linux-x86_64\.AppImage\)".*/\1/p' | sed -n '1p')"
    fi
  else
    echo "Could not look up latest Prism release"
  fi
fi
URL="${'$'}{URL:-$FALLBACK_URL}"
ARCHIVE_NAME="${'$'}{URL%%\?*}"
ARCHIVE="$APP_ROOT/${'$'}{ARCHIVE_NAME##*/}"

if [ ! -s "$ARCHIVE" ] || [ "$(wc -c < "$ARCHIVE")" -lt 1048576 ]; then
  echo "Downloading Prism from $URL"
  TMP="$ARCHIVE.download"
  rm -f "$TMP"
  curl -L --fail --max-time 240 -H "User-Agent: prism-bootstrap/1" -o "$TMP" "$URL"
  mv "$TMP" "$ARCHIVE"
fi

echo "Prism archive: $ARCHIVE $(wc -c < "$ARCHIVE")"
rm -rf "$EXTRACT_DIR"
mkdir -p "$EXTRACT_DIR"
case "$ARCHIVE" in
  *.AppImage)
    chmod +x "$ARCHIVE"
    (cd "$EXTRACT_DIR" && "$ARCHIVE" --appimage-extract)
    ;;
  *)
    tar -xzf "$ARCHIVE" -C "$EXTRACT_DIR"
    ;;
esac

PRISM=""
for NAME in prismlauncher PrismLauncher prismlauncher.bin; do
  PRISM="$(find "$EXTRACT_DIR" -type f -name "$NAME" -print -quit)"
  if [ -n "$PRISM" ]; then
    break
  fi
done
if [ -z "$PRISM" ]; then
  echo "Error: could not find Prism executable after extraction" >&2
  exit 1
fi
chmod +x "$PRISM"
printf '#!/bin/sh\nexec "%s" "$@"\n' "$PRISM" > "$LAUNCHER"
chmod 755 "$LAUNCHER"
"$LAUNCHER" --version
echo "Prism is ready: $LAUNCHER"
