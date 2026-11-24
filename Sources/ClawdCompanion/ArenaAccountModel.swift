import Foundation
import SwiftUI

@MainActor
final class ArenaAccountModel: ObservableObject {
    @Published private(set) var username: String?
    @Published private(set) var player: ArenaOnlinePlayer?
    @Published private(set) var leaders: [ArenaOnlinePlayer] = []
    @Published private(set) var round: ArenaOnlineFrame?
    @Published private(set) var busy = false
    @Published private(set) var message: String?

    var onRankedDeath: ((String) -> Void)?
    private var lastReportedDeath: String?

    private let client: ArenaAccountClient
    private let vault: ArenaSessionVault
    private var session: ArenaLogin?
    private var restored = false
    private var readingRound = false
    private var queuedPoint: CGPoint?
    private var nextRead = Date.distantPast
    private var nextClick = Date.distantPast
    private var needsSnapshot = false

    init(client: ArenaAccountClient = ArenaAccountClient(), vault: ArenaSessionVault = ArenaKeychain()) {
        self.client = client
        self.vault = vault
    }

    func appear() async {
        if !restored {
            restored = true
            do { setSession(try vault.read()) }
            catch { show(error) }
        }
        if session != nil { await refresh() }
    }

    func authenticate(name: String, email: String?, password: String) async {
        guard !busy, session == nil else { return }
        busy = true
        message = nil
        do {
            let login = try await client.authenticate(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                email: email?.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
            setSession(login)
            do { try vault.save(login) }
            catch { show(error) }
            try await readScores(for: login)
        } catch { show(error) }
        busy = false
    }

    func refresh() async {
        guard !busy, let login = session else { return }
        busy = true
        message = nil
        do { try await readScores(for: login) }
        catch { if session == login { show(error) } }
        busy = false
    }

    private func readScores(for login: ArenaLogin) async throws {
        async let user = client.me(login.token)
        async let table = client.leaderboard(login.token)
        let (me, players) = try await (user, table)
        guard session == login else { return }
        player = me
        leaders = players
    }

    func logout() async {
        guard !busy, let login = session else { return }
        busy = true
        message = nil
        do {
            try vault.clear()
        } catch {
            show(error)
            busy = false
            return
        }
        setSession(nil)
        do { try await client.logout(login.token) }
        catch ArenaAccountFailure.rejected("unauthorized") {}
        catch { message = "Lokal abgemeldet. Der Server konnte die Abmeldung nicht bestätigen." }
        busy = false
    }

    func startRound() async {
        guard !busy, let login = session, round?.playing != true else { return }
        busy = true
        message = nil
        do {
            let initial = try await client.start(login.token)
            if session == login { round = initial; queuedPoint = nil; nextRead = .distantPast }
        } catch { if session == login { show(error) } }
        busy = false
    }

    /// A click takes the next sequence from the last confirmed snapshot. After an ambiguous
    /// response, a fresh snapshot reconciles the sequence before the next input is accepted.
    func updateRound(tapping point: CGPoint? = nil) async {
        guard let login = session, let initial = round, initial.playing else { return }
        if let point, point.x.isFinite, point.y.isFinite,
           (0..<300).contains(point.x), (0..<160).contains(point.y) { queuedPoint = point }
        guard !readingRound, Date() >= nextRead else { return }
        readingRound = true
        var becameTerminal = false
        do {
            repeat {
                guard let previous = round, previous.id == initial.id, previous.playing, session == login else { break }
                let next: ArenaOnlineFrame
                if let tapped = queuedPoint, !needsSnapshot {
                    guard Date() >= nextClick else { break }
                    nextClick = Date().addingTimeInterval(0.20)
                    queuedPoint = nil
                    next = try await client.click(previous.id, token: login.token, point: tapped, seq: previous.seq + 1)
                } else {
                    next = try await client.frame(previous.id, token: login.token)
                }
                guard session == login, next.id == initial.id, round?.id == initial.id else { break }
                round = next
                needsSnapshot = false
                message = nil
                becameTerminal = !next.playing
                if next.phase == .dead, lastReportedDeath != next.id {
                    lastReportedDeath = next.id
                    onRankedDeath?(next.id)
                }
            } while queuedPoint != nil && !becameTerminal
        } catch {
            if session == login, round?.id == initial.id {
                queuedPoint = nil
                needsSnapshot = true
                if let failure = error as? ArenaAccountFailure, failure == .rejected("not_found") { round = nil }
                if let failure = error as? ArenaAccountFailure, failure == .rejected("sequence_gap") {
                    // The preceding click may already have reached the server.
                    nextRead = .distantPast
                } else {
                    nextRead = Date().addingTimeInterval(2)
                    show(error)
                }
            }
        }
        readingRound = false
        if becameTerminal { await refresh() }
    }

    private func setSession(_ next: ArenaLogin?) {
        session = next
        username = next?.username
        player = nil
        leaders = []
        round = nil
        queuedPoint = nil
        needsSnapshot = false
        nextClick = .distantPast
    }

    private func show(_ error: Error) {
        if Task.isCancelled || (error as? URLError)?.code == .cancelled { return }
        let failure = error as? ArenaAccountFailure ?? .unavailable
        if failure == .rejected("unauthorized") {
            setSession(nil)
            do { try vault.clear() } catch { message = ArenaAccountFailure.keychain.message; return }
        }
        message = failure.message
    }
}
