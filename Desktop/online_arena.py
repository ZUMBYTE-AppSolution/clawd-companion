"""Optional, server-scored arena and account controls for the desktop Highscores tab."""
from concurrent.futures import ThreadPoolExecutor
import json
import arena_session
from time import monotonic

from PySide6.QtCore import QCoreApplication, QRectF, Qt, QTimer, Signal
from PySide6.QtGui import QColor, QPainter, QPixmap
from PySide6.QtWidgets import (QAbstractItemView, QCheckBox, QDialog, QDialogButtonBox, QFormLayout, QHBoxLayout,
                               QLabel, QLineEdit, QPushButton, QTableWidget, QTableWidgetItem, QVBoxLayout, QWidget)

from arena_wire import ArenaClient, ArenaError, RemoteFrame, USER, kd_ratio, leaderboard_rows, number, validate_account
from desktop_core import ASSETS


class RankedCanvas(QWidget):
    clicked = Signal(float, float)

    def __init__(self, parent=None):
        super().__init__(parent)
        self.frame = None
        self.atlas = QPixmap(str(ASSETS / "mascot-atlas.png"))
        self.sprites = json.loads((ASSETS / "mascot-atlas.json").read_text(encoding="utf-8"))
        self.setMinimumHeight(160)
        self.setMaximumHeight(220)

    def box(self):
        unit = min(self.width()/300, self.height()/160)
        return QRectF((self.width()-300*unit)/2, (self.height()-160*unit)/2, 300*unit, 160*unit)

    def paintEvent(self, event):
        if self.frame is None:
            return
        p = QPainter(self)
        try:
            rect = self.box()
            p.fillRect(rect, QColor("#45414b"))
            p.translate(rect.topLeft())
            p.scale(rect.width()/300, rect.height()/160)
            scene = self.frame.scene
            scene.draw(p)
            pose = {"dead": "grave", "victory": "virusVictory", "expired": "idle"}.get(self.frame.phase, "virusFight")
            record = self.sprites["poses"].get(pose, self.sprites["poses"]["idle"])
            cel = int(scene.time*self.sprites["fps"]) % record["frames"]
            w, h = self.sprites["cellWidth"], self.sprites["cellHeight"]
            src = QRectF(cel*w, record["row"]*h, w, h)
            x, y = scene.hero
            p.setRenderHint(QPainter.RenderHint.SmoothPixmapTransform, False)
            p.drawPixmap(QRectF(x-w/2, y-h/2, w, h), self.atlas, src)
        finally:
            p.end()

    def mousePressEvent(self, event):
        rect = self.box()
        point = event.position()
        if self.frame and rect.contains(point) and event.button() == Qt.MouseButton.LeftButton:
            x = (point.x()-rect.x())*300/rect.width()
            y = (point.y()-rect.y())*160/rect.height()
            if self.frame.scene.target_at(x, y):
                self.clicked.emit(x, y)
                event.accept()
                return
        super().mousePressEvent(event)


class OnlineArenaWidget(QWidget):
    roundEnded = Signal(str, str)

    def __init__(self, translate, can_play, parent=None, *, client=None, local_playing=lambda: False):
        super().__init__(parent)
        self.tr_text, self.can_play = translate, can_play
        self.local_playing = local_playing
        self._client = client or ArenaClient()
        self._workers = ThreadPoolExecutor(max_workers=3, thread_name_prefix="clawd-arena")
        self._pending = {}
        self._token, self._username = "", ""
        self._remember = False
        self._stored = False
        self._auth_epoch = self._run_epoch = 0
        self._next_poll = self._opened = 0.0
        self._next_click = None
        self._retry_click = 0
        self._starting = self._want_profile = self._want_board = False
        self._last_terminal_id = None
        self._profile = None
        self._message_key = ""
        self._rows = []
        self._has_loaded = False
        layout = QVBoxLayout(self)
        self.account = QLabel()
        self.account.setTextFormat(Qt.TextFormat.PlainText)
        self.profile = QLabel()
        self.profile.setTextFormat(Qt.TextFormat.PlainText)
        self.profile.setWordWrap(True)
        self.status = QLabel()
        self.status.setTextFormat(Qt.TextFormat.PlainText)
        self.status.setWordWrap(True)
        self.login, self.register, self.logout = QPushButton(), QPushButton(), QPushButton()
        self.login.clicked.connect(lambda checked=False: self._credentials(False))
        self.register.clicked.connect(lambda checked=False: self._credentials(True))
        self.logout.clicked.connect(self._logout)
        row = QHBoxLayout()
        row.addWidget(self.account)
        row.addStretch(1)
        for button in (self.login, self.register, self.logout):
            row.addWidget(button)
        layout.addLayout(row)
        layout.addWidget(self.profile)
        controls = QHBoxLayout()
        self.start, self.refresh = QPushButton(), QPushButton()
        self.start.clicked.connect(self._toggle_run)
        self.refresh.clicked.connect(self._refresh)
        controls.addWidget(self.start)
        controls.addWidget(self.refresh)
        controls.addStretch(1)
        layout.addLayout(controls)
        self.canvas = RankedCanvas()
        self.canvas.clicked.connect(self._click)
        layout.addWidget(self.canvas)
        self.table = QTableWidget(0, 7)
        self.table.setEditTriggers(QAbstractItemView.EditTrigger.NoEditTriggers)
        self.table.setSelectionBehavior(QAbstractItemView.SelectionBehavior.SelectRows)
        self.table.verticalHeader().setVisible(False)
        self.table.setMinimumHeight(105)
        layout.addWidget(self.table)
        layout.addWidget(self.status)
        self._timer = QTimer(self)
        self._timer.setInterval(70)
        self._timer.timeout.connect(self._pump)
        QCoreApplication.instance().aboutToQuit.connect(self._shutdown)
        if client is None:
            try:
                self._token, self._username = arena_session.read()
                self._stored = bool(self._token)
            except Exception:
                pass
        self.refresh_language()
        if self._token:
            self._refresh()

    def _shutdown(self):
        self._timer.stop()
        self._clear_auth()
        self._workers.shutdown(wait=False, cancel_futures=True)

    def is_playing(self):
        return self._starting or (self.canvas.frame is not None and self.canvas.frame.scene.playing)

    def stop(self):
        """Release a live run locally. The API expires abandoned runs on the server."""
        self._run_epoch += 1
        self._starting = False
        self._next_click = None
        self._retry_click = 0
        self.canvas.frame = None
        self.canvas.hide()
        self._sync()

    def refresh_language(self):
        t = self.tr_text
        for control, key in ((self.login, "Anmelden"), (self.register, "Registrieren"),
                             (self.logout, "Abmelden"), (self.refresh, "Aktualisieren")):
            control.setText(t(key))
        self.table.setHorizontalHeaderLabels([t(key) for key in ("Rang", "Benutzername", "Kills", "Tode", "K/D", "Siege", "Punkte")])
        self.table.resizeColumnsToContents()
        self._sync()

    def _sync(self):
        t = self.tr_text
        logged = bool(self._token)
        self.account.setText(t("Angemeldet als {0}").replace("{0}", self._username) if logged else t("Rangliste"))
        self.login.setVisible(not logged)
        self.register.setVisible(not logged)
        self.logout.setVisible(logged)
        self.refresh.setEnabled(logged)
        self.table.setVisible(logged)
        for control in (self.login, self.register, self.logout):
            control.setEnabled("auth" not in self._pending)
        self.start.setText(t("Wertungsrunde beenden" if self.is_playing() else "Wertungsrunde starten"))
        self.refresh_start_button()
        self.profile.setVisible(bool(self._profile))
        if self._profile:
            self.profile.setText("    ".join(f"{t(key)}  {self._stat_text(key, value)}" for key, value in zip(
                ("Kills", "Tode", "K/D", "Siege", "Punkte"), self._profile)))
        frame = self.canvas.frame
        self.canvas.setVisible(frame is not None)
        if frame:
            self.canvas.update()
        self.status.setVisible(bool(self._message_key or frame or not logged))
        message = (t(self._message_key) if self._message_key else
                   t("Für die Online-Rangliste und gewertete Runden anmelden.") if not logged else "")
        if frame:
            credit = t("Gewerteter Treffer bestätigt" if frame.ranked else "Noch ohne gewerteten Treffer")
            message = "    ".join(filter(None, (message, credit, f"{t('Punkte')}  {frame.score}")))
        self.status.setText(message)

    def refresh_start_button(self):
        self.start.setEnabled(bool(self._token) and not self.local_playing()
                              and (self.is_playing() or "game" not in self._pending))

    @staticmethod
    def _stat_text(key, value):
        if key == "K/D":
            return "—" if value is None else f"{value:g}"
        return str(value)

    def _submit(self, lane, op, method, path, data=None, token=""):
        if lane in self._pending:
            return False
        future = self._workers.submit(self._client.request, method, path, data, token)
        self._pending[lane] = (op, future, self._auth_epoch, self._run_epoch)
        if not self._timer.isActive():
            self._timer.start()
        return True

    def _credentials(self, register):
        if self._token or "auth" in self._pending:
            return
        t = self.tr_text
        dialog = QDialog(self)
        dialog.setWindowTitle(t("Konto erstellen" if register else "Anmelden"))
        form = QFormLayout(dialog)
        user = QLineEdit()
        user.setMaxLength(24 if register else 254)
        mail = QLineEdit()
        mail.setMaxLength(254)
        password = QLineEdit()
        password.setMaxLength(128)
        password.setEchoMode(QLineEdit.EchoMode.Password)
        form.addRow(t("Benutzername" if register else "Benutzername oder E-Mail"), user)
        if register:
            form.addRow(t("E-Mail"), mail)
        form.addRow(t("Passwort"), password)
        remember = QCheckBox(t("Angemeldet bleiben"))
        form.addRow(remember)
        buttons = QDialogButtonBox(QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel)
        buttons.accepted.connect(dialog.accept)
        buttons.rejected.connect(dialog.reject)
        form.addRow(buttons)
        if dialog.exec() != QDialog.DialogCode.Accepted:
            password.clear()
            dialog.deleteLater()
            return
        self._remember = remember.isChecked()
        name, secret, email = user.text().strip(), password.text(), mail.text().strip()
        password.clear()
        dialog.deleteLater()
        try:
            validate_account(name, secret, email if register else None)
        except ArenaError:
            self._message_key = "Eingaben prüfen."
        else:
            body = {"username": name, "password": secret}
            if register:
                body["email"] = email
            action = "register" if register else "login"
            self._submit("auth", action, "POST", "/" + action, body)
            self._message_key = ""
        self._sync()

    def _logout(self):
        if self._stored:
            try:
                arena_session.clear()
            except Exception:
                self._message_key = "Schlüsselbund nicht verfügbar"
                self._sync()
                return
            self._stored = False
        token = self._token
        self.stop()
        self._clear_auth()
        if token:
            self._submit("auth", "logout", "POST", "/logout", {}, token)
        self._message_key = ""
        self._sync()

    def _clear_auth(self):
        self._auth_epoch += 1
        self._token, self._username, self._profile = "", "", None
        self._want_profile = self._want_board = False
        self._has_loaded = False
        self._rows.clear()
        self.table.setRowCount(0)

    def _refresh(self):
        self._want_board = bool(self._token)
        self._want_profile = bool(self._token)
        if self._token and not self._timer.isActive():
            self._timer.start()

    def _toggle_run(self):
        if self.is_playing():
            self.stop()
        elif self._token and self.can_play():
            self._run_epoch += 1
            self._opened = monotonic()
            self._starting = self._submit("game", "start", "POST", "/runs", {}, self._token)
            self.canvas.frame = None
            self._message_key = ""
        else:
            self._message_key = "Für eine Wertungsrunde aktives Spielen erlauben."
        self._sync()

    def _click(self, x, y):
        frame = self.canvas.frame
        if frame and frame.scene.playing and self.can_play() and self._next_click is None and frame.scene.target_at(x, y):
            # A delayed response retries exactly the same coordinates and sequence.
            self._next_click = {"x": x, "y": y, "seq": frame.seq+1}
            self._retry_click = 0
            self._next_poll = 0

    def _pump(self):
        for lane, (op, future, auth_epoch, run_epoch) in list(self._pending.items()):
            if not future.done():
                continue
            del self._pending[lane]
            if auth_epoch != self._auth_epoch or (lane == "game" and run_epoch != self._run_epoch):
                self._sync()
                continue
            try:
                self._accept(op, future.result())
            except (ArenaError, OSError) as error:
                self._failure(op, error)
            self._sync()
        if not self.isVisible():
            if not self._pending:
                self._timer.stop()
            return
        if self.is_playing() and not self.can_play():
            self.stop()
            self._message_key = "Für eine Wertungsrunde aktives Spielen erlauben."
            self._sync()
        if self._want_profile and self._token:
            if self._submit("profile", "profile", "GET", "/me", token=self._token):
                self._want_profile = False
        if self._want_board and self._token and self._submit("board", "board", "GET", "/leaderboard", token=self._token):
            self._want_board = False
        frame = self.canvas.frame
        if frame and frame.scene.playing and "game" not in self._pending and monotonic() >= self._next_poll:
            path = "/runs/" + frame.id
            if self._next_click:
                self._submit("game", "click", "POST", path+"/click", self._next_click, self._token)
            else:
                self._submit("game", "poll", "GET", path, token=self._token)
            self._next_poll = monotonic() + .20
        if not self._pending and not self.is_playing() and not self._want_board and not self._want_profile:
            self._timer.stop()

    def _accept(self, op, data):
        if op in ("register", "login"):
            token, username = data.get("token"), data.get("username")
            if not isinstance(token, str) or not token.isascii() or not 1 <= len(token) <= 4096 or not all(33 <= ord(c) <= 126 for c in token):
                raise ArenaError("invalid_response")
            if not isinstance(username, str) or not USER.fullmatch(username):
                raise ArenaError("invalid_response")
            self._auth_epoch += 1
            self._token, self._username = token, username
            self._refresh()
            self._message_key = ""
            if self._remember:
                try:
                    arena_session.save(token, username)
                    self._stored = True
                except Exception:
                    self._message_key = "Schlüsselbund nicht verfügbar"
        elif op == "board":
            self._rows = leaderboard_rows(data)
            self.table.setRowCount(len(self._rows))
            for row, values in enumerate(self._rows):
                for col, value in enumerate(values):
                    self.table.setItem(row, col, QTableWidgetItem(self._stat_text("K/D" if col == 4 else "", value)))
            self.table.resizeColumnsToContents()
            self._has_loaded = True
            if self._message_key == "Keine Verbindung zum Server.":
                self._message_key = ""
        elif op == "profile":
            if data.get("username") != self._username:
                raise ArenaError("invalid_response")
            self._profile = tuple(kd_ratio(data) if k == "kd" else number(data.get(k), 0, 10**15, integer=True)
                                  for k in ("kills", "deaths", "kd", "wins", "score"))
        elif op in ("start", "poll", "click"):
            frame = RemoteFrame(data, self.tr_text, max(0, monotonic()-self._opened))
            old = self.canvas.frame
            if old and (frame.id != old.id or frame.seq < old.seq):
                raise ArenaError("invalid_response")
            if op == "click" and self._next_click and frame.seq < self._next_click["seq"]:
                raise ArenaError("invalid_response")
            if self._next_click and frame.seq >= self._next_click["seq"]:
                self._next_click = None
            self._starting = False
            self.canvas.frame = frame
            self._message_key = {"dead": "Game Over", "victory": "Sieg!", "expired": "Runde abgelaufen."}.get(frame.phase, "")
            if not frame.scene.playing:
                self._next_click = None
                self._refresh()
                if frame.phase in ("dead", "victory") and frame.id != self._last_terminal_id:
                    self._last_terminal_id = frame.id
                    self.roundEnded.emit(frame.id, frame.phase)

    def _failure(self, op, error):
        code, http = getattr(error, "code", "network"), getattr(error, "http", 0)
        if http == 401 and op not in ("login", "register"):
            if self._stored:
                try:
                    arena_session.clear()
                except Exception:
                    pass
                self._stored = False
            self.stop()
            self._clear_auth()
        if op == "click" and code == "network" and self._retry_click < 2:
            self._retry_click += 1
            self._next_poll = monotonic() + .6
        elif op in ("start", "click", "poll"):
            self.stop()
        known = {
            "reviving": "Claw’d ruht unter einem GIT-Grabstein",
            "invalid_credentials": "Zugangsdaten ungültig.",
            "account_unavailable": "Benutzername oder E-Mail bereits vergeben.",
            "invalid_registration": "Prüfe Benutzername, E-Mail und Passwort.",
            "unauthorized": "Sitzung abgelaufen. Bitte erneut anmelden.",
            "rate_limited": "Zu viele Anfragen. Bitte kurz warten.",
            "not_found": "Die Runde ist nicht mehr verfügbar.",
        }
        if op == "logout":
            self._message_key = "Lokal abgemeldet. Der Server konnte die Abmeldung nicht bestätigen."
        elif code in known:
            self._message_key = known[code]
        elif op in ("login", "register") and http in (400, 401, 403, 409, 422):
            self._message_key = "Anmeldung fehlgeschlagen."
        elif code == "network":
            self._message_key = "Keine Verbindung zum Server."
        else:
            self._message_key = "Der Server hat die Anfrage abgelehnt."

    def showEvent(self, event):
        super().showEvent(event)
        if not self._has_loaded or self._want_board or self._want_profile:
            self._refresh()

    def hideEvent(self, event):
        if self.is_playing():
            self.stop()
        super().hideEvent(event)
