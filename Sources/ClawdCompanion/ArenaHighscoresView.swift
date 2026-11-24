import SwiftUI

struct ArenaHighscoresView: View {
    @ObservedObject var state: CompanionState

    var body: some View {
        ArenaHighscoresContent(totals: state.arenaTotals, account: state.arenaAccount,
                               rankedLocked: !state.canStartRankedArena,
                               localArena: LocalArenaCard(state: state, manual: state.manualArena,
                                                         account: state.arenaAccount))
    }
}

private final class ArenaCredentialsForm: ObservableObject {
    @Published var registering = false
    @Published var name = ""
    @Published var email = ""
    @Published var password = ""
}

struct ArenaHighscoresContent: View {
    let totals: ArenaTotals
    @ObservedObject var account: ArenaAccountModel
    var rankedLocked = false
    var localArena: LocalArenaCard? = nil
    @StateObject private var form = ArenaCredentialsForm()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("Highscores")).font(.system(size: 22, weight: .semibold))
            localArena
            if let username = account.username {
                HStack {
                    Label(L("Angemeldet als {0}", username), systemImage: "person.crop.circle.fill")
                        .foregroundStyle(Ink.mint)
                    Spacer()
                    Button(L("Abmelden")) { Task { await account.logout() } }.disabled(account.busy)
                }.font(.system(size: 12))
                rankedRun
                if let me = account.player {
                    SmallLabel(text: "Dein Online-Ergebnis")
                    Grid(horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow {
                            metric("Punkte", me.score)
                            metric("Besiegte Viren", me.kills)
                            metric("Tode", me.deaths)
                        }
                        GridRow {
                            metric("Siege", me.wins)
                            metric("K/D", displayKD(me.kd))
                            Color.clear.frame(height: 1)
                        }
                    }
                }
                leaderboard
            } else {
                loginForm
            }
            if let message = account.message {
                Label(L(message), systemImage: "info.circle")
                    .font(.system(size: 12)).foregroundStyle(Ink.cream).textSelection(.enabled)
            }
            Rectangle().fill(Ink.line).frame(height: 1)
            SmallLabel(text: "Auf diesem Gerät")
            Grid(horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow { metric("Punkte", totals.points); metric("Besiegte Viren", totals.kills); metric("Tode", totals.deaths) }
                GridRow { metric("Siege", totals.wins); metric("Besiegte Bosse", totals.bossKills); metric("Runden", totals.rounds) }
                GridRow { metric("K/D", displayKD(totals.deaths > 0 ? Double(totals.kills) / Double(totals.deaths) : nil)); Color.clear.frame(height: 1); Color.clear.frame(height: 1) }
            }
        }
        .task { await account.appear() }
        .task(id: account.round?.playing == true) {
            guard account.round?.playing == true else { return }
            while !Task.isCancelled, account.round?.playing == true {
                await account.updateRound()
                do { try await Task.sleep(nanoseconds: 300_000_000) } catch { break }
            }
        }
        .onDisappear { form.password = "" }
    }

    private var loginForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            SmallLabel(text: "Online-Konto")
            Text(L("Für die Online-Rangliste und gewertete Runden anmelden."))
                .font(.system(size: 12)).foregroundStyle(Ink.dim)
            Picker(L("Online-Konto"), selection: $form.registering) {
                Text(L("Anmelden")).tag(false)
                Text(L("Registrieren")).tag(true)
            }.pickerStyle(.segmented).labelsHidden()
            TextField(form.registering ? L("Benutzername") : L("Benutzername oder E-Mail"), text: $form.name)
                .textContentType(.username)
            if form.registering {
                TextField(L("E-Mail"), text: $form.email)
            }
            SecureField(L("Passwort"), text: $form.password)
                .textContentType(.password)
                .onSubmit { if canSubmit { submit() } }
            if form.registering {
                Text(L("3–24 Zeichen für den Namen, 12–128 Zeichen für das Passwort."))
                    .font(.system(size: 11)).foregroundStyle(Ink.dim)
            }
            HStack {
                Button(form.registering ? L("Registrieren") : L("Anmelden")) { submit() }
                    .buttonStyle(.borderedProminent).disabled(!canSubmit)
                if account.busy { ProgressView().controlSize(.small) }
            }
        }.disabled(account.busy).textFieldStyle(.roundedBorder).padding(12)
            .background(RoundedRectangle(cornerRadius: 9).fill(Ink.card))
    }

    private var canSubmit: Bool {
        !account.busy && !form.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !form.password.isEmpty &&
            (!form.registering || ((3...24).contains(form.name.count) && (12...128).contains(form.password.count) &&
                           form.email.contains("@")))
    }

    private func submit() {
        let sentName = form.name, sentEmail = form.registering ? form.email : nil, sentPassword = form.password
        Task {
            await account.authenticate(name: sentName, email: sentEmail, password: sentPassword)
            if account.username != nil { form.password = ""; form.email = ""; form.name = "" }
        }
    }

    private func metric(_ key: String, _ number: Int) -> some View {
        metric(key, number.formatted(.number.locale(L10n.locale)))
    }

    private func metric(_ key: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.system(size: 18, weight: .semibold, design: .monospaced)).foregroundStyle(Ink.cream)
            Text(L(key)).font(.system(size: 10)).foregroundStyle(Ink.dim)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
            .background(RoundedRectangle(cornerRadius: 6).fill(Ink.card))
    }

    private func displayKD(_ value: Double?) -> String {
        value?.formatted(.number.precision(.fractionLength(0...2)).locale(L10n.locale)) ?? "—"
    }

    private var rankedRun: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                SmallLabel(text: "Gewertete Runde")
                Spacer()
                if account.round?.playing != true {
                    Button(L("Runde starten")) { Task { await account.startRound() } }.disabled(account.busy || rankedLocked)
                }
            }
            Text(L("Nur abgeschlossene Runden, in denen du selbst einen Gegner getroffen oder ein wirksames Power-up eingesammelt hast, zählen."))
                .font(.system(size: 12)).foregroundStyle(Ink.dim)
            if let round = account.round {
                if round.playing {
                    RankedArenaField(frame: round) { point in Task { await account.updateRound(tapping: point) } }
                }
                HStack {
                    Text(round.playing ? "" : L(round.phase == .victory ? "Boss besiegt" :
                        round.phase == .expired ? "Runde abgelaufen" : "Runde beendet"))
                    if !round.playing { Spacer() }
                    Text(L(round.ranked ? "Gewertete Aktion bestätigt" : "Noch keine gewertete Aktion"))
                        .foregroundStyle(round.ranked ? Ink.mint : Ink.dim)
                    Spacer()
                    Text(L("Punkte") + " " + String(round.score)).monospacedDigit()
                }.font(.system(size: 11))
            }
        }.padding(12).background(RoundedRectangle(cornerRadius: 9).fill(Ink.card))
    }

    private var leaderboard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                SmallLabel(text: "Online-Rangliste")
                Spacer()
                Button(L("Aktualisieren")) { Task { await account.refresh() } }.disabled(account.busy)
            }
            if account.leaders.isEmpty {
                if account.busy { ProgressView().controlSize(.small) }
                else if account.player != nil { Text(L("Noch keine gewerteten Runden.")).font(.caption).foregroundStyle(Ink.dim) }
            } else {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 7) {
                    GridRow {
                        Text(L("Platz")); Text(L("Spieler")); Text(L("Kills")); Text(L("Tode"))
                        Text(L("K/D")); Text(L("Punkte"))
                    }.font(.system(size: 10, weight: .semibold)).foregroundStyle(Ink.dim)
                    ForEach(account.leaders) { entry in
                        GridRow {
                            Text(entry.rank.map(String.init) ?? "–")
                            Text(entry.username).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                            Text(String(entry.kills)); Text(String(entry.deaths)); Text(displayKD(entry.kd)); Text(String(entry.score))
                        }.foregroundStyle(entry.username == account.username ? Ink.mint : Ink.cream)
                    }
                }.font(.system(size: 12)).monospacedDigit()
            }
        }
    }
}

struct LocalArenaCard: View {
    @ObservedObject var state: CompanionState
    @ObservedObject var manual: ManualArena
    @ObservedObject var account: ArenaAccountModel

    private var visibleFrame: VirusArcade.Frame? {
        guard let frame = manual.frame else { return nil }
        if frame.phase == .dead {
            guard case .grave(let until) = state.arcadeStatus, until > Date() else { return nil }
        }
        return frame
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            SmallLabel(text: "Lokale Arena")
            Text(L("Klicke auf Viren und Power-ups. Nur selbst gespielte Runden zählen."))
                .font(.system(size: 12)).foregroundStyle(Ink.dim)
            HStack {
                if manual.playing {
                    Button(L(manual.paused ? "Runde fortsetzen" : "Runde pausieren")) {
                        if manual.paused { manual.resume(now: ProcessInfo.processInfo.systemUptime) }
                        else { manual.pause() }
                    }
                    Button(L("Lokale Runde beenden")) { manual.end() }
                } else {
                    Button(L("Lokale Runde starten")) { state.startManualArena() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!state.canStartManualArena || account.round?.playing == true)
                }
            }
            if let frame = visibleFrame {
                PixelArenaField(frame: frame, label: L("Lokale Arena"), acceptsInput: manual.playing && !manual.paused) {
                    manual.tap($0)
                }
                if frame.phase == .victory {
                    Text(L("Sieg!")).font(.caption).foregroundStyle(Ink.mint)
                } else if frame.phase != .dead {
                    Text(L("Welle {0} · {1} LP", String(frame.wave), String(frame.playerHP)))
                        .font(.caption).foregroundStyle(Ink.dim)
                }
            }
            if case .grave(let until) = state.arcadeStatus {
                TimelineView(.periodic(from: .now, by: 1)) { clock in
                    let seconds = Int(max(0, ceil(until.timeIntervalSince(clock.date))))
                    Text(L("Auferstehung in {0}", String(format: "%d:%02d", seconds / 60, seconds % 60)))
                        .font(.caption).monospacedDigit().foregroundStyle(Ink.dim)
                }
            }
        }.padding(12).background(RoundedRectangle(cornerRadius: 9).fill(Ink.card))
            .background(ArenaWindowFocus(didResign: manual.pause))
            .task(id: manual.playing && !manual.paused) {
                while !Task.isCancelled && manual.playing && !manual.paused {
                    manual.tick(now: ProcessInfo.processInfo.systemUptime)
                    do { try await Task.sleep(nanoseconds: 33_333_333) } catch { return }
                }
            }
            .onDisappear { manual.pause() }
    }
}

private struct ArenaWindowFocus: NSViewRepresentable {
    let didResign: () -> Void
    func makeNSView(context: Context) -> Observer {
        let view = Observer()
        view.didResign = didResign
        return view
    }
    func updateNSView(_ view: Observer, context: Context) { view.didResign = didResign }

    final class Observer: NSView {
        var didResign: (() -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self)
            guard let window else { return }
            NotificationCenter.default.addObserver(self, selector: #selector(resigned(_:)), name: NSWindow.didResignKeyNotification, object: window)
        }
        @objc private func resigned(_ notification: Notification) { didResign?() }
        deinit { NotificationCenter.default.removeObserver(self) }
    }
}

private struct PixelArenaField: View {
    let frame: VirusArcade.Frame
    let label: String
    let acceptsInput: Bool
    let tap: (CGPoint) -> Void

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                context.withCGContext { cg in
                    cg.saveGState()
                    let scale = min(size.width / 300, size.height / 160)
                    cg.translateBy(x: (size.width - 300 * scale) / 2, y: (size.height - 160 * scale) / 2)
                    cg.scaleBy(x: scale, y: scale)
                    cg.translateBy(x: 0, y: 160)
                    cg.scaleBy(x: 1, y: -1)
                    VirusArenaPixels.draw(frame, in: cg)
                    cg.translateBy(x: frame.hero.x - 24, y: frame.hero.y + 20.5)
                    cg.scaleBy(x: 1, y: -1)
                    let pose: MascotPose = frame.phase == .dead ? .grave : frame.phase == .victory ? .virusVictory : .virusFight
                    MascotPixels.draw(in: cg, size: CGSize(width: 48, height: 41), pose: pose,
                                      facingLeft: false, frame: Int(frame.time * 8))
                    cg.restoreGState()
                }
            }.background(Ink.base)
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture().onEnded { value in
                    guard acceptsInput else { return }
                    let size = geometry.size, scale = min(size.width / 300, size.height / 160)
                    guard scale > 0 else { return }
                    let point = CGPoint(x: (value.location.x - (size.width - 300 * scale) / 2) / scale,
                                        y: 160 - (value.location.y - (size.height - 160 * scale) / 2) / scale)
                    guard point.x >= 0, point.x < 300, point.y >= 0, point.y < 160 else { return }
                    tap(point)
                })
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label)
                .accessibilityValue(L("Welle {0} · {1} LP", String(frame.wave), String(frame.playerHP)))
                .accessibilityActions {
                    if acceptsInput {
                        ForEach(frame.enemies, id: \.id) { enemy in
                            Button(L(enemy.kind == .boss ? "Endboss" : "Pixelvirus") + " " + String(enemy.id)) {
                                hit(.enemy(enemy.id), at: enemy.position, radius: enemy.radius)
                            }
                        }
                        ForEach(frame.pickups, id: \.id) { pickup in
                            Button(L(pickup.kind == .shield ? "Schild" : pickup.kind == .rapidFire ? "Schnellfeuer" : "Heilung")) {
                                hit(.pickup(pickup.id), at: pickup.position, radius: pickup.radius)
                            }
                        }
                    }
                }
        }.frame(maxWidth: .infinity).frame(height: 196).clipShape(RoundedRectangle(cornerRadius: 7))
    }

    // Some sprites have transparent centers. Find visible ink of this target, including when sprites overlap.
    private func hit(_ target: VirusArenaPixels.Target, at center: CGPoint, radius: CGFloat) {
        if VirusArenaPixels.target(at: center, in: frame)?.target == target { tap(center); return }
        for y in stride(from: center.y - radius, through: center.y + radius, by: 1) {
            for x in stride(from: center.x - radius, through: center.x + radius, by: 1) {
                let p = CGPoint(x: x, y: y)
                if VirusArenaPixels.target(at: p, in: frame)?.target == target { tap(p); return }
            }
        }
    }
}

private struct RankedArenaField: View {
    let frame: ArenaOnlineFrame
    let tap: (CGPoint) -> Void

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.125)) { clock in
            let time = clock.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 4096)
            PixelArenaField(frame: displayFrame(seconds: time), label: L("Gewertete Runde"), acceptsInput: frame.playing) {
                tap(CGPoint(x: $0.x, y: 160 - $0.y))
            }
        }
    }

    private func displayFrame(seconds: Double) -> VirusArcade.Frame {
        func position(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: 160-y) }
        let enemies = frame.enemies.map { enemy in
            let kind: VirusArcade.Kind
            switch enemy.kind { case "boss": kind = .boss; case "worm": kind = .worm; case "spore": kind = .spore; default: kind = .bug }
            return VirusArcade.Enemy(id: enemy.id, kind: kind, position: position(enemy.x, enemy.y), radius: enemy.radius,
                                     hp: enemy.hp, maxHP: enemy.maxHP, hurt: 0)
        }
        let items = frame.pickups.map { item in
            VirusArcade.Pickup(id: item.id, kind: item.kind == "shield" ? .shield : item.kind == "rapidFire" ? .rapidFire : .restore,
                               position: position(item.x, item.y), radius: item.radius)
        }
        let shots = frame.shots.enumerated().map { i, shot in
            VirusArcade.Shot(id: i, hostile: shot.hostile, position: position(shot.x, shot.y))
        }
        return VirusArcade.Frame(phase: frame.phase == .boss ? .boss : .wave, wave: frame.wave, playerHP: frame.hp,
                                 hero: position(frame.hero.x, frame.hero.y), enemies: enemies, shots: shots, time: seconds,
                                 heroHurt: 0, heroFiring: false, event: nil, cues: [], pickups: items, shield: 0,
                                 rapidFire: 0, enemyTotal: enemies.count, defeated: 0)
    }
}
