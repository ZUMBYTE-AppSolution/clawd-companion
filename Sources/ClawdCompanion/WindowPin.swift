import AppKit
import ApplicationServices

/// Retains a point on the chosen window. Edge attachments follow that edge on resize;
/// interior attachments retain their point offset from the window's top-left corner.
struct WindowPinOffset {
    private let right: Bool
    private let bottom: Bool
    private let dx: CGFloat
    private let dy: CGFloat

    init(pet: CGRect, window: CGRect) {
        right = abs(pet.midX - window.maxX) <= pet.width * 0.6
        bottom = abs(pet.midY - window.minY) <= pet.height * 0.6
        dx = pet.midX - (right ? window.maxX : window.minX)
        dy = pet.midY - (bottom ? window.minY : window.maxY)
    }

    func origin(in window: CGRect, petSize: CGSize) -> CGPoint {
        CGPoint(x: (right ? window.maxX : window.minX) + dx - petSize.width / 2,
                y: (bottom ? window.minY : window.maxY) + dy - petSize.height / 2)
    }
}

/// Geometry and identity only: no window titles, contents, or screenshots.
// All lookups and ID recovery run on the overlay's serial window-geometry queue.
final class WindowPinTarget: @unchecked Sendable {
    enum Reading {
        case visible(CGRect), hidden, closed, unavailable
    }

    private var id: CGWindowID
    private let pid: pid_t
    private let axWindow: AXUIElement?

    private init(id: CGWindowID, pid: pid_t, axWindow: AXUIElement?) {
        self.id = id
        self.pid = pid
        self.axWindow = axWindow
    }

    private struct Entry {
        let id: CGWindowID
        let pid: pid_t
        let bounds: CGRect

        init?(_ info: [String: Any]) {
            guard let number = info[kCGWindowNumber as String] as? NSNumber,
                  let owner = info[kCGWindowOwnerPID as String] as? NSNumber,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict),
                  bounds.width > 30, bounds.height > 22 else { return nil }
            self.id = number.uint32Value
            self.pid = owner.int32Value
            self.bounds = bounds
        }
    }

    static func capture(at point: CGPoint, pet: CGRect, primaryTop: CGFloat) -> (WindowPinTarget, CGRect)? {
        let cursor = CGPoint(x: point.x, y: primaryTop - point.y)
        let petBounds = quartzFlip(pet, primaryTop: primaryTop)
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return nil }
        let entries = info.compactMap { item -> Entry? in
            guard (item[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  (item[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0 else { return nil }
            return Entry(item)
        }
        // Prefer the top window under the original right-click. A sprite already hanging
        // just outside a window may touch it only with its transparent panel margin.
        let selected = entries.first { $0.bounds.contains(cursor) }
            ?? entries.first { $0.bounds.insetBy(dx: -3, dy: -3).intersects(petBounds) }
        guard let selected else { return nil }
        let element = matchingAXWindow(for: selected, cursor: cursor)
        let target = WindowPinTarget(id: selected.id, pid: selected.pid, axWindow: element)
        return (target, quartzFlip(selected.bounds, primaryTop: primaryTop))
    }

    static func quartzFlip(_ rect: CGRect, primaryTop: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryTop - rect.maxY, width: rect.width, height: rect.height)
    }

    private static func matchingAXWindow(for entry: Entry, cursor: CGPoint) -> AXUIElement? {
        guard AXIsProcessTrusted(), entry.pid != ProcessInfo.processInfo.processIdentifier else { return nil }
        let app = AXUIElementCreateApplication(entry.pid)
        AXUIElementSetMessagingTimeout(app, 0.15)
        let point = CGPoint(x: min(max(cursor.x, entry.bounds.minX + 2), entry.bounds.maxX - 2),
                            y: min(max(cursor.y, entry.bounds.minY + 2), entry.bounds.maxY - 2))
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(app, Float(point.x), Float(point.y), &hit) == .success,
              let hit else { return nil }
        var ref: CFTypeRef?
        let window: AXUIElement
        if AXUIElementCopyAttributeValue(hit, kAXWindowAttribute as CFString, &ref) == .success,
           let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() {
            window = ref as! AXUIElement
        } else { window = hit }
        var role: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXRoleAttribute as CFString, &role) == .success,
              role as? String == kAXWindowRole else { return nil }
        AXUIElementSetMessagingTimeout(window, 0.15)
        return window
    }

    func read(primaryTop: CGFloat) -> Reading {
        guard let list = CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]] else {
            return .unavailable
        }
        if let info = list.first, (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid {
            if (info[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue == true {
                guard let entry = Entry(info) else { return .unavailable }
                return .visible(Self.quartzFlip(entry.bounds, primaryTop: primaryTop))
            }
            return restored(primaryTop: primaryTop, otherwise: .hidden)
        }
        return restored(primaryTop: primaryTop, otherwise: .closed)
    }

    /// Some apps withdraw (and later replace) the WindowServer ID when a live AX window
    /// is minimized. Rebind only to a unique, visible match for that retained AX window.
    private func restored(primaryTop: CGFloat, otherwise fallback: Reading) -> Reading {
        guard let axWindow else { return fallback }
        guard let application = NSRunningApplication(processIdentifier: pid), !application.isTerminated else { return .closed }
        if application.isHidden { return .hidden }
        var minimized: CFTypeRef?
        switch AXUIElementCopyAttributeValue(axWindow, kAXMinimizedAttribute as CFString, &minimized) {
        case .success:
            if (minimized as? NSNumber)?.boolValue == true { return .hidden }
        case .attributeUnsupported, .noValue: break
        case .apiDisabled, .invalidUIElement: return .closed
        default: return .unavailable
        }
        guard let rect = Self.bounds(of: axWindow),
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return .unavailable }
        let matches = list.compactMap { info -> Entry? in
            guard (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let item = Entry(info), item.pid == pid, abs(rect.minX - item.bounds.minX) <= 2,
                  abs(rect.minY - item.bounds.minY) <= 2, abs(rect.width - item.bounds.width) <= 2,
                  abs(rect.height - item.bounds.height) <= 2 else { return nil }
            return item
        }
        guard matches.count == 1, let match = matches.first else { return .hidden }
        // Geometry alone could also match an identically-sized window on another Space.
        let probes = [CGPoint(x: rect.midX, y: rect.minY + 12), CGPoint(x: rect.midX, y: rect.midY)]
        guard probes.contains(where: { point in
            guard let hit = Self.matchingAXWindow(for: match, cursor: point) else { return false }
            return CFEqual(hit, axWindow)
        }) else { return .hidden }
        id = match.id
        return .visible(Self.quartzFlip(match.bounds, primaryTop: primaryTop))
    }

    static func bounds(of window: AXUIElement) -> CGRect? {
        func attribute(_ key: String) -> AXValue? {
            var object: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, key as CFString, &object) == .success,
                  let object, CFGetTypeID(object) == AXValueGetTypeID() else { return nil }
            return (object as! AXValue)
        }
        guard let origin = attribute(kAXPositionAttribute), let size = attribute(kAXSizeAttribute) else { return nil }
        var point = CGPoint.zero, extent = CGSize.zero
        guard AXValueGetValue(origin, .cgPoint, &point), AXValueGetValue(size, .cgSize, &extent),
              point.x.isFinite, point.y.isFinite, extent.width.isFinite, extent.height.isFinite,
              extent.width > 1, extent.height > 1 else { return nil }
        return CGRect(origin: point, size: extent)
    }
}
