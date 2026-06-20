import json
import os
import shutil
import subprocess
import sys
import threading
import tempfile
import textwrap
import time

HOME = os.environ.get('HOME') or '/home/karel'
BIN_DIR = os.path.join(HOME, '.local', 'bin')
WM_DIR = os.path.join(HOME, '.local', 'codehs-wm')
RUNTIME_DIR = os.path.join(HOME, '.local', 'run')
DESKTOP_ENV_FILE = os.path.join(HOME, '.cod-desktop-env')
DBUS_BUS_PATH = os.path.join(RUNTIME_DIR, 'bus')
DBUS_BUS_ADDRESS = 'unix:path=' + DBUS_BUS_PATH
os.makedirs(BIN_DIR, exist_ok=True)
os.makedirs(WM_DIR, exist_ok=True)
os.makedirs(RUNTIME_DIR, exist_ok=True)
os.chmod(RUNTIME_DIR, 0o700)
os.environ['PATH'] = BIN_DIR + ':' + os.environ.get('PATH', '')
os.environ['DISPLAY'] = ':99'
os.environ['XDG_RUNTIME_DIR'] = RUNTIME_DIR
os.environ['DBUS_SESSION_BUS_ADDRESS'] = DBUS_BUS_ADDRESS
os.environ['NO_AT_BRIDGE'] = '1'
os.environ['GTK_A11Y'] = 'none'
os.environ['GTK_MODULES'] = ''

GRAPHICS_WIDTH = 1920
GRAPHICS_HEIGHT = 1080

def say(*parts):
    print(*parts, flush=True)

def say_block(label, text):
    if not text:
        return
    print(label, flush=True)
    print(text[:2000].rstrip(), flush=True)

def run(cmd, timeout=60, cwd=None, env=None, quiet=False):
    if not quiet:
        say('$', ' '.join(cmd))
    try:
        p = subprocess.run(cmd, text=True, capture_output=True, timeout=timeout, cwd=cwd, env=env)
        if not quiet:
            say('Command finished with exit code', p.returncode)
        if not quiet:
            say_block('Output:', p.stdout)
            say_block('Errors:', p.stderr)
        return p.returncode == 0, p.stdout, p.stderr
    except Exception as exc:
        if not quiet:
            say('Command failed:', type(exc).__name__, str(exc))
        return False, '', str(exc)

def sh_quote(value):
    return "'" + value.replace("'", "'\"'\"'") + "'"

def write_desktop_env():
    with open(DESKTOP_ENV_FILE, 'w') as f:
        for key in ['DISPLAY', 'XDG_RUNTIME_DIR', 'DBUS_SESSION_BUS_ADDRESS', 'NO_AT_BRIDGE', 'GTK_A11Y', 'GTK_MODULES']:
            f.write('export {}={}\n'.format(key, sh_quote(os.environ.get(key, ''))))

def start_session_bus():
    run(['pkill', '-f', 'dbus-daemon --session --address=' + DBUS_BUS_ADDRESS], timeout=5, quiet=True)
    try:
        os.remove(DBUS_BUS_PATH)
    except FileNotFoundError:
        pass
    except Exception as exc:
        say('Warning: could not remove stale D-Bus socket', type(exc).__name__, str(exc))

    start_background(
        ['dbus-daemon', '--session', '--address=' + DBUS_BUS_ADDRESS, '--nofork', '--nopidfile'],
        '/tmp/cod-dbus.log',
    )
    deadline = time.time() + 5
    while time.time() < deadline:
        if os.path.exists(DBUS_BUS_PATH):
            say('Session D-Bus is ready:', DBUS_BUS_ADDRESS)
            return
        time.sleep(0.1)
    say('Warning: session D-Bus socket did not appear')

def download(url, path, timeout=120):
    return run(['curl', '-L', '--fail', '--max-time', str(timeout - 20), '-o', path, url], timeout=timeout)[0]

def extract_jwm():
    candidate = os.path.join(WM_DIR, 'usr', 'bin', 'jwm')
    if os.path.exists(candidate):
        return candidate
    deb = os.path.join(tempfile.mkdtemp(prefix='cod-jwm-'), 'jwm.deb')
    urls = [
        'https://mirrors.kernel.org/ubuntu/pool/universe/j/jwm/jwm_2.4.0-2_amd64.deb',
        'https://archive.ubuntu.com/ubuntu/pool/universe/j/jwm/jwm_2.4.0-2_amd64.deb',
    ]
    for url in urls:
        if download(url, deb, 90):
            ok, _out, _err = run(['dpkg-deb', '-x', deb, WM_DIR], timeout=60)
            if ok and os.path.exists(candidate):
                os.chmod(candidate, os.stat(candidate).st_mode | 0o111)
                return candidate
    return None

def start_background(cmd, log_path, cwd=None):
    log = open(log_path, 'ab', buffering=0)
    return subprocess.Popen(
        cmd,
        cwd=cwd,
        stdin=subprocess.DEVNULL,
        stdout=log,
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )

def wait_for_display(timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        ok, _out, _err = run(['xdpyinfo', '-display', ':99'], timeout=2, quiet=True)
        if ok:
            return True
        time.sleep(0.25)
    return False

def restart_graphics_stack():
    say('Restarting graphics stack at', f'{GRAPHICS_WIDTH}x{GRAPHICS_HEIGHT}')
    for pattern in [
        'websockify 1337 :5900',
        'x11vnc .* -display :99',
        '/usr/bin/Xvfb :99',
    ]:
        run(['pkill', '-f', pattern], timeout=5, quiet=True)
    time.sleep(1)
    for path in ['/tmp/.X99-lock', '/tmp/.X11-unix/X99']:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
        except Exception as exc:
            say('Warning: could not remove display lock', path, type(exc).__name__, str(exc))

    start_background(
        [
            '/usr/bin/Xvfb',
            ':99',
            '-screen',
            '0',
            f'{GRAPHICS_WIDTH}x{GRAPHICS_HEIGHT}x16',
            '-ac',
            '+extension',
            'GLX',
            '+extension',
            'RANDR',
        ],
        '/tmp/cod-xvfb.log',
    )
    if not wait_for_display():
        say('Error: Xvfb display did not become ready')
        sys.exit(5)
    run(['xrandr', '-d', ':99', '--current'], timeout=5)
    start_background(
        ['x11vnc', '-noxrecord', '-xrandr', '-noncache', '-display', ':99', '-forever', '-rfbport', '5900'],
        '/tmp/cod-x11vnc.log',
    )
    time.sleep(1)
    start_background(
        ['/usr/bin/python3.8', '-m', 'websockify', '1337', ':5900'],
        '/tmp/cod-websockify.log',
        cwd='/usr/local/websockify',
    )
    time.sleep(2)
    say('Graphics stack is ready at', f'{GRAPHICS_WIDTH}x{GRAPHICS_HEIGHT}')

def write_jwmrc(path):
    with open(path, 'w') as f:
        f.write(textwrap.dedent('''\
            <?xml version="1.0"?>
            <JWM>
              <RootMenu onroot="123">
                <Restart label="Restart JWM"/>
                <Exit label="Exit JWM" confirm="false"/>
              </RootMenu>
              <Group>
                <Name>Navigator</Name>
                <Class>firefox</Class>
                <Class>Firefox</Class>
                <Option>maximized</Option>
                <Option>noborder</Option>
                <Option>notitle</Option>
              </Group>
              <Group>
                <Name>PrismLauncher</Name>
                <Class>PrismLauncher</Class>
                <Class>prismlauncher</Class>
                <Option>maximized</Option>
              </Group>
              <Group>
                <Option>tiled</Option>
                <Option>aerosnap</Option>
              </Group>
              <WindowStyle decorations="motif">
                <Font>Sans-10</Font>
                <Width>1</Width>
                <Height>20</Height>
                <Corner>0</Corner>
                <Foreground>#81b69f</Foreground>
                <Background>#001e14</Background>
                <Outline>#001e14</Outline>
                <Active>
                  <Foreground>#daffec</Foreground>
                  <Background>#002c1f</Background>
                  <Outline>#002c1f</Outline>
                </Active>
              </WindowStyle>
              <TitleButtonOrder>tx</TitleButtonOrder>
              <Tray autohide="true" x="0" y="-1" height="1"></Tray>
              <FocusModel>click</FocusModel>
              <MoveMode>opaque</MoveMode>
              <ResizeMode>opaque</ResizeMode>
              <DoubleClickSpeed>400</DoubleClickSpeed>
              <DoubleClickDelta>2</DoubleClickDelta>
              <Mouse context="title" button="1">move</Mouse>
              <Mouse context="title" button="11">maximize</Mouse>
              <Mouse context="close" button="1">close</Mouse>
              <Key key="A-Tab">nextstacked</Key>
              <Key key="A-F4">close</Key>
            </JWM>
        '''))

def get_window_title(window_id):
    ok, out, _err = run(['xprop', '-id', window_id, '_NET_WM_NAME', 'WM_NAME'], timeout=2, quiet=True)
    if not ok:
        return ''
    for line in out.splitlines():
        if ' = ' not in line:
            continue
        _key, value = line.split(' = ', 1)
        if value.startswith('"') and value.endswith('"'):
            return value[1:-1]
    return ''

def list_windows():
    ok, out, _err = run(['xprop', '-root', '_NET_CLIENT_LIST'], timeout=2, quiet=True)
    if not ok or '#' not in out:
        return []
    ids = [part.strip().rstrip(',') for part in out.split('#', 1)[1].split(',')]
    windows = []
    for window_id in ids:
        if not window_id.startswith('0x'):
            continue
        title = get_window_title(window_id) or 'Untitled window'
        windows.append({'id': window_id, 'title': title})
    return windows

def watch_windows():
    previous = None
    while True:
        windows = list_windows()
        current = json.dumps(windows, sort_keys=True)
        if current != previous:
            say('COD_WINDOWS', current)
            previous = current
        time.sleep(1)

say('Starting desktop services')
write_desktop_env()
start_session_bus()
restart_graphics_stack()
try:
    subprocess.run(['xsetroot', '-solid', '#00120a'], timeout=5)
except Exception:
    pass

jwm = extract_jwm()
if not jwm:
    say('Error: could not install the window manager')
    sys.exit(2)
say('Window manager is ready:', jwm)

jwmrc = os.path.join(tempfile.mkdtemp(prefix='cod-jwmrc-'), 'jwmrc')
write_jwmrc(jwmrc)
env = os.environ.copy()
env['PATH'] = os.path.dirname(jwm) + ':' + BIN_DIR + ':' + env.get('PATH', '')
wm = subprocess.Popen([jwm, '-f', jwmrc], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env=env)
time.sleep(1)
if wm.poll() is not None:
    say('Error: window manager exited during startup with code', wm.returncode)
    sys.exit(3)
say('Desktop is ready')
threading.Thread(target=watch_windows, daemon=True).start()

while True:
    if wm.poll() is not None:
        say('Error: window manager stopped with code', wm.returncode)
        sys.exit(4)
    time.sleep(5)
