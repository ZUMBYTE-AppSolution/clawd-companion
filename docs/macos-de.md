# Claw’d Companion auf dem Mac

[Zur Projektübersicht](../README.md)

Claw’d lebt als animierte Pixel-Figur auf deinem Schreibtisch. Während Claude antwortet, klettert er an einer Fensterkante hoch. Wenn die Antwort fertig ist, seilt er sich ab. Claude.ai-Hinweise erscheinen in einer Sprechblase direkt neben ihm.

## Die Virenarena

Du kannst die Virenarena auf Mac, Windows und Linux direkt unter **Highscores → Lokale Runde starten** spielen. Die lokale Runde läuft auch offline und ohne Konto. Du startest sie jederzeit selbst, unabhängig vom Leerlauf. Deine Einstellungen für das automatische Spiel bleiben erhalten. Für deine lokale Statistik zählen nur abgeschlossene Runden, in denen du selbst einen Gegner getroffen oder ein wirksames Power-up eingesammelt hast. Die Online-Rangliste wertet ausschließlich angemeldete Serverrunden.

Die automatische Desktop-Runde kann nach mindestens 90 Sekunden ohne Maus- oder Tastatureingabe beginnen. Er startet mit **100 Lebenspunkten**. In zwei Wellen treten Pixelviren in zufälliger Anzahl, Größe und Stärke an. Jeder hat einen eigenen Lebensbalken. Danach kommt der Endboss mit eigenem Angriffsmuster und Musikmotiv.

Claude-Aktionen und Freigaben haben Vorrang. Für eine Runde braucht Claw’d sein sichtbares Overlay, freie Bewegung und einen gelösten Fenster-Pin. Nach einer Unterbrechung setzt er die Runde mit denselben Lebenspunkten fort.

Claw’d sammelt **Heilung**, **Schild** und **Schnellfeuer** selbst ein. Bewegst du die Maus oder tippst du, pausiert die Runde samt Musik. Unter **Begleiter → Für den Leerlauf vormerken** kannst du dir eine Runde für die nächste Pause wünschen. Willst du sofort mitspielen, aktiviere **Overlay → Virenarena → Auch bei aktiver Nutzung spielen** und wähle **Begleiter → Arcade starten**. Klicke auf Gegner, um Claw’d zu helfen, oder auf ein Power-up, um es einzusammeln. Die Arena lässt den Trefferzähler der Mauszeigerspiele unberührt.

Nach einer Niederlage bleibt ein Pixelgrabstein mit **GIT** auf dem Schreibtisch. Unter **Begleiter** siehst du den Countdown. Nach **fünf Minuten** gräbt sich Claw’d wieder aus. Die Frist läuft auch im Ruhezustand und bei geschlossener App weiter. Unter **Overlay → Töne → Einzelne Töne** kannst du die Arcade-Musik und die einzelnen Effekte separat einstellen.

Eine [Spielszene mit Originalton](media/virus-arena.mp4) zeigt Wellenmusik, Bossthema und Effekte. Der Film kürzt die fünf Minuten am Grab ab.

## Wenn Claude auf deine Freigabe wartet

Claw’d hält an und entrollt ein kleines **OK?**. Solange eine erkannte Werkzeugfreigabe aussteht, bleibt das Schild auf dem Schreibtisch und in der Menüleiste sichtbar. Du beantwortest die Frage wie gewohnt in Claude. Nach der letzten offenen Anfrage rollt Claw’d das Schild ein und folgt der aktuellen Aktivität. Ein Fenster-Pin bleibt dabei erhalten. Mit **Bewegung reduzieren** zeigt er das aufgeklappte Schild als ruhige Pose.

Unter **Begleiter → OK?-Schild** kannst du die Animation ausprobieren. **Einrollen** beendet die Vorschau vorzeitig. Die Vorschau trifft keine Entscheidung in Claude.

Unter **Begleiter → Aktionsvorschau** kannst du alle sechs Werkzeuganimationen einzeln aufrufen. Im gekoppelten Browser bestimmt die sichtbare Aktivitätsanzeige die Pose. Interne Arbeitsschritte, die Claude.ai nicht ausweist, erscheinen als normale Schreibanimation.

Im gekoppelten Browser erkennt die Erweiterung sichtbare, eindeutig beschriftete Werkzeugfreigaben auf Claude.ai. Bei Claude Code kommen die Signale über die optionale Aktivitätsanbindung. Für unterstützte Terminalsitzungen gleicht Claw’d offene Hauptanfragen mit der lokalen Sitzungsanzeige ab. Fehlt dieser Status, rollt er das Schild beim nächsten zugehörigen Abschluss- oder Fortschrittsereignis ein. Bei einem lange laufenden Werkzeug kann das später als dein Klick sein. [Claude-Code-Hooks](https://code.claude.com/docs/en/hooks) · [Sitzungsstatus](https://code.claude.com/docs/en/agent-view#read-session-state-from-a-script)

## Fenster beim Spazieren erkunden

Wenn **Overlay → Spazieren** und **An Fenstern klettern** eingeschaltet sind, sucht Claw’d während seiner Spaziergänge nach erreichbaren Fensterkanten. Er läuft zur freien Seite, springt an höher gelegene Rahmen und klettert hinauf. Oben balanciert er auf der Kante und späht manchmal hinunter, bevor er abspringt. Ist über dem Fenster zu wenig Platz, stößt er sich von der Seite ab. Die Menüleistenfigur macht den Sprung und die Landung mit.

Bei einem freien Spaziergang sucht er gelegentlich einen Sitzplatz auf der Titelleiste des aktiven Fensters. Er setzt die Füße auf die sichtbare Kante, schaut sich um, blinzelt und grübelt. Schiebst du das Fenster, bewegt sich sein Sitzplatz mit. Ein gesetzter Pin hat Vorrang. Mit „Bewegung reduzieren“ bleibt die Figur ruhig.

Zum direkten Ausprobieren aktiviere ein normales Fenster und wähle per Rechtsklick auf Claw’d **Auf Titelleiste setzen**. Bei einer zu hohen Fensterkante erreicht er den Titelstreifen mit den Scheren von innen. Für einen Sitzplatz braucht er eine freie Kante mit genügend Platz für seinen Körper.

Für das freie Klettern nutzt Claw’d die Geometrie sichtbarer Fenster. Mit der optionalen Bedienungshilfen-Freigabe kann er das fokussierte Fenster einer App genauer bestimmen.

## Sprachen und Stimme

Unter **Overlay → Sprache** kannst du zwischen der Systemsprache und elf festen Sprachen wählen. Das sind Englisch, Mandarin (vereinfachte Schrift), Hindi, Spanisch, Standardarabisch, Französisch, Bengalisch, Portugiesisch, Indonesisch, Urdu und Deutsch. Die Auswahl orientiert sich an der Gesamtzahl der Erst- und Zweitsprachler. Eine vorhandene deutschsprachige Installation startet beim Update weiter auf Deutsch. [Sprachdaten für 2026](https://www.voronoiapp.com/society/The-10-Most-Spoken-Languages-in-the-World-9016)

Claw’ds eigene Meldungen, Status und Bedienelemente folgen der Auswahl. Die Browser-Erweiterung verwendet die Oberflächensprache des Browsers. Claude.ai-Mitteilungen erscheinen im Originalwortlaut. Unter **Eigene Meldungen vorlesen** kannst du eine passende lokal verfügbare macOS-Stimme aktivieren und ausprobieren. Die Sprachausgabe ist anfangs ausgeschaltet.

## Begleiter, Fenster-Pin und Cursor-Spiele

- Die Menüleistenfigur ist animiert. Ihr Bewegungsablauf folgt der Desktopfigur und den Claude-Ereignissen. Bei ausgeblendeter Desktopfigur bleibt die Menüleiste aktiv.
- In Arbeitspausen spaziert Claw’d los, blickt zum Cursor und verfolgt ihn gelegentlich. Benachbarte Monitore gehören zur Spielfläche. Unter **Overlay → Verhalten und Spiel** kannst du Spazieren, Cursorjagd und Codebogen einzeln schalten.
- **Begleiter → Codebogen** startet sofort eine Spielrunde. Sobald der kleine Bogen erscheint, hat Claw’d sein Ziel gewählt. Bewege dann die Maus. Nach einem Treffer erscheint die Trefferzahl am Cursor. Unter **Begleiter** bleiben Treffer und ausgewichene Schüsse auch nach einem Neustart sichtbar.
- Gelegentlich holt Claw’d seinen türkisfarbenen **Buchstabenblaster** heraus. Jede Salve enthält zufällig **3 bis 42** Pixelbuchstaben. Der Blaster folgt der Maus und zielt bei jedem Abschuss neu. Bereits abgefeuerte Buchstaben fliegen auf ihrer eigenen Bahn weiter. Als Treffer zählt die Berührung der Mausspitze mit dem sichtbaren Buchstaben oder dem Codeplättchen des Bogens. Durch die Lücke in einem Buchstaben kannst du hindurchkommen. Automatische Salven liegen mindestens vier Minuten auseinander. Über **Rechtsklick auf Claw’d → Buchstabensalve testen** oder den Pfeil neben **Codebogen** kannst du sie direkt auslösen. Drei ausgewichene Geschosse in Folge bringen Claw’d zum Tanzen.
- **Pin to Window** sitzt im Rechtsklickmenü der Figur. Ziehe Claw’d an die gewünschte Stelle eines Fensters und hefte ihn dort an. Der Pin folgt diesem Fenster auch beim Wechsel zu einer anderen App. Beim Abseilen hängt Claw’d am Pin und kehrt anschließend zurück. Der Pin gilt für das laufende Fenster und lässt sich per Rechtsklick wieder lösen.
- Während Claude Code Subagents meldet, jongliert Claw’d mit kleinen Agentenfiguren. Auf dem Schreibtisch sind bis zu fünf und in der Menüleiste bis zu drei sichtbar. Die genaue Zahl steht im Agentenstatus. Die Web-Anbindung reagiert weiterhin auf erkennbare Claude.ai-Aktivitäten und Meldungen.
- Sprechblasen tragen gestufte Konturen, farbige Pixelsymbole und eine eigens gezeichnete Pixelschrift. Du kannst sie unter **Overlay → Sprechblase testen** ausprobieren.

## Claw’ds Töne

Unter **Overlay → Töne** findest du den Hauptschalter und die Lautstärke. Claw’d startet bei 28 Prozent. Öffne **Einzelne Töne**, um etwa die Schritte stummzuschalten und das Landegeräusch zu behalten. Fürs Tippen, Nachdenken, Jonglieren und für neue Sprechblasen gibt es jeweils einen eigenen Klang. Das Lautsprechersymbol spielt den jeweiligen Ton zur Probe. Deine Auswahl und die Lautstärke bleiben nach dem Beenden erhalten.

## Update einer vorhandenen Installation

Beende die laufende ältere Version per Rechtsklick auf das Menüleistensymbol, lege die neue App in **Programme** und öffne sie. Bestehende Einstellungen verwenden denselben App-Bezeichner. Bei einer bereits eingerichteten Claude-Code-Anbindung wähle unter **Verbindungen → Aktivität und Subagents → Aktualisieren** die neuen Ereignisse und starte dann eine neue Claude-Code-Sitzung. Für den Browser lade die entpackte Erweiterung und deine geöffneten Claude.ai-Tabs erneut. Wenn du die App verschoben hast, findest du den aktuellen Erweiterungsordner unter **Verbindungen**.

## In zwei Minuten ausprobieren

1. Entpacke die ZIP-Datei, ziehe **Clawd Companion.app** in **Programme** und starte sie. Die App ist ein Universal-Build für Apple Silicon und Intel ab macOS 13.
2. Klicke im Bedienfenster auf **Klettern**, **Abseilen** oder **Streicheln**. Unter **Overlay → Sprechblase testen** erscheint eine Beispielmeldung.
3. Öffne ein normales App-Fenster und lass daneben etwas Platz. Das freie Klettern ist mit den Voreinstellungen aktiv. Für die Orientierung am fokussierten Fenster bei Claude-Aktionen kannst du unter **Overlay → Zugriff erlauben** die Bedienungshilfen aktivieren.

Lokal gebaute Testversionen können mit einer Ad-hoc-Signatur versehen sein. Wie macOS mit lokal signierten Apps umgeht, beschreibt [Apple Support](https://support.apple.com/de-de/102445). Mit Xcode kannst du die mitgelieferten Quellen auch direkt selbst bauen.

## Claude Desktop verbinden (macOS)

1. Öffne in Claw’d **Verbindungen** und schalte die Verbindung zu **Claude Desktop** ein.
2. Klicke auf **Zugriff erlauben …**. Aktiviere **Claw’d Companion** in den macOS-Systemeinstellungen unter **Datenschutz & Sicherheit → Bedienungshilfen**.
3. Öffne in der **Claude-App** auf dem Mac **Einstellungen → Nutzung** und lass die Seite kurz geöffnet. Mit **Jetzt einlesen** kannst du die Ansicht erneut prüfen lassen.

Alternativ öffnest du in Claude neben dem Eingabefeld das Menü **Nutzung**. Im geöffneten Menü kann Claw’d die angezeigten Zeitfenster lesen. Bei geschlossenem Menü liefert die Schaltfläche nur den ausdrücklich bezeichneten Zeitraum, etwa das Wochenlimit.

Claw’d liest die verbleibenden Prozente für das Sitzungs- oder Wochenlimit und die Rücksetzzeit, soweit Claude diese Werte in einer unterstützten Form anzeigt. Öffne die Nutzungsansicht erneut, wenn du einen aktuellen Stand brauchst.

Beim Einschalten wählt Claw’d automatisch **Claude Desktop** als Kontingentquelle. Die letzte gültige Messung behält ihren ursprünglichen Zeitstempel. Eine später unter **Begleiter → Kontingent** getroffene Quellenwahl bleibt beim nächsten Start erhalten.

[Apple](https://support.apple.com/guide/mac-help/allow-accessibility-apps-to-access-your-mac-mh43185/mac) · [Claude](https://support.claude.com/en/articles/17007452-what-is-a-limit-reset)

## Claude.ai verbinden

Öffne in der App **Verbindungen** und schalte **Browser-Verbindung** ein. Wähle den Browser, in dem du Claude.ai bereits nutzt.

### Chrome, Edge oder Brave

1. Öffne im Browser die Erweiterungsverwaltung über das Menü **Erweiterungen**. Aktiviere dort den **Entwicklermodus**.
2. In Claw’d klickst du auf **Erweiterungsordner zeigen und Pfad kopieren**. Wähle im Browser **Entpackte Erweiterung laden**, drücke im Dateidialog **⌘⇧G** und füge den kopierten Pfad ein.
3. Klicke in der App auf **Kopplungscode kopieren**. Öffne das Claw’d-Symbol im Erweiterungsmenü des Browsers und füge den Code ein. Lade bereits geöffnete Claude-Tabs einmal neu.

### Safari

1. Starte die App einmal aus **Programme**, damit Safari die eingebettete Erweiterung findet.
2. Für den lokalen Testbuild aktivierst du in **Safari → Einstellungen → Erweitert** die Funktionen für Webentwickler. Ab Safari 17 findest du **Unsignierte Erweiterungen erlauben** anschließend unter **Einstellungen → Entwickler**. Bei älteren Safari-Versionen liegt die Option im Menü **Entwickler**. Safari setzt sie beim Beenden zurück. [Apple-Dokumentation](https://developer.apple.com/documentation/safariservices/running-your-safari-web-extension)
3. Aktiviere unter **Safari → Einstellungen → Erweiterungen** die Erweiterung **Claw’d für Claude.ai** und erlaube ihr den Zugriff auf **claude.ai**. Kopiere den Kopplungscode in der Mac-App und füge ihn im Erweiterungssymbol von Safari ein. Lade offene Claude-Tabs neu.

### Erste Messung und erste Sprechblase

Öffne über das Claw’d-Symbol im **gekoppelten Browser** die Nutzungsseite. Dort übernimmt die Erweiterung die angezeigten Werte für das Sitzungs- und Wochenlimit. Zurück im Chat kannst du wie gewohnt eine Nachricht senden. Sobald Claude eine laufende Antwort signalisiert, reagiert die Figur. Im Bedienfenster steht, welche Aktivität erkannt wurde.

Die Nutzung wird beim erneuten Öffnen oder bei sichtbaren Änderungen dieser Seite aktualisiert. **Stand** bzw. **Letzte Messung** zeigen das Alter des Werts an. Ein bereits erreichter Rücksetzzeitpunkt blendet den alten Wert aus. Bei relativen Zeitangaben ist die errechnete Uhrzeit mit **ca.** gekennzeichnet. Eine verfügbare, aber nicht in ein eindeutiges Datum umrechenbare Angabe erscheint im Originalwortlaut. Enthält der Tarif oder die sichtbare Seite keinen entsprechenden Messwert, bleibt das Feld offen. Die Erweiterung erkennt unterstützte Nutzungs- und Aktivitätsanzeigen in allen elf App-Sprachen. Bleiben Bezeichnungen oder Zeitangaben mehrdeutig, zeigt Claw’d den sichtbaren Wortlaut oder lässt das Feld offen. [Claude-Nutzungsseite](https://claude.ai/settings/usage)

## Auf dem Schreibtisch

| Bedienung oder Claude-Ereignis | Reaktion |
| --- | --- |
| Maus über der Figur | Aktivität, verbleibende Prozente, Rücksetzzeit und Datenquelle erscheinen neben der Figur. |
| Freier Spaziergang neben einer Fensterkante | Claw’d kann hinaufklettern, auf einer zugänglichen Oberkante laufen, abspringen und nach der Landung weiterziehen. |
| Klicken oder ziehen | Öffnet das Bedienfenster bzw. verschiebt Claw’d. |
| Laufende Antwort, Schreiben oder Bearbeiten | Claw’d tippt auf seinem Pixel-Notebook. |
| Erkennbarer Planungs-, Recherche- oder Lesevorgang | Claw’d zeichnet am Flipchart, untersucht Quellen mit der Lupe oder öffnet seine Lesemappe. |
| Erkennbare Codeausführung oder Artefakterstellung | Er arbeitet am Mini-Terminal oder an der Staffelei. |
| Eine beobachtete Antwort endet | Claw’d seilt sich ab, freut sich und meldet den Abschluss. |
| Neuer Hinweis oder Fehler auf Claude.ai | Claw’d zeigt den kurzen Originaltext. Eine Warnung oder ein Fehler löst einen besorgten Gesichtsausdruck aus. |
| Maus über einer Sprechblase | Die Blase bleibt zum Lesen stehen. Mausklicks erreichen weiterhin das Fenster darunter. |
| Rechtsklick auf die Figur | Weitere Bewegungen zum Ausprobieren. |
| Rechtsklick auf das Menüleistensymbol | Figur ein- oder ausblenden und App beenden. |

Die Browser-Verbindung benötigt einen geöffneten, aktiven oder im Hintergrund weiterlaufenden Claude.ai-Tab. Die Erweiterung erkennt neu eingeblendete Meldungen der Website. Hat Claude.ai im Browser bereits Mitteilungsrechte, kann sie außerdem neue, noch aktive Mitteilungen des eigenen Website-Service-Workers übernehmen, sofern der Browser diese dem Tab bereitstellt. Sehr kurze Meldungen und Meldungen bei geschlossenem oder angehaltenem Tab können entfallen.

**Overlay → Sprechblasen** schaltet die Anzeige ein oder aus. **Bewegung reduzieren** zeigt den Zustand als ruhige Pose. Das Bedienfenster lässt sich schließen, während Figur und Browser-Verbindung weiterlaufen.

## Optionale Claude-Code-Anbindung

Für Claude im Terminal stehen in **Verbindungen → Claude Code** zwei unabhängige Schalter bereit.

- **Aktivität** ergänzt Claude-Code-Hooks für laufende Werkzeuge, Freigabeanfragen, Fehler und abgeschlossene Antworten. Für die Agentenzahl ordnet Claw’d Start und Ende über gehashte Sitzungs- und Agentenkennungen zu. Reguläre Aktivität erneuert den Zeitstempel bekannter Agenten. Verwaiste Einträge laufen nach 30 Minuten ohne beobachtetes Ereignis ab.
- **Kontingent** übernimmt die dokumentierten Felder der Claude-Code-Statuszeile. Nach der ersten Antwort können je nach Abo das Fünf-Stunden-Fenster und das Wochenlimit vorliegen. Eine vorhandene kompatible Statuszeile wird verkettet und beim Entfernen wiederhergestellt.

Starte nach der Einrichtung eine neue Claude-Code-Sitzung. Unter **Begleiter → Kontingent** kannst du die Quelle auswählen. Für Claude Desktop, Browser und Terminal werden getrennte Messwerte geführt, auch wenn du unterschiedliche Konten verwendest. [Claude-Code-Statuszeile](https://code.claude.com/docs/en/statusline) · [Claude-Code-Hooks](https://code.claude.com/docs/en/hooks)

## Lokale Verarbeitung und Entfernung

Die Erweiterung sendet Aktivitätszustände, Messwerte sowie den kurzen Titel und Text erkannter Hinweise über eine gekoppelte Verbindung auf diesem Mac. Claw’d benötigt weder ein Claude-Passwort noch einen API-Schlüssel. Die Sprechblasen werden nicht als Nachrichtenverlauf gespeichert.

Zum Entfernen zunächst eingerichtete Claude-Code-Anbindungen unter **Verbindungen** entfernen. Deaktiviere die Browser-Verbindung, trenne die Kopplung im Erweiterungsmenü und entferne die entpackte Erweiterung im Chromium-Browser bzw. deaktiviere sie in Safari. Beende Claw’d über das Menüleistensymbol. Danach kannst du die App löschen.

## Quellcode und Build

Im Stammverzeichnis des Repositorys liegt das vollständige Swift-Projekt mit beiden Browser-Erweiterungen. Die Datei **Package.swift** lässt sich in Xcode öffnen. Die folgende Befehlsfolge baut mit Xcode 15.3 oder neuer die komplette App samt Safari-Erweiterung und Ressourcen.

~~~bash
./Scripts/build-mac.sh
open ".build/app/Clawd Companion.app"
~~~

Für die Tests stehen folgende Befehle bereit. Die Swift- und Browser-Tests verwenden lokale Testdaten. Der Integrationstest richtet ein temporäres Benutzerverzeichnis ein.

~~~bash
swift test
node --test BrowserTests/*.test.js
python3 Scripts/test-hooks.py
~~~
