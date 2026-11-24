import os
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import platform_host


class PlatformHostTests(unittest.TestCase):
    def test_missing_desktop_has_no_idle_or_window(self):
        with patch.object(platform_host, "_backend", return_value=None), patch.object(platform_host, "_wayland", return_value=False):
            self.assertIsNone(platform_host.active_window())
            self.assertIsNone(platform_host.window_rect(1))
            self.assertIsNone(platform_host.idle_seconds())

    @unittest.skipUnless(sys.platform == "win32", "Win32 input clock")
    def test_last_input_reads_current_session(self):
        value = platform_host.idle_seconds()
        self.assertIsInstance(value, float)
        self.assertGreaterEqual(value, 0)
        self.assertIsNone(platform_host.window_rect(0))

    @unittest.skipUnless(os.environ.get("CLAWD_ISOLATED_X11") == "1", "Requires the CI's private Xvfb display")
    def test_real_x11_geometry_and_idle_clock(self):
        from Xlib import X, Xatom, display
        client = display.Display()
        self.addCleanup(client.close)
        root = client.screen().root
        win = root.create_window(40, 60, 240, 120, 0, X.CopyFromParent, X.InputOutput, X.CopyFromParent)
        self.addCleanup(win.destroy)
        win.change_property(client.intern_atom("_NET_FRAME_EXTENTS"), Xatom.CARDINAL, 32, [2, 3, 20, 4])
        root.change_property(client.intern_atom("_NET_ACTIVE_WINDOW"), Xatom.WINDOW, 32, [win.id])
        win.map()
        client.sync()
        self.assertEqual(platform_host.active_window(), (win.id, 38, 40, 245, 144))
        self.assertEqual(platform_host.window_rect(win.id), (38, 40, 245, 144))
        self.assertIsNotNone(platform_host.idle_seconds())
        win.unmap()
        client.sync()
        self.assertIsNone(platform_host.window_rect(win.id))
