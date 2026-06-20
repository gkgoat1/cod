export DISPLAY=:99
export XDG_RUNTIME_DIR="$HOME/.local/run"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"
if [ -r "$HOME/.cod-desktop-env" ]; then
  . "$HOME/.cod-desktop-env"
fi
export NO_AT_BRIDGE=1
export GTK_A11Y=none
export GTK_MODULES=
export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"