<script lang="ts">
  import type { Attachment } from 'svelte/attachments';
  import cod from '../assets/cod-animation.webp';
  import firefoxIcon from '../assets/firefox.svg';
  import opencodeIcon from '../assets/opencode.svg';
  import prismIcon from '../assets/prism-launcher.svg';
  import type { SpawnSession } from './spawn';
  import TerminalWindow from './TerminalWindow.svelte';
  import {
    type TerminalLine,
    type TerminalWindow as TerminalWindowModel,
  } from './terminal';
  import { script as desktopEnvCommand } from './scripts/desktop-env.sh';
  import { script as firefoxInstallCommand } from './scripts/firefox.sh';
  import { script as prismInstallCommand } from './scripts/prism.sh';
  import { script as opencodeInstallCommand } from './scripts/opencode.sh';
  import { script as relativeMouseCommand } from './scripts/relm.sh';
  import { script as remoteProgram } from './scripts/remote.py';

  type RemoteWindow = {
    id: string;
    title: string;
  };

  type ScreenSize = {
    width: number;
    height: number;
  };

  type TaskTerminalOptions = {
    id: string;
    title: string;
    command: string;
    args?: string[];
    env?: Record<string, string | number>;
    type?: 'normal' | 'echopty';
    track?: boolean;
    onOutput?: (stream: TerminalLine['stream'], text: string) => void;
    onSuccess?: () => void;
    onFailure?: (error: Error) => void;
  };

  type Props = {
    uid: string;
    appWindow: Window;
    session: SpawnSession;
  };

  const NOVNC_SCRIPT_URL = 'https://static1.codehs.com/lib/noVNC/noVNC.js';
  const REMOTE_DISPLAY_MAX_WIDTH = 1920;
  const REMOTE_DISPLAY_MAX_HEIGHT = 1080;
  const REMOTE_WINDOWS = 'COD_WINDOWS ';
  const RELATIVE_MOUSE_ID = 'task-relative-mouse';
  const withDesktopEnv = (command: string) =>
    `${desktopEnvCommand}\n${command}`;
  let { uid, appWindow, session }: Props = $props();
  let loading = $state(true);
  let latestDisplaySize: ScreenSize | undefined;
  let displayResizeTimer = 0;
  let terminalOpen = $state(false);
  let activeTerminalTab = $state('tasks');
  let terminals = $state<TerminalWindowModel[]>([]);
  let remoteWindows = $state<RemoteWindow[]>([]);
  let firefoxInstalled = $state(false);
  let prismInstalled = $state(false);
  let opencodeInstalled = $state(false);
  let relativeMouseEnabled = $state(false);
  let showRelativeMouseHint = $state(false);
  let relativeMouseHintSeen = $state(false);
  let vncScreen: HTMLElement | undefined;
  let relativeMouseReady = false;
  let relativeMouseDx = 0;
  let relativeMouseDy = 0;
  let relativeMouseFlushTimer = 0;
  let relativeMouseHintTimer = 0;
  const taskOutputHandlers = new Map<
    string,
    NonNullable<TaskTerminalOptions['onOutput']>
  >();

  const openTerminalApp = (tab = activeTerminalTab) => {
    activeTerminalTab = tab;
    terminalOpen = true;
    appWindow.setTimeout(focusTerminalApp);
  };

  const closeTerminalApp = () => {
    terminalOpen = false;
  };

  const loadScript = (document: Document, src: string) =>
    new Promise<void>((resolve, reject) => {
      const existing = [...document.scripts].find(
        (script) => script.src === src,
      );
      if (existing) {
        resolve();
        return;
      }

      const script = document.createElement('script');
      script.src = src;
      script.onload = () => resolve();
      script.onerror = () => reject(new Error(`failed to load ${src}`));
      document.head.appendChild(script);
    });

  const getWindowDisplaySize = (): ScreenSize => ({
    width: Math.max(1, Math.round(appWindow.innerWidth)),
    height: Math.max(1, Math.round(appWindow.innerHeight)),
  });

  const observeDisplaySize = (onResize: (size: ScreenSize) => void) => {
    let timer = 0;
    let lastSize: ScreenSize | undefined;

    const emitResize = () => {
      timer = 0;
      const size = getWindowDisplaySize();
      if (lastSize?.width === size.width && lastSize.height === size.height)
        return;
      lastSize = size;
      onResize(size);
    };

    const scheduleResize = () => {
      if (timer) appWindow.clearTimeout(timer);
      timer = appWindow.setTimeout(emitResize);
    };

    appWindow.addEventListener('resize', scheduleResize);
    scheduleResize();

    return () => {
      appWindow.removeEventListener('resize', scheduleResize);
      if (timer) appWindow.clearTimeout(timer);
    };
  };

  const syncCanvasLogicalSize = (screen: HTMLElement) => {
    const canvas = screen.querySelector('canvas');
    if (!(canvas instanceof HTMLCanvasElement)) return;

    canvas.style.width = `${canvas.width}px`;
    canvas.style.height = `${canvas.height}px`;
    canvas.style.maxWidth = 'none';
    canvas.style.maxHeight = 'none';
    canvas.style.objectFit = 'fill';
  };

  const observeCanvasLogicalSize = (screen: HTMLElement) => {
    let canvasObserver: MutationObserver | undefined;

    const observeCanvas = () => {
      const canvas = screen.querySelector('canvas');
      if (!(canvas instanceof HTMLCanvasElement)) return false;

      canvasObserver?.disconnect();
      const observer = new MutationObserver(() =>
        syncCanvasLogicalSize(screen),
      );
      canvasObserver = observer;
      observer.observe(canvas, {
        attributes: true,
        attributeFilter: ['width', 'height'],
      });
      syncCanvasLogicalSize(screen);
      return true;
    };

    const screenObserver = new MutationObserver(() => {
      if (observeCanvas()) screenObserver.disconnect();
    });

    if (!observeCanvas()) {
      screenObserver.observe(screen, { childList: true, subtree: true });
    }
  };

  const flushRelativeMouse = () => {
    relativeMouseFlushTimer = 0;
    const dx = Math.round(relativeMouseDx);
    const dy = Math.round(relativeMouseDy);
    relativeMouseDx = 0;
    relativeMouseDy = 0;
    if (!relativeMouseReady) return;
    if (!dx && !dy) return;
    session.input(RELATIVE_MOUSE_ID, `m ${dx} ${dy}\n`);
  };

  const queueRelativeMouse = (dx: number, dy: number) => {
    relativeMouseDx += dx;
    relativeMouseDy += dy;
    if (!relativeMouseFlushTimer) {
      relativeMouseFlushTimer = appWindow.setTimeout(flushRelativeMouse, 8);
    }
  };

  const remoteButtonForMouseEvent = (event: MouseEvent) => {
    if (event.button === 0) return 1;
    if (event.button === 1) return 2;
    if (event.button === 2) return 3;
    return undefined;
  };

  const isRelativeMouseCandidateWindow = (window: RemoteWindow) => {
    const title = window.title.toLowerCase();
    return title.includes('minecraft');
  };

  const showRelativeMouseToast = () => {
    if (relativeMouseHintSeen || relativeMouseEnabled) return;
    relativeMouseHintSeen = true;
    showRelativeMouseHint = true;
    if (relativeMouseHintTimer) appWindow.clearTimeout(relativeMouseHintTimer);
    relativeMouseHintTimer = appWindow.setTimeout(() => {
      relativeMouseHintTimer = 0;
      showRelativeMouseHint = false;
    }, 6500);
  };

  const attachRelativeMouse = (screen: HTMLElement) => {
    const document = appWindow.document;

    const hasPointerLock = () => document.pointerLockElement === screen;

    const updatePointerLockState = () => {
      if (!hasPointerLock() && relativeMouseFlushTimer) {
        appWindow.clearTimeout(relativeMouseFlushTimer);
        flushRelativeMouse();
      }
      relativeMouseEnabled = hasPointerLock();
    };

    const requestPointerLock = (event: MouseEvent) => {
      if (!event.ctrlKey || event.button !== 0 || hasPointerLock()) return;
      screen.requestPointerLock();
      event.preventDefault();
      event.stopImmediatePropagation();
    };

    const handleMouseMove = (event: MouseEvent) => {
      if (!hasPointerLock()) return;
      queueRelativeMouse(event.movementX, event.movementY);
      event.preventDefault();
      event.stopImmediatePropagation();
    };

    const handleMouseButton = (event: MouseEvent) => {
      if (!hasPointerLock()) return;
      const button = remoteButtonForMouseEvent(event);
      if (button)
        session.input(
          RELATIVE_MOUSE_ID,
          `b ${button} ${event.type === 'mousedown' ? 1 : 0}\n`,
        );
      event.preventDefault();
      event.stopImmediatePropagation();
    };

    const handleContextMenu = (event: MouseEvent) => {
      if (!hasPointerLock()) return;
      event.preventDefault();
      event.stopImmediatePropagation();
    };

    screen.addEventListener('mousedown', requestPointerLock, { capture: true });
    document.addEventListener('mousemove', handleMouseMove, { capture: true });
    document.addEventListener('pointermove', handleMouseMove, {
      capture: true,
    });
    document.addEventListener('mousedown', handleMouseButton, {
      capture: true,
    });
    document.addEventListener('mouseup', handleMouseButton, { capture: true });
    document.addEventListener('contextmenu', handleContextMenu, {
      capture: true,
    });
    document.addEventListener('pointerlockchange', updatePointerLockState);

    return () => {
      screen.removeEventListener('mousedown', requestPointerLock, {
        capture: true,
      });
      document.removeEventListener('mousemove', handleMouseMove, {
        capture: true,
      });
      document.removeEventListener('pointermove', handleMouseMove, {
        capture: true,
      });
      document.removeEventListener('mousedown', handleMouseButton, {
        capture: true,
      });
      document.removeEventListener('mouseup', handleMouseButton, {
        capture: true,
      });
      document.removeEventListener('contextmenu', handleContextMenu, {
        capture: true,
      });
      document.removeEventListener('pointerlockchange', updatePointerLockState);
      if (relativeMouseFlushTimer)
        appWindow.clearTimeout(relativeMouseFlushTimer);
      relativeMouseFlushTimer = 0;
      relativeMouseEnabled = false;
    };
  };

  const connectRfb = (
    screen: HTMLElement,
    url: string,
    onConnect: () => void,
  ) => {
    let connected = false;
    let rfb: RfbClient | undefined;
    let reconnectTimer = 0;

    const connect = () => {
      const RFB = appWindow.RFB;
      if (!RFB) return;

      connected = false;
      reconnectTimer = 0;

      rfb = new RFB(screen, url, {});
      rfb.scaleViewport = false;
      rfb.resizeSession = false;
      rfb.clipViewport = true;
      rfb.focusOnClick = true;

      rfb.addEventListener('disconnect', (event) => {
        if (connected) console.warn('[rfb] disconnected', event);
        connected = false;
        if (!reconnectTimer)
          reconnectTimer = appWindow.setTimeout(connect, 1000);
      });

      rfb.addEventListener('connect', () => {
        connected = true;
        onConnect();
      });
    };

    connect();

    return () => {
      if (reconnectTimer) appWindow.clearTimeout(reconnectTimer);
      rfb?.disconnect();
    };
  };

  const resizeDisplay = (size: ScreenSize) => {
    const width = Math.min(size.width, REMOTE_DISPLAY_MAX_WIDTH);
    const height = Math.min(size.height, REMOTE_DISPLAY_MAX_HEIGHT);
    latestDisplaySize = { width, height };

    if (displayResizeTimer) appWindow.clearTimeout(displayResizeTimer);
    displayResizeTimer = appWindow.setTimeout(() => {
      displayResizeTimer = 0;
      const target = latestDisplaySize;
      if (!target) return;
      const command = `set -euo pipefail
WIDTH=${target.width}
HEIGHT=${target.height}
MODE="\${WIDTH}x\${HEIGHT}"
MODEL="$(gtf "$WIDTH" "$HEIGHT" 60 | sed -n -e 's/^.*"  //p')"
for _ in $(seq 1 1200); do
  if xdpyinfo -display :99 >/dev/null 2>&1 && xrandr -d :99 --query >/dev/null 2>&1; then
    xrandr -d :99 --newmode "$MODE" $MODEL >/dev/null 2>&1 || true
    xrandr -d :99 --addmode screen "$MODE" >/dev/null 2>&1 || true
    if xrandr -d :99 --output screen --mode "$MODE" >/dev/null 2>&1; then
      echo "Display resized to $MODE"
      exit 0
    fi
  fi
  sleep 0.5
done
xdpyinfo -display :99 >/dev/null
xrandr -d :99 --query >/dev/null
for _ in $(seq 1 10); do
  xrandr -d :99 --newmode "$MODE" $MODEL || true
  xrandr -d :99 --addmode screen "$MODE" || true
  if xrandr -d :99 --output screen --mode "$MODE"; then
    echo "Display resized to $MODE"
    break
  fi
  sleep 0.5
done
xrandr -d :99 --output screen --mode "$MODE" >/dev/null
`;
      startTaskTerminal({
        id: `task-display-resize-${Date.now()}`,
        title: `Resize display to ${target.width}x${target.height}`,
        command,
      });
    }, 120);
  };

  const updateRemoteWindows = (line: string) => {
    const json = line.slice(REMOTE_WINDOWS.length).trim();
    try {
      const windows = (JSON.parse(json) as RemoteWindow[]).filter(
        (window) =>
          typeof window.id === 'string' && typeof window.title === 'string',
      );
      const windowsById = new Map(windows.map((window) => [window.id, window]));
      const orderedWindows = remoteWindows
        .map((window) => windowsById.get(window.id))
        .filter((window): window is RemoteWindow => !!window);

      for (const window of windows) {
        if (
          !orderedWindows.some(
            (orderedWindow) => orderedWindow.id === window.id,
          )
        ) {
          orderedWindows.push(window);
        }
      }

      remoteWindows = orderedWindows;
      if (orderedWindows.some(isRelativeMouseCandidateWindow))
        showRelativeMouseToast();
    } catch (error) {
      console.warn('[wm] failed to parse windows', error, line);
    }
  };

  const transferDesktop = () => {
    return session.transfer({
      'main.py': remoteProgram,
    });
  };

  const spawnDesktop = (onDesktopWindowsReady: () => void) => {
    const command =
      'set -e\nsource "./.pyvenv311/bin/activate"\npython -B "$MAIN_FILE"';

    startTaskTerminal({
      id: 'task-desktop',
      title: 'Starting desktop',
      command,
      args: ['-i', '-c', command],
      type: 'echopty',
      env: {
        MAIN_FILE: 'main.py',
        DEBUG_MODE: 0,
      },
      track: false,
      onOutput: (_stream, text) => {
        for (const line of text.split('\n')) {
          if (line.startsWith(REMOTE_WINDOWS)) updateRemoteWindows(line);
          if (line.trim() === 'COD_WINDOWS []') onDesktopWindowsReady();
        }
      },
    });
  };

  const spawnRelativeMouse = () => {
    relativeMouseReady = false;
    startTaskTerminal({
      id: RELATIVE_MOUSE_ID,
      title: 'Relative mouse helper',
      command: relativeMouseCommand,
      args: ['-lc', relativeMouseCommand],
      type: 'echopty',
      track: false,
      onOutput: (_stream, text) => {
        if (text.includes('Relative mouse helper ready'))
          relativeMouseReady = true;
      },
    });
  };

  const startVnc = async (screen: HTMLElement) => {
    const url = `wss://scalinghub.codehs.com/user/${uid}/graphics`;
    let resolveDesktopWindowsReady: () => void = () => {};
    const desktopWindowsReady = new Promise<void>((resolve) => {
      resolveDesktopWindowsReady = resolve;
    });

    observeCanvasLogicalSize(screen);

    session.setOutputHandler((stream, data, id) => {
      const text = String(data ?? '');
      if (id && terminals.some((terminal) => terminal.id === id)) {
        appendTerminal(id, stream, text);
      }

      if (id) taskOutputHandlers.get(id)?.(stream, text);
      if (stream === 'stderr') console.warn('[spawn]', text);
    });

    observeDisplaySize(resizeDisplay);
    await transferDesktop();
    spawnDesktop(resolveDesktopWindowsReady);
    startTaskTerminal({
      id: 'task-firefox-install',
      title: 'Installing Firefox',
      command: firefoxInstallCommand,
      onSuccess: () => {
        firefoxInstalled = true;
        launchFirefox();
      },
    });
    startTaskTerminal({
      id: 'task-prism-install',
      title: 'Installing Prism Launcher',
      command: prismInstallCommand,
      onSuccess: () => {
        prismInstalled = true;
      },
    });
    startTaskTerminal({
      id: 'task-opencode-install',
      title: 'Installing opencode',
      command: opencodeInstallCommand,
      onSuccess: () => {
        opencodeInstalled = true;
      },
    });
    await loadScript(appWindow.document, NOVNC_SCRIPT_URL);
    if (!appWindow.RFB) throw new Error('noVNC RFB global did not load');

    await desktopWindowsReady;
    spawnRelativeMouse();
    connectRfb(screen, url, () => {
      loading = false;
      syncCanvasLogicalSize(screen);
    });
  };

  const attachVnc: Attachment<HTMLElement> = (screen) => {
    vncScreen = screen;
    const detachRelativeMouse = attachRelativeMouse(screen);
    void startVnc(screen);

    return () => {
      detachRelativeMouse();
      if (relativeMouseHintTimer)
        appWindow.clearTimeout(relativeMouseHintTimer);
      relativeMouseHintTimer = 0;
      showRelativeMouseHint = false;
      vncScreen = undefined;
    };
  };

  const focusVncScreen = () => {
    const canvas = vncScreen?.querySelector('canvas');
    if (canvas instanceof HTMLCanvasElement)
      canvas.focus({ preventScroll: true });
  };

  const focusTerminalApp = () => {
    const terminal = appWindow.document.querySelector<HTMLElement>(
      '[data-terminal-app]',
    );
    terminal?.focus({ preventScroll: true });
  };

  const shellsCount = () =>
    terminals.filter((terminal) => terminal.kind === 'terminal').length;

  const hasRemoteWindowNamed = (name: string) =>
    remoteWindows.some((window) => window.title.toLowerCase().includes(name));

  const launchFirefox = () => {
    if (!firefoxInstalled) return;
    startTaskTerminal({
      id: `task-firefox-launch-${Date.now()}`,
      title: 'Launching Firefox',
      command: `set -euo pipefail
BROWSER="$HOME/.local/firefox/firefox"
for _ in $(seq 1 1200); do
  if xdpyinfo -display :99 >/dev/null 2>&1 && xprop -root _NET_SUPPORTING_WM_CHECK >/dev/null 2>&1; then
    break
  fi
  sleep 0.5
done
[ -x "$BROWSER" ]
xdpyinfo -display :99 >/dev/null
xprop -root _NET_SUPPORTING_WM_CHECK >/dev/null
"$BROWSER" about:blank`,
    });
  };

  const launchPrism = () => {
    if (!prismInstalled) return;
    startTaskTerminal({
      id: `task-prism-launch-${Date.now()}`,
      title: 'Launching Prism Launcher',
      command: `set -euo pipefail
PRISM="$HOME/.local/bin/prismlauncher"
export QT_XCB_GL_INTEGRATION="\${QT_XCB_GL_INTEGRATION:-none}"
export QT_LOGGING_RULES="\${QT_LOGGING_RULES:-qt.qpa.*=true}"
export LIBGL_ALWAYS_SOFTWARE="\${LIBGL_ALWAYS_SOFTWARE:-1}"
export MESA_LOADER_DRIVER_OVERRIDE="\${MESA_LOADER_DRIVER_OVERRIDE:-llvmpipe}"
for _ in $(seq 1 1200); do
  if xdpyinfo -display :99 >/dev/null 2>&1 && xprop -root _NET_SUPPORTING_WM_CHECK >/dev/null 2>&1; then
    break
  fi
  sleep 0.5
done
[ -x "$PRISM" ]
xdpyinfo -display :99 >/dev/null
xprop -root _NET_SUPPORTING_WM_CHECK >/dev/null
"$PRISM" \${PRISM_ARGS:-}`,
    });
  };

  const launchOpencode = () => {
    if (!opencodeInstalled) return;
    startTaskTerminal({
      id: `task-opencode-launch-${Date.now()}`,
      title: 'Launching opencode',
      command: `set -euo pipefail
OPENCODE="$HOME/.local/bin/opencode"
for _ in $(seq 1 1200); do
  if xdpyinfo -display :99 >/dev/null 2>&1 && xprop -root _NET_SUPPORTING_WM_CHECK >/dev/null 2>&1; then
    break
  fi
  sleep 0.5
done
[ -x "$OPENCODE" ]
xdpyinfo -display :99 >/dev/null
xprop -root _NET_SUPPORTING_WM_CHECK >/dev/null
"$OPENCODE" web`,
    });
  };

  const launcherApps = [
    {
      id: 'firefox',
      name: 'Firefox',
      icon: firefoxIcon,
      isInstalled: () => firefoxInstalled,
      isRunning: () => hasRemoteWindowNamed('firefox'),
      launch: launchFirefox,
    },
    {
      id: 'prism',
      name: 'Prism Launcher',
      icon: prismIcon,
      isInstalled: () => prismInstalled,
      isRunning: () => hasRemoteWindowNamed('prism'),
      launch: launchPrism,
    },
    {
      id: 'opencode',
      name: 'opencode',
      icon: opencodeIcon,
      isInstalled: () => opencodeInstalled,
      isRunning: () => hasRemoteWindowNamed('opencode'),
      launch: launchOpencode,
    },
  ];

  const launchTerminal = () => {
    const id = `terminal-${Date.now()}`;
    terminals = [
      ...terminals,
      {
        id,
        title: `Bash ${shellsCount() + 1}`,
        kind: 'terminal',
        running: true,
        started: true,
        failed: false,
        collapsed: false,
        lines: [],
      },
    ];
    activeTerminalTab = id;
    openTerminalApp(id);

    const command = withDesktopEnv('exec bash -l');
    session.spawnCommand(id, command, {
      type: 'echopty',
      args: ['-lc', command],
      untracked: true,
    });
  };

  const focusRemoteWindow = (window: RemoteWindow) => {
    if (session) {
      const windowId = JSON.stringify(window.id);
      startTaskTerminal({
        id: `task-focus-${Date.now()}`,
        title: `Focus ${window.title}`,
        command: `python -B - <<'PY'
import ctypes
import time

window_id = ${windowId}
if not window_id.startswith('0x'):
    raise SystemExit(0)

class ClientMessageData(ctypes.Union):
    _fields_ = [
        ('b', ctypes.c_char * 20),
        ('s', ctypes.c_short * 10),
        ('l', ctypes.c_long * 5),
    ]

class XClientMessageEvent(ctypes.Structure):
    _fields_ = [
        ('type', ctypes.c_int),
        ('serial', ctypes.c_ulong),
        ('send_event', ctypes.c_int),
        ('display', ctypes.c_void_p),
        ('window', ctypes.c_ulong),
        ('message_type', ctypes.c_ulong),
        ('format', ctypes.c_int),
        ('data', ClientMessageData),
    ]

class XEvent(ctypes.Union):
    _fields_ = [
        ('type', ctypes.c_int),
        ('xclient', XClientMessageEvent),
        ('pad', ctypes.c_long * 24),
    ]

x11 = ctypes.cdll.LoadLibrary('libX11.so.6')
x11.XOpenDisplay.argtypes = [ctypes.c_char_p]
x11.XOpenDisplay.restype = ctypes.c_void_p
x11.XDefaultRootWindow.argtypes = [ctypes.c_void_p]
x11.XDefaultRootWindow.restype = ctypes.c_ulong
x11.XInternAtom.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int]
x11.XInternAtom.restype = ctypes.c_ulong
x11.XSendEvent.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_int, ctypes.c_long, ctypes.POINTER(XEvent)]
x11.XSendEvent.restype = ctypes.c_int
x11.XRaiseWindow.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
x11.XRaiseWindow.restype = ctypes.c_int
x11.XFlush.argtypes = [ctypes.c_void_p]
x11.XFlush.restype = ctypes.c_int
x11.XCloseDisplay.argtypes = [ctypes.c_void_p]
x11.XCloseDisplay.restype = ctypes.c_int

display = x11.XOpenDisplay(None)
if not display:
    raise SystemExit(0)
try:
    window = int(window_id, 16)
    root = x11.XDefaultRootWindow(display)
    active_window = x11.XInternAtom(display, b'_NET_ACTIVE_WINDOW', False)
    event = XEvent()
    event.xclient.type = 33
    event.xclient.display = display
    event.xclient.window = window
    event.xclient.message_type = active_window
    event.xclient.format = 32
    event.xclient.data.l[0] = 1
    event.xclient.data.l[1] = int(time.time())
    x11.XSendEvent(display, root, False, 0x00100000 | 0x00080000, ctypes.byref(event))
    x11.XRaiseWindow(display, window)
    x11.XFlush(display)
finally:
    x11.XCloseDisplay(display)
PY`,
      });
    }
    appWindow.setTimeout(focusVncScreen);
  };

  const appendTerminal = (
    id: string,
    stream: TerminalLine['stream'],
    text: string,
  ) => {
    terminals = terminals.map((terminal) =>
      terminal.id === id
        ? {
            ...terminal,
            running:
              stream === 'system' && text.includes('exited')
                ? false
                : terminal.running,
            lines: [...terminal.lines, { stream, text }].slice(-500),
          }
        : terminal,
    );
  };

  const markTerminalFinished = (id: string, failed: boolean, text: string) => {
    terminals = terminals.map((terminal) =>
      terminal.id === id
        ? {
            ...terminal,
            running: false,
            failed,
            collapsed: true,
            lines: [
              ...terminal.lines,
              { stream: 'system' as const, text },
            ].slice(-500),
          }
        : terminal,
    );
  };

  const startTaskTerminal = ({
    id,
    title,
    command,
    args,
    env,
    type,
    track = true,
    onOutput,
    onSuccess,
    onFailure,
  }: TaskTerminalOptions) => {
    if (terminals.some((terminal) => terminal.id === id)) {
      throw new Error(`cannot start ${id}: terminal already exists`);
    }
    const marker = `COD_TASK_EXIT ${id} `;
    const commandWithDesktopEnv = withDesktopEnv(command);
    const wrappedCommand = `set +e\n(\n${commandWithDesktopEnv}\n)\ncode=$?\necho "${marker}$code"\nexit 0`;
    const spawnCommand = track ? wrappedCommand : commandWithDesktopEnv;
    const spawnArgs = args
      ? args.map((arg) => (arg === command ? commandWithDesktopEnv : arg))
      : ['-lc', spawnCommand];

    terminals = [
      ...terminals,
      {
        id,
        title,
        kind: 'task',
        running: true,
        started: true,
        failed: false,
        collapsed: true,
        lines: [],
      },
    ];
    if (onOutput) taskOutputHandlers.set(id, onOutput);

    let result: Promise<void> | undefined;
    try {
      result = session.spawnCommand(id, spawnCommand, {
        type: type ?? 'echopty',
        args: spawnArgs,
        env,
        untracked: !track,
        resolveOnOutput: (text) => text.includes(`${marker}0`),
        rejectOnOutput: (text) => {
          const match = text.match(new RegExp(`${marker}(\\d+)`));
          if (!match || match[1] === '0') return undefined;
          return new Error(`${title} exited with code ${match[1]}`);
        },
      });
    } catch (error) {
      taskOutputHandlers.delete(id);
      const spawnError =
        error instanceof Error ? error : new Error(String(error));
      markTerminalFinished(
        id,
        true,
        `\nTask failed to start: ${spawnError.message}\n`,
      );
      onFailure?.(spawnError);
      return;
    }

    result
      ?.then(() => {
        taskOutputHandlers.delete(id);
        markTerminalFinished(id, false, '\nTask completed successfully.\n');
        onSuccess?.();
      })
      .catch((error: Error) => {
        taskOutputHandlers.delete(id);
        markTerminalFinished(id, true, `\nTask failed: ${error.message}\n`);
        onFailure?.(error);
      });
  };

  const selectTerminalTab = (id: string) => {
    activeTerminalTab = id;
    openTerminalApp(id);
  };

  const toggleTask = (id: string) => {
    terminals = terminals.map((terminal) =>
      terminal.id === id
        ? {
            ...terminal,
            collapsed: !terminal.collapsed,
          }
        : terminal,
    );
  };

  const sendTerminalInput = (id: string, input: string) => {
    session?.input(id, input);
  };
</script>

<div class="screen" {@attach attachVnc}></div>

{#if showRelativeMouseHint || relativeMouseEnabled}
  <div class:active={relativeMouseEnabled} class="mouse-lock-hint">
    {relativeMouseEnabled
      ? 'Relative mouse active. Press Esc to release.'
      : 'Game detected. Ctrl+click the desktop for relative mouse.'}
  </div>
{/if}

<TerminalWindow
  {terminals}
  open={terminalOpen}
  activeTab={activeTerminalTab}
  onClose={closeTerminalApp}
  onSelectTab={selectTerminalTab}
  onToggleTask={toggleTask}
  onNewTerminal={launchTerminal}
  onInput={sendTerminalInput}
/>

<div class:force-expand={loading} class="bar-anchor">
  <nav class="bar" aria-label="Open windows">
    {#each remoteWindows as window (window.id)}
      <button
        class="app-entry alive m3-layer"
        type="button"
        title={window.title}
        onclick={() => focusRemoteWindow(window)}
      >
        <span>{window.title}</span>
      </button>
    {/each}
    <button
      class="app-entry m3-layer"
      class:alive={terminalOpen || terminals.length > 0}
      type="button"
      title="Terminal"
      onclick={() => openTerminalApp()}
    >
      <span>Terminal</span>
    </button>
    {#each launcherApps as app (app.id)}
      {#if app.isInstalled() && !app.isRunning()}
        <button
          class="app-entry launcher m3-layer"
          type="button"
          title={`Launch ${app.name}`}
          aria-label={`Launch ${app.name}`}
          onclick={app.launch}
        >
          {@html app.icon}
          <span>{app.name}</span>
        </button>
      {/if}
    {/each}
  </nav>
</div>

<div class:hidden={!loading} class="loader">
  <img src={cod} alt="Loading Cod" />
</div>

<style>
  .screen {
    position: absolute;
    z-index: 10;
    inset: 0;
    overflow: visible;

    :global(canvas) {
      max-width: none;
      max-height: none;
      object-fit: none;
    }
  }

  .mouse-lock-hint {
    position: fixed;
    z-index: 120;
    top: 0.75rem;
    left: 50%;
    max-width: calc(100vw - 1.5rem);
    border-radius: 999px;
    padding: 0.45rem 0.75rem;
    background: color-mix(
      in srgb,
      var(--m3c-surface-container-highest) 88%,
      transparent
    );
    color: var(--m3c-on-surface);
    font-size: 0.8125rem;
    font-weight: 650;
    opacity: 0.9;
    pointer-events: none;
    translate: -50% 0;
    animation: mouse-lock-hint-in 180ms ease-out;
    box-shadow: 0 0.375rem 1.5rem rgb(0 0 0 / 0.18);

    &.active {
      background: var(--m3c-primary-container);
      color: var(--m3c-on-primary-container);
      opacity: 1;
    }
  }

  @keyframes mouse-lock-hint-in {
    from {
      opacity: 0;
      transform: translateY(-0.35rem);
    }

    to {
      opacity: 0.9;
      transform: translateY(0);
    }
  }

  .bar-anchor {
    display: contents;
    --transition: 220ms cubic-bezier(0.2, 0, 0, 1);
  }

  .bar {
    position: fixed;
    z-index: 100;
    bottom: 0;
    left: 50%;
    display: flex;
    align-items: center;
    gap: 0.25rem;
    width: max-content;
    max-width: calc(100vw - 1rem);
    height: 2.25rem;
    overflow: visible;
    padding: 0.25rem;
    background: transparent;
    translate: -50% 0;
    transition:
      height var(--transition),
      width var(--transition),
      padding var(--transition),
      border-radius var(--transition);

    &::after {
      position: absolute;
      bottom: 0.1875rem;
      left: 50%;
      width: 2.75rem;
      height: 0.25rem;
      border-radius: 999px;
      background: var(--m3c-primary-container);
      content: '';
      translate: -50% 0;
      transition:
        opacity var(--transition),
        visibility var(--transition);
    }
  }

  .bar-anchor:not(:hover, :focus-within, .force-expand) > .bar {
    width: 3.5rem;
    height: 0.75rem;
    padding: 0;
  }

  .bar-anchor:is(:hover, :focus-within, .force-expand) > .bar::after {
    visibility: hidden;
    opacity: 0;
  }

  .bar-anchor:not(:hover, :focus-within, .force-expand) > .bar > button {
    width: 0;
    min-width: 0;
    padding-inline: 0;
    visibility: hidden;
  }

  .bar button {
    position: relative;
    display: flex;
    align-items: center;
    justify-content: center;
    min-width: 5.25rem;
    max-width: 10rem;
    height: 1.75rem;
    border: 0;
    border-radius: 0.5rem;
    padding: 0 0.625rem;
    background: var(--m3c-surface-container-low);
    color: var(--m3c-on-surface);
    text-align: center;
    cursor: pointer;
    transition:
      width var(--transition),
      min-width var(--transition),
      padding var(--transition),
      background 120ms;

    &:hover {
      background: var(--m3c-surface-container-high);
    }

    &.alive::after {
      position: absolute;
      bottom: 0.2rem;
      left: 50%;
      width: 0.25rem;
      height: 0.25rem;
      border-radius: 999px;
      background: currentColor;
      content: '';
      opacity: 0.75;
      translate: -50% 0;
    }

    span {
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
      font-weight: 650;
      line-height: 1.1;
    }

    &.launcher {
      width: 2rem;
      min-width: 2rem;
      padding: 0;

      :global(svg) {
        width: 1.25rem;
        height: 1.25rem;
        object-fit: contain;
        pointer-events: none;
      }

      span {
        position: absolute;
        width: 1px;
        height: 1px;
        overflow: hidden;
        clip: rect(0 0 0 0);
        white-space: nowrap;
      }
    }
  }

  .loader {
    position: absolute;
    z-index: 60;
    inset: 0;
    display: grid;
    place-items: center;
    align-content: center;
    gap: 1rem;
    background: var(--m3c-surface-container-lowest);
    transition: opacity 140ms;

    &.hidden {
      visibility: hidden;
      opacity: 0;
    }

    img {
      width: min(50vw, 50vh, 24rem);
      height: auto;
    }
  }
</style>
