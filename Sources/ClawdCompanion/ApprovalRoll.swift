import Foundation

/// One roll is shared by the overlay and menu bar. Repeated hook snapshots leave
/// it alone, and a new request during a fold reverses from the current position.
struct ApprovalRoll {
    private(set) var pose: MascotPose?
    private(set) var started: TimeInterval?
    var waiting: Bool { pose == .approvalOpening || pose == .awaitingApproval }

    @discardableResult
    mutating func set(waiting newValue: Bool, at now: TimeInterval, reduced: Bool) -> Bool {
        guard newValue != waiting else { return false }
        let duration = MascotPose.approvalTransitionDuration
        let progress = started.map { min(1, max(0, (now - $0) / duration)) } ?? 1
        let reversing = started != nil
        if reduced || (reversing && progress == 0) {
            pose = newValue ? .awaitingApproval : nil
            started = nil
        } else {
            pose = newValue ? .approvalOpening : .approvalClosing
            started = reversing ? now - (1 - progress) * duration : now
        }
        return true
    }

    @discardableResult
    mutating func advance(to now: TimeInterval, reduced: Bool) -> Bool {
        guard let started, reduced || now - started >= MascotPose.approvalTransitionDuration else { return false }
        pose = waiting ? .awaitingApproval : nil
        self.started = nil
        return true
    }
}
