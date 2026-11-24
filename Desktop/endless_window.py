"""The player-controlled arena owns its window and never takes over the overlay."""
import json
from urllib.parse import urlencode
from PySide6.QtCore import QUrl, Qt
from PySide6.QtWebEngineWidgets import QWebEngineView
from desktop_core import ROOT

LABELS = ("Endlos-Arena", "Level", "Welle", "Bestleistung", "Spielen", "Pause", "Spiel vorbei",
          "Mehrfachschuss", "Flächenschaden", "Durchschuss", "Schnellfeuer", "Bewegen")

class EndlessWindow(QWebEngineView):
    def __init__(self, translate, preferences, on_record):
        super().__init__()
        self.setAttribute(Qt.WidgetAttribute.WA_DeleteOnClose)
        self.setWindowTitle(translate(LABELS[0]))
        self.titleChanged.connect(self.record)
        self.preferences = preferences
        self.on_record = on_record
        url = QUrl.fromLocalFile(str(ROOT / "Resources/EndlessArena/index.html"))
        fragment = urlencode({"labels": json.dumps([translate(k) for k in LABELS]),
                              "volume": preferences["volume"]/100 if preferences["sound"] else 0,
                              "muted": json.dumps(preferences["muted"]), "best": preferences["endlessBest"]})
        self.load(QUrl.fromEncoded(url.toEncoded().data() + b"#" + fragment.encode("ascii")))

    def record(self, title):
        prefix = "ClawdArena/"
        if title.startswith(prefix) and title[len(prefix):].isascii() and title[len(prefix):].isdigit():
            progress = int(title[len(prefix):])
            if progress > self.preferences["endlessBest"]:
                self.preferences["endlessBest"] = progress
                self.preferences.save()
                self.on_record()
