set -euo pipefail
export DISPLAY=:99
for _ in $(seq 1 1200); do
  if xdpyinfo -display :99 >/dev/null 2>&1; then
    break
  fi
  sleep 0.5
done
xdpyinfo -display :99 >/dev/null
HELPER="$(mktemp /tmp/cod-relative-mouse.XXXXXX.py)"
trap 'rm -f "$HELPER"' EXIT
cat > "$HELPER" <<'PY'
import ctypes
import sys

x11 = ctypes.cdll.LoadLibrary('libX11.so.6')
xtst = ctypes.cdll.LoadLibrary('libXtst.so.6')

XErrorHandler = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_void_p, ctypes.c_void_p)
XIOErrorHandler = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_void_p)

@XErrorHandler
def handle_x_error(display, event):
    print('Relative mouse X error', flush=True)
    return 0

@XIOErrorHandler
def handle_x_io_error(display):
    print('Relative mouse X IO error', flush=True)
    return 0

x11.XOpenDisplay.argtypes = [ctypes.c_char_p]
x11.XOpenDisplay.restype = ctypes.c_void_p
x11.XSync.argtypes = [ctypes.c_void_p, ctypes.c_int]
x11.XSync.restype = ctypes.c_int
x11.XSetErrorHandler.argtypes = [XErrorHandler]
x11.XSetErrorHandler.restype = ctypes.c_void_p
x11.XSetIOErrorHandler.argtypes = [XIOErrorHandler]
x11.XSetIOErrorHandler.restype = ctypes.c_void_p
xtst.XTestFakeRelativeMotionEvent.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_ulong]
xtst.XTestFakeRelativeMotionEvent.restype = ctypes.c_int
xtst.XTestFakeButtonEvent.argtypes = [ctypes.c_void_p, ctypes.c_uint, ctypes.c_int, ctypes.c_ulong]
xtst.XTestFakeButtonEvent.restype = ctypes.c_int

x11.XSetErrorHandler(handle_x_error)
x11.XSetIOErrorHandler(handle_x_io_error)
display = x11.XOpenDisplay(None)
if not display:
    raise SystemExit('could not open DISPLAY')

print('Relative mouse helper ready', flush=True)

def clamp(value):
    return max(-2000, min(2000, int(value)))

for line in sys.stdin:
    parts = line.split()
    if not parts:
        continue
    try:
        if parts[0] == 'm' and len(parts) == 3:
            dx = clamp(parts[1])
            dy = clamp(parts[2])
            if dx or dy:
                xtst.XTestFakeRelativeMotionEvent(display, dx, dy, 0, 0)
                x11.XSync(display, 0)
        elif parts[0] == 'b' and len(parts) == 3:
            button = max(1, min(7, int(parts[1])))
            down = 1 if int(parts[2]) else 0
            xtst.XTestFakeButtonEvent(display, button, down, 0)
            x11.XSync(display, 0)
    except Exception as exc:
        print('Relative mouse input error:', type(exc).__name__, exc, flush=True)
PY
exec python3 -u "$HELPER"
