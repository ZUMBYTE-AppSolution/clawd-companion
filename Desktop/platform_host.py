"""Read foreground-window geometry and aggregate session idle time without input hooks."""
import ctypes
from ctypes import wintypes
from functools import lru_cache
import os
import sys


def _logical_rect(rect, monitor=None):
    """Qt reports logical sizes, while the window server returns physical pixels."""
    from PySide6.QtGui import QGuiApplication
    app = QGuiApplication.instance()
    if app is None:
        return rect
    x, y, w, h = rect
    screens = app.screens()
    if not screens:
        return rect
    center_x, center_y = x + w / 2, y + h / 2

    def distance(screen):
        box, ratio = screen.geometry(), screen.devicePixelRatio()
        dx = max(box.x() - center_x, 0, center_x - box.x() - box.width() * ratio)
        dy = max(box.y() - center_y, 0, center_y - box.y() - box.height() * ratio)
        return dx * dx + dy * dy

    chosen = min(screens, key=distance)
    if monitor is not None:
        left, top, name = monitor
        chosen = next((s for s in screens if s.name().casefold() == name.casefold()), chosen)
    else:
        left, top = chosen.geometry().x(), chosen.geometry().y()
    scale, box = chosen.devicePixelRatio(), chosen.geometry()
    return (round(box.x() + (x-left)/scale), round(box.y() + (y-top)/scale),
            max(1, round(w/scale)), max(1, round(h/scale)))


class _LastInput(ctypes.Structure):
    _fields_ = [("size", wintypes.UINT), ("tick", wintypes.DWORD)]


class _MonitorInfo(ctypes.Structure):
    _fields_ = [("size", wintypes.DWORD), ("rect", wintypes.RECT), ("work", wintypes.RECT),
                ("flags", wintypes.DWORD), ("device", wintypes.WCHAR * 32)]


def _bind(dll, name, result, *args):
    fn = getattr(dll, name)
    fn.argtypes, fn.restype = args, result
    return fn


class _Windows:
    def __init__(self):
        user = ctypes.WinDLL("user32", use_last_error=True)
        kernel = ctypes.WinDLL("kernel32", use_last_error=True)
        dwm = ctypes.WinDLL("dwmapi", use_last_error=True)
        hwnd, boolean = wintypes.HWND, wintypes.BOOL
        self.foreground = _bind(user, "GetForegroundWindow", hwnd)
        self.shell = _bind(user, "GetShellWindow", hwnd)
        self.visible = _bind(user, "IsWindowVisible", boolean, hwnd)
        self.minimized = _bind(user, "IsIconic", boolean, hwnd)
        self.process = _bind(user, "GetWindowThreadProcessId", wintypes.DWORD, hwnd, ctypes.POINTER(wintypes.DWORD))
        self.classname = _bind(user, "GetClassNameW", ctypes.c_int, hwnd, wintypes.LPWSTR, ctypes.c_int)
        self.bounds = _bind(user, "GetWindowRect", boolean, hwnd, ctypes.POINTER(wintypes.RECT))
        self.dwm_attribute = _bind(dwm, "DwmGetWindowAttribute", ctypes.c_long, hwnd, wintypes.DWORD,
                                   ctypes.c_void_p, wintypes.DWORD)
        self.monitor = _bind(user, "MonitorFromWindow", ctypes.c_void_p, hwnd, wintypes.DWORD)
        self.monitor_info = _bind(user, "GetMonitorInfoW", boolean, ctypes.c_void_p, ctypes.POINTER(_MonitorInfo))
        self.last = _bind(user, "GetLastInputInfo", boolean, ctypes.POINTER(_LastInput))
        self.ticks = _bind(kernel, "GetTickCount", wintypes.DWORD)

    def idle(self):
        info = _LastInput()
        info.size = ctypes.sizeof(info)
        if self.last(ctypes.byref(info)):
            return ((self.ticks() - info.tick) & 0xFFFFFFFF) / 1000.0
        return None

    def rect(self, handle):
        if not handle or not self.visible(handle) or self.minimized(handle) or handle == self.shell():
            return None
        cloaked = wintypes.DWORD()
        self.dwm_attribute(handle, 14, ctypes.byref(cloaked), ctypes.sizeof(cloaked))
        pid = wintypes.DWORD()
        self.process(handle, ctypes.byref(pid))
        if cloaked.value or pid.value == os.getpid():
            return None
        name = ctypes.create_unicode_buffer(128)
        self.classname(handle, name, len(name))
        if name.value in {"Shell_TrayWnd", "Shell_SecondaryTrayWnd", "WorkerW", "Progman"}:
            return None
        rect = wintypes.RECT()
        if self.dwm_attribute(handle, 9, ctypes.byref(rect), ctypes.sizeof(rect)) != 0 and not self.bounds(handle, ctypes.byref(rect)):
            return None
        if rect.right <= rect.left or rect.bottom <= rect.top:
            return None
        info = _MonitorInfo()
        info.size = ctypes.sizeof(info)
        mon = None
        if self.monitor_info(self.monitor(handle, 2), ctypes.byref(info)):
            mon = info.rect.left, info.rect.top, info.device
        return _logical_rect((rect.left, rect.top, rect.right - rect.left, rect.bottom - rect.top), mon)


class _X11:
    def __init__(self):
        from Xlib import display
        self.display = display.Display()
        self.root = self.display.screen().root
        self.atoms = {name: self.display.intern_atom(name) for name in
                      ("_NET_ACTIVE_WINDOW", "_NET_FRAME_EXTENTS", "_NET_WM_PID", "_NET_WM_WINDOW_TYPE",
                       "_NET_WM_WINDOW_TYPE_DESKTOP", "_NET_WM_WINDOW_TYPE_DOCK")}

    def property(self, window, name):
        prop = window.get_full_property(self.atoms[name], 0)
        return prop.value if prop is not None else ()

    def foreground(self):
        handles = self.property(self.root, "_NET_ACTIVE_WINDOW")
        return int(handles[0]) if len(handles) else None

    def rect(self, handle):
        from Xlib import X
        win = self.display.create_resource_object("window", int(handle))
        if win.get_attributes().map_state != X.IsViewable:
            return None
        owners = self.property(win, "_NET_WM_PID")
        types = self.property(win, "_NET_WM_WINDOW_TYPE")
        if (len(owners) and owners[0] == os.getpid()) or any(self.atoms[n] in types for n in
                ("_NET_WM_WINDOW_TYPE_DESKTOP", "_NET_WM_WINDOW_TYPE_DOCK")):
            return None
        size = win.get_geometry()
        pos = self.root.translate_coords(win, 0, 0)
        borders = self.property(win, "_NET_FRAME_EXTENTS")
        left, right, top, bottom = (int(v) for v in borders[:4]) if len(borders) >= 4 else (0, 0, 0, 0)
        return _logical_rect((pos.x - left, pos.y - top, size.width + left + right, size.height + top + bottom))

    def idle(self):
        return self.root.screensaver_query_info().idle / 1000.0


@lru_cache(maxsize=1)
def _backend():
    if sys.platform == "win32":
        return _Windows()
    if sys.platform.startswith("linux") and os.environ.get("DISPLAY") and not _wayland():
        return _X11()
    return None


def _wayland():
    return bool(os.environ.get("WAYLAND_DISPLAY")) or os.environ.get("XDG_SESSION_TYPE", "").lower() == "wayland"


def active_window():
    """Return (native ID, x, y, width, height), or None if the OS hides the window."""
    try:
        host = _backend()
        handle = host.foreground() if host else None
        rect = host.rect(handle) if handle else None
        return (handle, *rect) if rect else None
    except Exception:
        # The client may have exited between the property and geometry queries.
        return None


def window_rect(handle):
    try:
        host = _backend()
        return host.rect(handle) if host and handle else None
    except Exception:
        return None


@lru_cache(maxsize=1)
def _gnome_idle_interface():
    from PySide6.QtDBus import QDBusConnection, QDBusInterface
    interface = QDBusInterface("org.gnome.Mutter.IdleMonitor", "/org/gnome/Mutter/IdleMonitor/Core",
                               "org.gnome.Mutter.IdleMonitor", QDBusConnection.sessionBus())
    interface.setTimeout(100)
    return interface


def idle_seconds():
    """A missing source returns None so the idle-only arcade can fail closed."""
    try:
        if sys.platform.startswith("linux") and _wayland():
            interface = _gnome_idle_interface()
            if not interface.isValid():
                return None
            reply = interface.call("GetIdletime")
            values = reply.arguments()
            return float(values[0])/1000 if not reply.errorName() and values else None
        host = _backend()
        return host.idle() if host else None
    except Exception:
        return None
