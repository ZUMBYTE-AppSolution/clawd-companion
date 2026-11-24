import Foundation

enum DesktopUsageStatus: Equatable {
    case disabled, checking, needsPermission, notRunning, identityUnavailable, unavailable, ready
}

enum DesktopUsageSample: Sendable {
    case usage(LimitReport, fromCompactButton: Bool = false), needsPermission, notRunning, identityUnavailable, unavailable

    /// Both the accessibility query and parsing run on CompanionState's serial worker.
    static func read() -> Self {
        switch ClaudeDesktopUsageReader.read() {
        case .needsPermission: return .needsPermission
        case .notRunning: return .notRunning
        case .identityUnavailable: return .identityUnavailable
        case .unavailable: return .unavailable
        case .usageButton(let label):
            guard let report = ClaudeDesktopUsageParser.parseUsageButton(label, observedAt: Date()) else { return .unavailable }
            return .usage(report, fromCompactButton: true)
        case .usage(let lines):
            guard let report = ClaudeDesktopUsageParser.parse(lines, observedAt: Date()) else { return .unavailable }
            return .usage(report)
        }
    }
}

extension LimitReport {
    /// A visible page can expose only one card. Keep the other card's original observation time,
    /// so reading a weekly limit cannot renew an old or expired session value.
    func desktopObservation(preserving cached: LimitReport?, now: Date, fromCompactButton: Bool = false) -> LimitReport? {
        let latestPlausible = now.addingTimeInterval(60)
        guard seen.timeIntervalSinceReferenceDate.isFinite, seen <= latestPlausible else { return nil }
        // A wall-clock correction can make an older cache appear to come from the future.
        let previous = cached.flatMap { $0.seen <= latestPlausible ? $0 : nil }
        let session = current(weekly: false, at: now)
        let week = current(weekly: true, at: now)
        guard session != nil || week != nil else { return nil }
        func choose(_ fresh: LimitWindow?, _ cached: LimitWindow?) -> LimitWindow? {
            var saved = cached
            if saved?.observedAt == nil { saved?.observedAt = previous?.seen }
            guard var latest = fresh else { return saved }
            let observed = latest.observedAt ?? seen
            if let oldTime = saved?.observedAt, oldTime > observed { return saved }
            if fromCompactButton, latest.reset == nil, latest.resetLabel == nil,
               let saved, let knownReset = saved.reset, knownReset > observed, latest.remaining <= saved.remaining {
                latest.reset = knownReset
                latest.resetLabel = saved.resetLabel
                latest.resetApproximate = saved.resetApproximate
            }
            latest.observedAt = observed
            return latest
        }
        return LimitReport(seen: max(previous?.seen ?? seen, seen),
                           session: choose(session, previous?.session), week: choose(week, previous?.week))
    }
}
