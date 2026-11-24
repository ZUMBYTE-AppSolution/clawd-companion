"""Companion chrome shared by the Qt windows and their native popups."""
from PySide6.QtCore import Qt
from PySide6.QtGui import QColor, QPalette, QPainter
from PySide6.QtWidgets import QWidget

PALETTES = {
    "dark": dict(window="#211e23", surface="#2e2930", field="#242127", button="#39333b",
                 ink="#fff1df", secondary="#d2c2b8", muted="#aa9896", line="#685960",
                 accent="#ffb28e", on_accent="#341e18", hover="#4b4048", sky="#302831", hill="#453845"),
    "light": dict(window="#f6f0e8", surface="#fffbf5", field="#fffdfa", button="#f0e6da",
                  ink="#2e2426", secondary="#55484a", muted="#726366", line="#aa9691",
                  accent="#9c452d", on_accent="#fff8ec", hover="#e6d6c8", sky="#f3e8d9", hill="#dac8b8")
}

class Appearance:
    def __init__(self, app, preference):
        self.app = app
        self.preference = preference
        self.fallback_dark = app.palette().color(QPalette.ColorRole.Window).lightness() < 128
        app.setStyle("Fusion")
        app.styleHints().colorSchemeChanged.connect(self.apply)
        self.apply()

    def select(self, value):
        self.preference = value
        self.apply()

    def apply(self, *_):
        scheme = self.app.styleHints().colorScheme()
        dark = scheme == Qt.ColorScheme.Dark or (scheme == Qt.ColorScheme.Unknown and self.fallback_dark)
        self.mode = self.preference if self.preference in PALETTES else ("dark" if dark else "light")
        c = PALETTES[self.mode]
        palette = QPalette()
        role = QPalette.ColorRole
        for key, name in ((role.Window,"window"),(role.Base,"field"),(role.AlternateBase,"surface"),
                          (role.Button,"button"),(role.WindowText,"ink"),(role.Text,"ink"),
                          (role.ButtonText,"ink"),(role.ToolTipBase,"surface"),(role.ToolTipText,"ink"),
                          (role.Highlight,"accent"),(role.HighlightedText,"on_accent"),(role.Link,"accent"),
                          (role.PlaceholderText,"muted"),(role.Light,"surface"),(role.Mid,"line"),
                          (role.Dark,"line"),(role.BrightText,"ink"),(role.Accent,"accent")):
            palette.setColor(key, QColor(c[name]))
        for key in (role.WindowText,role.Text,role.ButtonText):
            palette.setColor(QPalette.ColorGroup.Disabled,key,QColor(c["muted"]))
        self.app.setPalette(palette)
        self.app.setStyleSheet("""
          QFrame#companionHeader { background: %(sky)s; border: 1px solid %(line)s; border-radius: 9px; }
          QLabel#companionName { font-size: 28px; font-weight: bold; color: %(ink)s; }
          QDialog { background: %(window)s; color: %(ink)s; }
          QScrollArea, QWidget#settingsPage { background: %(surface)s; border: none; }
          QTabWidget::pane { background: %(surface)s; border: 1px solid %(line)s; border-radius: 8px; }
          QTabBar::tab { color: %(secondary)s; background: %(window)s; padding: 8px 13px; margin: 0 2px 3px 0; border-radius: 6px; }
          QTabBar::tab:selected { background: %(accent)s; color: %(on_accent)s; }
          QTabBar::tab:!selected:hover { background: %(hover)s; }
          QLabel, QCheckBox { color: %(ink)s; background: transparent; }
          QLabel[heading="true"] { color: %(secondary)s; padding-top: 8px; }
          QPushButton, QComboBox, QLineEdit, QTextBrowser, QTableWidget {
            color: %(ink)s; background: %(field)s; border: 1px solid %(line)s; border-radius: 6px; padding: 6px 10px;
            selection-color: %(on_accent)s; selection-background-color: %(accent)s; }
          QPushButton, QComboBox { background: %(button)s; }
          QPushButton:hover, QComboBox:hover { background: %(hover)s; }
          QPushButton:pressed { background: %(accent)s; color: %(on_accent)s; }
          QPushButton:focus, QComboBox:focus, QLineEdit:focus, QTabBar::tab:focus, QCheckBox:focus { border: 2px solid %(accent)s; }
          QPushButton:disabled, QComboBox:disabled, QCheckBox:disabled { color: %(muted)s; }
          QHeaderView::section { background: %(button)s; color: %(ink)s; padding: 5px; border: 0; }
          QMenu, QComboBox QAbstractItemView { background: %(surface)s; color: %(ink)s; border: 1px solid %(line)s;
            selection-color: %(on_accent)s; selection-background-color: %(accent)s; }
          QMenu::item { padding: 5px 16px; }
          QMenu::item:selected { color: %(on_accent)s; background: %(accent)s; }
          QToolTip { background: %(surface)s; color: %(ink)s; border: 1px solid %(line)s; }
        """ % c)
        for window in self.app.topLevelWidgets():
            if isinstance(window, CompanionStage):
                window.update()
            if hasattr(window, "set_game_appearance"):
                window.set_game_appearance(self.mode)

class CompanionStage(QWidget):
    """Paint only the Wayland play surface. Child overlays retain transparency."""
    def __init__(self, appearance):
        super().__init__()
        self.appearance = appearance

    def paintEvent(self, event):
        c = PALETTES[self.appearance.mode]
        p = QPainter(self)
        p.fillRect(event.rect(), QColor(c["sky"]))
        width, height = self.width(), self.height()
        for i in range(30):
            x, y = (i*89+37)%width, (i*i*31+21)%max(1,height-54)
            p.fillRect(x,y,2,2,QColor(c["hill"]))
        heights = (18,24,18,32,38,28,22,34,42,33,20,26,36,28)
        for i in range(width//28+1):
            h=heights[i%len(heights)]
            p.fillRect(i*28,height-h,28,h,QColor(c["hill"]))
        p.end()
