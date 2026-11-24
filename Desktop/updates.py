"""Qt desktop release checker. Downloads always open in the user's browser."""
import threading

from PySide6.QtCore import QByteArray, QLocale, QObject, QSettings, QTimer, QUrl, Qt, Signal
from PySide6.QtGui import QDesktopServices, QTextDocument
from PySide6.QtWidgets import (
    QComboBox, QDialog, QDialogButtonBox, QHBoxLayout, QLabel, QPushButton, QTextBrowser, QVBoxLayout,
)

if __package__:
    from .release_info import REPOSITORY, VERSION, fetch_latest, platform_packages, version_key
else:
    from release_info import REPOSITORY, VERSION, fetch_latest, platform_packages, version_key


class _Notes(QTextBrowser):
    def loadResource(self, kind, url):
        # Markdown can contain images, including file URLs. Release notes are text only.
        return QByteArray()


class UpdateController(QObject):
    available = Signal(str)
    _complete = Signal(object, int)

    def __init__(self, parent, tr, language=None):
        super().__init__(parent)
        self.tr_key = tr
        self.language = language or (lambda: QLocale.system().name())
        self.release = None
        self._state = "idle"
        self._generation = 0
        self._enabled = True
        self._dialog = None
        self._settings = QSettings("Zumbyte", "ClawdCompanion")
        self._timer = QTimer(self)
        self._timer.setInterval(24 * 60 * 60 * 1000)
        self._timer.timeout.connect(self.check)
        self._complete.connect(self._receive, Qt.ConnectionType.QueuedConnection)

    def start(self):
        self._enabled = True
        self._timer.start()
        self.check()

    def stop(self):
        self._enabled = False
        self._generation += 1
        self._timer.stop()
        if self._state == "checking":
            self._state = "idle"

    def check(self):
        if not self._enabled or self._state == "checking":
            return
        self._state = "checking"
        self._generation += 1
        generation = self._generation
        self._refresh()

        def worker():
            try:
                result = fetch_latest()
            except Exception:
                # The GUI must recover after a TLS/HTTP/socket backend error.
                result = None
            try:
                self._complete.emit(result, generation)
            except RuntimeError:
                pass  # The application can be closed during a network request.

        threading.Thread(target=worker, daemon=True, name="ClawdReleaseCheck").start()

    def _receive(self, release, generation):
        if generation != self._generation or not self._enabled:
            return
        if release is None:
            self._state = "error"
        else:
            self.release = release
            newer = version_key(release.version) > version_key(VERSION)
            self._state = "new" if newer else "current"
            if newer and self._settings.value("lastUpdateNotice") != release.version:
                self._settings.setValue("lastUpdateNotice", release.version)
                self.available.emit(release.version)
        self._refresh()

    def show(self):
        if self._dialog is not None:
            self._dialog.close()
        tr = self.tr_key
        dialog = QDialog(self.parent())
        dialog.setWindowTitle(tr("Info & Updates"))
        dialog.setAttribute(Qt.WidgetAttribute.WA_DeleteOnClose)
        dialog.resize(475, 565)
        self._dialog = dialog
        dialog.finished.connect(lambda *_: self._closed(dialog))
        layout = QVBoxLayout(dialog)
        layout.setSpacing(10)
        title = QLabel("Claw’d Companion · " + tr("Version {0}").replace("{0}", VERSION))
        title.setStyleSheet("font-size: 17px; font-weight: bold")
        layout.addWidget(title)
        self.status = QLabel()
        self.status.setWordWrap(True)
        layout.addWidget(self.status)
        actions = QHBoxLayout()
        self.check_button = QPushButton(tr("Nach Updates suchen"))
        self.check_button.clicked.connect(self.check)
        actions.addWidget(self.check_button)
        self.release_button = QPushButton(tr("Veröffentlichung öffnen"))
        self.release_button.clicked.connect(lambda: self._open(self.release.url if self.release else REPOSITORY + "/releases/latest"))
        actions.addWidget(self.release_button)
        layout.addLayout(actions)
        self.notes_title = QLabel()
        layout.addWidget(self.notes_title)
        self.notes = _Notes()
        self.notes.setOpenLinks(False)
        self.notes.setOpenExternalLinks(False)
        layout.addWidget(self.notes, 1)
        self.options = QComboBox()
        self.options.setAccessibleName(tr("Paket"))
        layout.addWidget(self.options)
        self.download_button = QPushButton(tr("Paket herunterladen"))
        self.download_button.clicked.connect(self._download)
        layout.addWidget(self.download_button)
        details = QLabel("Zumbyte · AppSolution · Andreas Zumbansen\n"
                         "Kastanienallee 16a · 59174 Kamen · DE\n"
                         "info@zumbyte.de · +49 177 4149667\n"
                         + tr("USt-IdNr. {0}").replace("{0}", "DE347723697"))
        details.setTextInteractionFlags(Qt.TextInteractionFlag.TextSelectableByMouse)
        layout.addWidget(details)
        links = QHBoxLayout()
        for label, url in (("Zumbyte.de", "https://zumbyte.de/"), (tr("Impressum"), "https://zumbyte.de/impressum/")):
            button = QPushButton(label)
            button.clicked.connect(lambda checked=False, target=url: self._open(target))
            links.addWidget(button)
        layout.addLayout(links)
        greeting = QLabel(tr("Liebe Grüße an die gesamte AI Coding Community. Danke fürs Bauen, Teilen und gegenseitige Helfen!"))
        greeting.setWordWrap(True)
        layout.addWidget(greeting)
        buttons = QDialogButtonBox()
        buttons.addButton(tr("Schließen"), QDialogButtonBox.ButtonRole.RejectRole)
        buttons.rejected.connect(dialog.close)
        layout.addWidget(buttons)
        self._refresh()
        dialog.show()
        dialog.raise_()
        if self._state == "idle":
            self.check()

    def _closed(self, dialog):
        if self._dialog is dialog:
            self._dialog = None

    @staticmethod
    def _open(url):
        QDesktopServices.openUrl(QUrl(url))

    def _download(self):
        if self.release and self.options.currentText() in platform_packages(self.release):
            self._open(self.release.download(self.options.currentText()))

    def _refresh(self):
        if self._dialog is None:
            return
        tr = self.tr_key
        keys = {"checking": "Wird geprüft …", "current": "Du verwendest die aktuelle Version.",
                "new": "Version {0} ist verfügbar.", "error": "Updates konnten nicht geprüft werden."}
        key = keys.get(self._state)
        self.status.setText(tr(key).replace("{0}", self.release.version if self.release else "") if key else "")
        self.check_button.setEnabled(self._state != "checking")
        self.notes_title.setVisible(bool(self.release))
        self.notes.setVisible(bool(self.release))
        current_choice = self.options.currentText()
        self.options.clear()
        if self.release:
            self.notes_title.setText(tr("Änderungen in Version {0}").replace("{0}", self.release.version))
            self.notes.document().setMarkdown(self.release.localized_notes(self.language()),
                                              QTextDocument.MarkdownFeature.MarkdownNoHTML)
            self.options.addItems(platform_packages(self.release))
            if self.options.findText(current_choice) >= 0:
                self.options.setCurrentText(current_choice)
        newer = self.release is not None and version_key(self.release.version) > version_key(VERSION)
        self.options.setVisible(newer and self.options.count() > 1)
        self.download_button.setVisible(newer and self.options.count() > 0)
