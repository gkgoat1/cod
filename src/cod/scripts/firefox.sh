set -euo pipefail
echo "Installing Firefox..."
export PATH="$HOME/.local/bin:$PATH"
BIN_DIR="$HOME/.local/bin"
APP_DIR="$HOME/.local"
APPLICATIONS_DIR="$HOME/.local/share/applications"
mkdir -p "$BIN_DIR" "$APP_DIR" "$APPLICATIONS_DIR"
BROWSER="$APP_DIR/firefox/firefox"
BROWSER_BIN="$APP_DIR/firefox/firefox-bin"
DESKTOP_FILE="$APPLICATIONS_DIR/firefox.desktop"

if [ ! -x "$BROWSER" ]; then
  ARCHIVE="/tmp/firefox.tar.xz"
  EXTRACT_DIR="$(mktemp -d "$APP_DIR/firefox-install.XXXXXX")"
  URL="https://download.mozilla.org/?product=firefox-latest-ssl&os=linux64&lang=en-US"
  cleanup() {
    rm -rf "$EXTRACT_DIR"
  }
  trap cleanup EXIT
  echo "Downloading Firefox from Mozilla..."
  curl -L --fail --retry 2 --max-time 90 -o "$ARCHIVE" "$URL"
  echo "Extracting Firefox..."
  tar -xf "$ARCHIVE" -C "$EXTRACT_DIR"
  rm -rf "$APP_DIR/firefox"
  mv "$EXTRACT_DIR/firefox" "$APP_DIR/firefox"
fi

ln -sfn "$BROWSER" "$BIN_DIR/firefox"
cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Encoding=UTF-8
Version=1.0
Type=Application
NoDisplay=true
Exec=$BROWSER_BIN %u
Name=Firefox
Comment=Custom definition for Firefox
Icon=$APP_DIR/firefox/browser/chrome/icons/default/default128.png
MimeType=x-scheme-handler/http;x-scheme-handler/https;x-scheme-handler/chrome;text/html;application/x-extension-htm;application/x-extension-html;application/x-extension-shtml;application/xhtml+xml;application/x-extension-xhtml;application/x-extension-xht;
StartupWMClass=firefox
EOF
chmod 644 "$DESKTOP_FILE"
mkdir -p "$HOME/.config"
MIMEAPPS="$HOME/.config/mimeapps.list"
cat > "$MIMEAPPS" <<EOF
[Default Applications]
x-scheme-handler/http=firefox.desktop
x-scheme-handler/https=firefox.desktop
x-scheme-handler/chrome=firefox.desktop
text/html=firefox.desktop
application/x-extension-htm=firefox.desktop
application/x-extension-html=firefox.desktop
application/x-extension-shtml=firefox.desktop
application/xhtml+xml=firefox.desktop
application/x-extension-xhtml=firefox.desktop
application/x-extension-xht=firefox.desktop

[Added Associations]
x-scheme-handler/http=firefox.desktop;
x-scheme-handler/https=firefox.desktop;
x-scheme-handler/chrome=firefox.desktop;
text/html=firefox.desktop;
application/x-extension-htm=firefox.desktop;
application/x-extension-html=firefox.desktop;
application/x-extension-shtml=firefox.desktop;
application/xhtml+xml=firefox.desktop;
application/x-extension-xhtml=firefox.desktop;
application/x-extension-xht=firefox.desktop;
EOF

"$BROWSER" --version
echo "Firefox is ready: $BROWSER"
