import SwiftUI
import AppKit

struct SmallLabel: View {
    var text: String
    var body: some View {
        Text(L(text).uppercased(with: L10n.locale)).font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(["de", "en", "es", "fr", "pt", "id"].contains(L10n.locale.language.languageCode?.identifier ?? "") ? 1.2 : 0)
            .foregroundStyle(Ink.dim)
    }
}

private struct PanelButton: ButtonStyle {
    var accent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 11).padding(.vertical, 7)
            .foregroundStyle(accent ? Ink.base : Ink.cream)
            .background(RoundedRectangle(cornerRadius: 8).fill(accent ? Ink.coral : Ink.control))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Rectangle())
    }
}

/// A small pixel landscape and window ledge for the live sprite.
private struct NightWindow: View {
    var body: some View {
        Canvas { context, size in
            let width = size.width, height = size.height
            let step: CGFloat = 3
            func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: Color) {
                context.fill(Path(CGRect(x: x, y: y, width: w, height: h)), with: .color(color))
            }
            let pink = Ink.pair(0xad7864, 0x7a5761)
            for (x, y) in [(0.08,0.22),(0.21,0.13),(0.38,0.35),(0.46,0.16),(0.54,0.39),
                           (0.59,0.18),(0.74,0.09),(0.87,0.18),(0.93,0.48),(0.66,0.37),(0.32,0.68)] {
                rect(floor(width*x/step)*step, floor(height*y/step)*step, step, step, pink.opacity(0.75))
            }
            let skyline: [CGFloat] = [25,19,32,39,30,25,31,43,34,25,12,21,34,48,42,30,35,24,41,48,37,24,18,29]
            let cell = ceil(width / CGFloat(skyline.count))
            for (i, h) in skyline.enumerated() {
                rect(CGFloat(i)*cell, height-h, cell+1, h, Ink.pair(0xdfcbbb, 0x382e38))
            }
            let x = width - 155, y = height - 36
            rect(x+3, y, 135, 36, Ink.pair(0xf1dccc, 0x332b33))
            rect(x, y, 139, 3, pink)
            rect(x, y+3, 3, 33, pink); rect(x+136, y+3, 3, 33, pink)
            rect(x+3, y+13, 133, 2, pink.opacity(0.62))
            for i in 0..<3 { rect(x+9+CGFloat(i*7), y+6, 3, 3, [Ink.coral, Ink.dim, Ink.mint][i].opacity(0.7)) }
        }.accessibilityHidden(true)
    }
}

private struct SceneHeader: View {
    @ObservedObject var state: CompanionState
    var body: some View {
        ZStack(alignment: .leading) {
            LinearGradient(colors: [Ink.pair(0xf0dece, 0x2e252b),
                                    Ink.pair(0xffefe0, 0x40303b)],
                           startPoint: .bottomLeading, endPoint: .topTrailing)
            NightWindow().scaleEffect(x: L10n.isRTL ? -1 : 1, y: 1)
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    SmallLabel(text: "Desktop Companion")
                    Text("Claw’d").font(.system(size: 53, weight: .medium, design: .serif)).tracking(-2.6)
                        .foregroundStyle(Ink.cream)
                    HStack(spacing: 6) {
                        Circle().fill(state.activitySource == "Claw’d" ? Ink.dim : Ink.mint).frame(width: 6, height: 6)
                        Text(L(state.presentedLabel)).font(.system(size: 12, weight: .medium)).lineLimit(2)
                    }.foregroundStyle(Ink.cream)
                    if state.activitySource != "Claw’d" {
                        Text(L(state.activitySource)).font(.system(size: 10)).foregroundStyle(Ink.dim)
                    }
                }.padding(.leading, 22).padding(.trailing, 4)
                Spacer(minLength: 0)
                MascotArt(pose: state.presentedPose, reducedMotion: state.quiet, agentCount: state.activeAgentCount).frame(width: 126, height: 108)
                    .padding(.trailing, 23).offset(y: 0)
            }
        }.frame(height: 148)
            .clipShape(RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(Ink.line))
    }
}

private struct QuotaCard: View {
    let title: String
    let window: LimitWindow?
    let now: Date
    var latestObservation: Date?
    private var percent: String {
        guard let value = window?.remaining else { return "–" }
        return (value / 100).formatted(.percent.precision(.fractionLength(0...1)).locale(L10n.locale))
    }
    private var caption: String {
        guard let window else { return L("Kein aktueller Messwert") }
        if let date = window.reset {
            let calendar = Calendar.current
            let time = date.formatted(.dateTime.hour().minute().locale(L10n.locale))
            let day: String
            if calendar.isDate(date, inSameDayAs: now) { day = L("heute") }
            else if calendar.isDate(date, inSameDayAs: calendar.date(byAdding: .day, value: 1, to: now) ?? now) { day = L("morgen") }
            else { day = date.formatted(.dateTime.day().month(.abbreviated).locale(L10n.locale)) }
            return L("{0} {1}, {2}", L(window.resetPrefix), day, time)
        }
        if let label = window.resetLabel, !label.isEmpty { return L("Beim Abruf · {0}", label) }
        return L("Resetzeit unbekannt")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(L(title)).font(.system(size: 13, weight: .semibold)).foregroundStyle(Ink.cream)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(percent).font(.system(size: 29, weight: .medium, design: .rounded)).monospacedDigit()
                    .foregroundStyle(window == nil ? Ink.dim : Ink.cream)
                if window != nil { Text(L("frei")).font(.system(size: 11)).foregroundStyle(Ink.dim) }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Ink.control)
                    if let value = window?.remaining {
                        Capsule().fill(value <= 15 ? Ink.coral : Ink.mint)
                            .frame(width: geo.size.width * min(max(0, value), 100)/100)
                    }
                }
            }.frame(height: 4)
            Text(caption).font(.system(size: 11)).foregroundStyle(Ink.dim)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            if let seen = window?.observedAt, let latestObservation,
               latestObservation.timeIntervalSince(seen) >= 60 {
                Text(L("Stand {0}", seen.formatted(.dateTime.day().month().hour().minute().locale(L10n.locale))))
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(Ink.dim)
            }
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Ink.card))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Ink.line))
            .accessibilityElement(children: .combine)
    }
}

private struct ControlRow<Control: View>: View {
    let title: String
    let detail: String
    @ViewBuilder var control: () -> Control
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L(title)).foregroundStyle(Ink.cream).font(.system(size: 13, weight: .semibold))
                Text(L(detail)).foregroundStyle(Ink.dim).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            control()
        }.padding(.vertical, 6)
    }
}

struct CompanionPanel: View {
    @AppStorage("appearance") private var appearance = "system"
    @ObservedObject var state: CompanionState

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                ForEach(PanelPage.allCases, id: \.self) { page in
                    Button {
                        state.page = page
                        state.feedback = nil
                        if page == .connections || page == .overlay { state.refreshIntegrations() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: page == .companion ? "face.smiling" : page == .connections ? "link" : page == .info ? "info.circle" : page == .highscores ? "trophy" : "macwindow")
                            Text(L(page.rawValue)).lineLimit(2).minimumScaleFactor(0.85)
                        }.font(.system(size: 12, weight: .semibold)).frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .foregroundStyle(state.page == page ? Ink.cream : Ink.dim)
                            .background(RoundedRectangle(cornerRadius: 8).fill(state.page == page ? Ink.card : .clear))
                    }.buttonStyle(.plain).accessibilityAddTraits(state.page == page ? .isSelected : [])
                }
            }.padding(.horizontal, 16).padding(.vertical, 10)
            Rectangle().fill(Ink.line).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if state.page != .info {
                        ReleaseNoticeRow(updates: state.updates) { state.page = .info }
                    }
                    switch state.page {
                    case .companion: overview
                    case .connections: connections
                    case .overlay: overlayPage
                    case .highscores: ArenaHighscoresView(state: state)
                    case .info: ReleaseInfoView(updates: state.updates)
                    }
                    if let message = state.feedback {
                        HStack(alignment: .top) {
                            Text(L(message)).font(.system(size: 12)).foregroundStyle(Ink.cream)
                                .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                            Button { state.feedback = nil } label: { Image(systemName: "xmark") }
                                .buttonStyle(.plain).accessibilityLabel(L("Hinweis schließen"))
                        }.padding(12).background(RoundedRectangle(cornerRadius: 8).fill(Ink.card))
                    }
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.frame(minWidth: 438, minHeight: 475).background(Ink.base)
            .foregroundStyle(Ink.cream).tint(Ink.coral).onChange(of: appearance) { CompanionAppearance.apply($0) }
            .environment(\.locale, L10n.locale)
            .environment(\.layoutDirection, L10n.isRTL ? .rightToLeft : .leftToRight)
    }

    @ViewBuilder private var overview: some View {
        SceneHeader(state: state)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                title(L("Kontingent"))
                Spacer()
                Menu {
                    ForEach(QuotaSource.allCases, id: \.self) { source in
                        Button { state.quotaSource = source } label: {
                            if state.quotaSource == source { Label(source.rawValue, systemImage: "checkmark") }
                            else { Text(source.rawValue) }
                        }
                    }
                } label: { Text(state.quotaSource.rawValue) }
                    .menuStyle(.borderlessButton).fixedSize().foregroundStyle(Ink.dim)
                    .accessibilityLabel(L("Kontingentquelle, {0}", state.quotaSource.rawValue))
            }
            HStack(alignment: .top, spacing: 9) {
                QuotaCard(title: "5-Stunden-Fenster", window: state.selectedReport?.current(weekly: false, at: state.now),
                          now: state.now, latestObservation: state.selectedReport?.seen)
                QuotaCard(title: "Wochenlimit", window: state.selectedReport?.current(weekly: true, at: state.now),
                          now: state.now, latestObservation: state.selectedReport?.seen)
            }
            if let seen = state.selectedReport?.seen {
                Text(L("Letzte Messung · {0} Uhr", seen.formatted(.dateTime.day().month().hour().minute().locale(L10n.locale))))
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(Ink.dim)
            }
            if state.quotaSource == .desktop {
                if state.desktopUsageEnabled {
                    desktopUsageActions
                } else {
                    connectDesktopButton
                }
            } else if state.quotaSource == .browser && state.webConnected {
                usageMenu
            } else if state.quotaSource == .code && state.quotaInstalled && state.selectedReport == nil {
                Text(L("Öffne eine neue Claude-Code-Sitzung. Nach der ersten Antwort erscheinen verfügbare Limits hier."))
                    .font(.system(size: 12)).foregroundStyle(Ink.dim)
            } else if state.selectedReport == nil {
                Button { state.page = .connections } label: {
                    Label(L(state.quotaSource == .browser ? "Claude.ai verbinden" : "Claude Code verbinden"), systemImage: "link")
                }.buttonStyle(PanelButton())
                if !state.desktopUsageEnabled { connectDesktopButton }
            }
        }
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SmallLabel(text: "Mit Claw’d spielen")
                Spacer()
                Menu(L("Aktionsvorschau")) {
                    ForEach([MascotPose.typing, .planning, .researching, .reading, .executing, .drawing], id: \.self) { pose in
                        Button(pose.accessibilityDescription) { state.play(pose) }
                    }
                }.fixedSize().controlSize(.small).disabled(state.isAwaitingApproval || state.arcadeOwnsMascot)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 7) { playActions }.fixedSize(horizontal: true, vertical: false)
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 7) {
                    playActions
                }
            }
            HStack(spacing: 14) {
                score(state.playScore.hits, "Treffer", color: Ink.coral)
                Rectangle().fill(Ink.line).frame(width: 1, height: 30)
                score(state.playScore.dodges, "Ausgewichen", color: Ink.mint)
                Spacer(minLength: 4)
                Menu {
                    Button(L("Codebogen spannen")) { state.startBow() }
                    Button(L("Buchstabensalve testen")) { state.startBow(letters: true) }
                } label: {
                    Label(L("Codebogen"), systemImage: "cursorarrow.rays")
                        .font(.system(size: 12, weight: .semibold))
                } primaryAction: { state.startBow() }
                .fixedSize().disabled(state.bowUnavailableReason != nil)
                .help(L(state.bowUnavailableReason ?? "Klicke für den Codebogen. Im Aufklappmenü wartet der Buchstabenblaster."))
            }.padding(12).background(RoundedRectangle(cornerRadius: 10).fill(Ink.card))
            if state.arcadeEnabled || state.arcadeOwnsMascot {
                HStack(spacing: 10) {
                    Image(systemName: "gamecontroller").foregroundStyle(Ink.mint).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L("Virenarena")).font(.system(size: 13, weight: .semibold))
                        Text(state.arcadeStatusLabel).font(.system(size: 12)).monospacedDigit().foregroundStyle(Ink.dim)
                    }.accessibilityElement(children: .combine)
                    Spacer(minLength: 0)
                    if state.canRequestArcade {
                        Button(L(state.arcadeWhileActive ? "Arcade starten" : "Für den Leerlauf vormerken")) { state.requestArcade() }
                            .buttonStyle(PanelButton())
                    }
                }.padding(12).background(RoundedRectangle(cornerRadius: 10).fill(Ink.card))
            }
        }
    }

    @ViewBuilder private var playActions: some View {
        Group {
            action("Klettern", "arrow.up.right", .climbing)
            action("Abseilen", "arrow.down", .rappelling)
            action("Streicheln", "heart", .happy)
        }.disabled(state.isAwaitingApproval || state.arcadeOwnsMascot)
        Button(L(state.previewingApproval ? "Einrollen" : "OK?-Schild")) { state.toggleApprovalPreview() }
            .buttonStyle(PanelButton())
            .disabled(state.arcadeOwnsMascot || (state.isAwaitingApproval && !state.previewingApproval))
            .help(L("Spielt die Schildanimation zur Probe. Erneut klicken, um das Schild einzurollen."))
    }

    private func score(_ value: Int, _ label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value.formatted(.number.locale(L10n.locale))).font(.system(size: 20, weight: .semibold, design: .monospaced))
                .monospacedDigit().foregroundStyle(color)
            Text(L(label)).font(.system(size: 11)).foregroundStyle(Ink.dim)
        }.accessibilityElement(children: .combine)
    }

    private var connectDesktopButton: some View {
        Button {
            state.page = .connections
        } label: {
            Label(L("Claude Desktop verbinden"), systemImage: "macwindow")
        }.buttonStyle(PanelButton())
    }

    private var desktopUsageMessage: String {
        switch state.desktopUsageStatus {
        case .disabled: return "Verbindung mit Claude Desktop aktivieren"
        case .checking: return "Nutzungsanzeige wird geprüft …"
        case .needsPermission: return "Erlaube Claw’d unter Datenschutz & Sicherheit → Bedienungshilfen den Zugriff."
        case .notRunning: return "Starte die Claude-App und öffne Einstellungen → Nutzung."
        case .identityUnavailable: return "macOS konnte Claude Desktop nicht als Anthropic-App bestätigen."
        case .unavailable: return "Öffne in der Claude-App Einstellungen → Nutzung und lass die Seite kurz geöffnet."
        case .ready: return "Nutzungsdaten aus der Claude-App übernommen."
        }
    }

    @ViewBuilder private var desktopUsageActions: some View {
        Text(L(desktopUsageMessage)).font(.system(size: 12)).foregroundStyle(Ink.dim)
            .fixedSize(horizontal: false, vertical: true)
        HStack(spacing: 8) {
            if state.desktopUsageStatus == .needsPermission {
                Button(L("Zugriff erlauben …")) { state.requestDesktopUsageAccess() }
                    .buttonStyle(PanelButton(accent: true))
            } else if (state.desktopUsageStatus == .notRunning || state.desktopUsageStatus == .unavailable),
                      let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: ClaudeDesktopUsageReader.bundleIdentifier) {
                Button(L("Claude Desktop öffnen")) {
                    NSWorkspace.shared.openApplication(at: app, configuration: .init())
                }.buttonStyle(PanelButton())
            }
            Button(L("Jetzt einlesen")) { state.refreshDesktopUsage() }
                .disabled(state.desktopUsageStatus == .checking).buttonStyle(PanelButton())
        }
    }

    @ViewBuilder private var connections: some View {
        VStack(alignment: .leading, spacing: 8) {
            title("Claude Desktop")
            ControlRow(title: "Kontingent aus der Claude-App", detail: "Liest die angezeigten Limits unter Einstellungen → Nutzung.") {
                Toggle(L("Verbindung mit Claude Desktop aktivieren"), isOn: $state.desktopUsageEnabled)
                    .labelsHidden().toggleStyle(.switch)
            }
            if state.desktopUsageEnabled { desktopUsageActions }
        }
        Rectangle().fill(Ink.line).frame(height: 1)
        VStack(alignment: .leading, spacing: 8) {
            title(L("Claude.ai verbinden"))
            Text(L("Claw’d reagiert auf Antworten und Hinweise im gekoppelten Browser. Öffne die Nutzungsseite, um das Kontingent zu übernehmen."))
                .font(.system(size: 13)).foregroundStyle(Ink.dim)
            ControlRow(title: L("Browser-Verbindung"), detail: state.bridgeIssue ?? (state.webConnected ? L("Erweiterung verbunden") : state.browserRunning ? L("Wartet auf die Erweiterung") : L("Lokale Kopplung mit diesem Mac"))) {
                Toggle(L("Browser-Verbindung"), isOn: $state.webEnabled).labelsHidden().toggleStyle(.switch)
            }
            if state.webEnabled {
                Picker(L("Browser"), selection: $state.safariSetup) {
                    Text("Chrome · Edge · Brave").tag(false)
                    Text("Safari").tag(true)
                }.pickerStyle(.segmented)
                if state.safariSetup {
                    step("1", L("Aktiviere in Safari unter Einstellungen → Erweiterungen „Claw’d“ und erlaube den Zugriff auf claude.ai."))
                    Text(L("Für diese lokal signierte Version braucht Safari die Entwickleroption „Unsignierte Erweiterungen erlauben“. Nach einem Safari-Neustart muss die Option erneut aktiviert werden."))
                        .font(.system(size: 12)).foregroundStyle(Ink.dim)
                } else {
                    step("1", L("Aktiviere auf der Erweiterungsseite deines Browsers den Entwicklermodus. Wähle „Entpackte Erweiterung laden“."))
                Button(L("Erweiterungsordner zeigen und Pfad kopieren")) { state.revealExtension() }.buttonStyle(PanelButton())
                }
                step("2", L("Öffne Claw’d in der Browser-Symbolleiste und füge den Kopplungscode ein. Lade offene Claude-Tabs einmal neu."))
                Button(L("Kopplungscode kopieren")) { state.copyPairingToken() }.buttonStyle(PanelButton(accent: true))
                    .disabled(!state.browserRunning)
                step("3", L("Öffne die Nutzungsseite im gekoppelten Browser. Beim nächsten Besuch aktualisiert Claw’d die Anzeige."))
                usageMenu
            }
        }
        Rectangle().fill(Ink.line).frame(height: 1)
        VStack(alignment: .leading, spacing: 8) {
            title("Claude Code")
            Text(L("Optional für lokale Terminalsitzungen. Die beiden Schalter ergänzen deine Claude-Code-Benutzereinstellungen."))
                .font(.system(size: 13)).foregroundStyle(Ink.dim)
            ControlRow(title: L("Aktivität und Subagents"), detail: L("Bei einer ausstehenden Freigabe zeigt Claw’d sein OK?-Schild. Mit aktiven Subagents jongliert er.")) {
                Button(state.hooksInstalled ? L("Entfernen") : L("Einrichten")) { state.toggleIntegration(hooks: true) }.buttonStyle(PanelButton())
            }
            if state.hooksNeedUpgrade {
                HStack {
                    Text(L("Aktualisiere die Anbindung für Freigaben, Subagents und die neuen Werkzeuganimationen."))
                        .font(.system(size: 12)).foregroundStyle(Ink.dim)
                    Spacer()
                    Button(L("Aktualisieren")) { state.upgradeHooks() }.buttonStyle(PanelButton(accent: true))
                }
            }
            ControlRow(title: L("Kontingent"), detail: L("Liest die Statuszeile nach der ersten Antwort aus, wenn Claude dort Limits meldet.")) {
                Button(state.quotaInstalled ? L("Entfernen") : L("Einrichten")) { state.toggleIntegration(hooks: false) }.buttonStyle(PanelButton())
            }
        }
    }

    @ViewBuilder private var overlayPage: some View {
        title(L("Auf dem Schreibtisch"))
        VStack(alignment: .leading, spacing: 8) {
            Picker(L("Darstellung"), selection: $appearance) {
                Text(L("Wie das System")).tag("system")
                Text(L("Hell")).tag("light")
                Text(L("Dunkel")).tag("dark")
            }.pickerStyle(.menu)
            Picker(L("Sprache"), selection: $state.language) {
                Text(L("Systemsprache")).tag("system")
                ForEach(L10n.choices, id: \.0) { item in Text(verbatim: item.1).tag(item.0) }
            }.pickerStyle(.menu)
            Divider()
            HStack {
                Text(L("Eigene Meldungen vorlesen")).font(.system(size: 13, weight: .semibold))
                Spacer()
                Toggle(L("Eigene Meldungen vorlesen"), isOn: $state.voiceEnabled).labelsHidden().toggleStyle(.switch)
            }
            if state.voiceEnabled {
                if ClawdVoice.hasVoice(for: L10n.code) {
                    Button(L("Stimme testen")) { state.previewVoice() }.buttonStyle(PanelButton())
                } else {
                    Text(L("Für diese Sprache ist auf dem Mac keine passende Stimme verfügbar."))
                        .font(.system(size: 12)).foregroundStyle(Ink.dim)
                }
            }
        }.padding(14).background(RoundedRectangle(cornerRadius: 12).fill(Ink.card))
        VStack(spacing: 8) {
            ControlRow(title: L("Figur einblenden"), detail: L("Klicke Claw’d an, um dieses Fenster zu öffnen. Ziehe die Figur an einen anderen Platz.")) {
                Toggle(L("Figur einblenden"), isOn: $state.showOverlay).labelsHidden().toggleStyle(.switch)
            }
            Divider()
            ControlRow(title: L("An Fenstern klettern"), detail: L("Beim Spazieren entdeckt Claw’d freie Fensterkanten, klettert hinauf und springt wieder herunter. Für Claude-Aktionen kann er zusätzlich dem aktiven Fenster folgen.")) {
                Toggle(L("An Fenstern klettern"), isOn: $state.follow).labelsHidden().toggleStyle(.switch)
            }
            if state.follow {
                HStack {
                    Label(state.accessibility ? L("Aktives Fenster erkennbar") : L("Aktives Fenster für Claude-Aktionen"),
                          systemImage: state.accessibility ? "checkmark.circle" : "macwindow")
                        .foregroundStyle(state.accessibility ? Ink.mint : Ink.dim)
                    Spacer()
                    if !state.accessibility {
                        Button(L("Zugriff erlauben …")) { state.askAccessibility() }.buttonStyle(PanelButton())
                    }
                }.font(.system(size: 12))
            }
            Divider()
            if state.pinned {
                ControlRow(title: L("Am Fenster angeheftet"), detail: L("Claw’d kehrt nach dem Abseilen zum Pin zurück.")) {
                    Button(L("Pin lösen")) { state.releasePin() }.buttonStyle(PanelButton())
                }
            } else {
                Text(L("Zum Anheften ziehst du Claw’d auf ein Fenster und wählst per Rechtsklick „{0}“.", L("Pin to Window · An Fenster heften")))
                    .font(.system(size: 12)).foregroundStyle(Ink.dim).frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            ControlRow(title: L("Sprechblasen"), detail: L("Zeigt kurze Claude.ai-Meldungen neben der Figur, auch wenn dieses Fenster geschlossen ist.")) {
                Toggle(L("Sprechblasen"), isOn: $state.speechEnabled).labelsHidden().toggleStyle(.switch)
            }
            if state.speechEnabled {
                HStack {
                    Button(L("Sprechblase testen")) { state.testSpeech() }.buttonStyle(PanelButton())
                    Spacer()
                }
            }
            Divider()
            ControlRow(title: L("Bewegung reduzieren"), detail: L("Zeigt ruhige Posen. Die Systemeinstellung gilt ebenfalls.")) {
                Toggle(L("Bewegung reduzieren"), isOn: $state.quiet).labelsHidden().toggleStyle(.switch)
            }
            Divider()
            HStack {
                Text(L("Figurgröße")).font(.system(size: 13, weight: .semibold))
                Spacer()
                Slider(value: $state.scale, in: 0.7...1.65, step: 0.05).frame(width: 145)
                    .accessibilityLabel(L("Figurgröße"))
                Text(state.scale.formatted(.percent.precision(.fractionLength(0)).locale(L10n.locale))).monospacedDigit().frame(width: 46, alignment: .trailing)
            }.font(.system(size: 12)).padding(.vertical, 8)
        }.padding(14).background(RoundedRectangle(cornerRadius: 12).fill(Ink.card))
        VStack(alignment: .leading, spacing: 8) {
            SmallLabel(text: L("Verhalten und Spiel"))
            ControlRow(title: L("Spazieren"), detail: L("Claw’d läuft in Arbeitspausen über den Schreibtisch.")) {
                Toggle(L("Spazieren"), isOn: $state.roam).labelsHidden().toggleStyle(.switch)
            }
            Divider()
            ControlRow(title: L("Mauszeiger jagen"), detail: L("Folgt dem Zeiger gelegentlich ein Stück und lässt sich weiterhin anklicken.")) {
                Toggle(L("Mauszeiger jagen"), isOn: $state.chase).labelsHidden().toggleStyle(.switch)
            }
            Divider()
            ControlRow(title: L("Codebogen und Buchstabenblaster"), detail: L("Claw’d verfolgt deinen Mauszeiger und feuert pro Salve 3 bis 42 kleine Pixelbuchstaben. Weiche ihrer Flugbahn aus.")) {
                Toggle(L("Codebogen und Buchstabenblaster"), isOn: $state.bow).labelsHidden().toggleStyle(.switch)
            }
        }.padding(14).background(RoundedRectangle(cornerRadius: 12).fill(Ink.card))
        VStack(alignment: .leading, spacing: 4) {
            SmallLabel(text: "Virenarena")
            ControlRow(title: "Im Leerlauf spielen", detail: "Nach 90 Sekunden ohne Maus oder Tastatur darf Claw’d eine Runde beginnen.") {
                Toggle(L("Im Leerlauf spielen"), isOn: $state.arcadeEnabled).labelsHidden().toggleStyle(.switch)
            }
            Divider()
            ControlRow(title: "Auch bei aktiver Nutzung spielen", detail: "Claw’d spielt weiter, während du den Mac benutzt. Dann kannst du Gegner und Power-ups anklicken.") {
                Toggle(L("Auch bei aktiver Nutzung spielen"), isOn: $state.arcadeWhileActive).labelsHidden().toggleStyle(.switch)
            }.disabled(!state.arcadeEnabled)
        }.padding(14).background(RoundedRectangle(cornerRadius: 12).fill(Ink.card))
        SoundSettingsView(state: state)
        Button(L("Figur zurückholen")) { state.showOverlay = true; state.resetPosition() }.buttonStyle(PanelButton())
    }

    private var usageMenu: some View {
        Menu {
            Button(L("Im Standardbrowser öffnen")) { state.openUsage() }
            ForEach(["com.apple.Safari", "com.google.Chrome", "com.microsoft.edgemac", "com.brave.Browser"], id: \.self) { id in
                if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                    Button(L("In {0} öffnen", app.deletingPathExtension().lastPathComponent)) { state.openUsage(in: id) }
                }
            }
        } label: { Label(L("Nutzungsseite öffnen"), systemImage: "arrow.up.right.square") }
            .fixedSize()
    }
    private func title(_ text: String) -> some View { Text(text).font(.system(size: 21, weight: .semibold)).tracking(-0.55) }
    private func step(_ n: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(Int(n)?.formatted(.number.locale(L10n.locale)) ?? n).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(Ink.coral)
            Text(text).font(.system(size: 12)).foregroundStyle(Ink.dim).fixedSize(horizontal: false, vertical: true)
        }.padding(.top, 3)
    }
    private func action(_ label: String, _ symbol: String, _ pose: MascotPose) -> some View {
        Button { state.play(pose) } label: { Label(L(label), systemImage: symbol) }.buttonStyle(PanelButton())
    }
}
