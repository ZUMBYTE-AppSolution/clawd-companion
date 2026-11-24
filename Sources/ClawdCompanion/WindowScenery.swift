import AppKit
import CoreGraphics

/// Contact lines of the drawn sprite in the real window's title area. All
/// points here are global AppKit coordinates, including vertically offset displays.
enum WindowLedge {
    static func offset(forRow row: CGFloat, pet: CGSize) -> CGFloat {
        let cell = min(pet.width / 56, pet.height / 48)
        return (pet.height - 48 * cell) / 2 + (48 - row) * cell
    }

    static func standY(window: CGRect, screen: CGRect, pet: CGSize) -> CGFloat? {
        let sole = offset(forRow: 43, pet: pet)
        let value = min(window.maxY - sole, screen.maxY - pet.height)
        guard window.maxY <= screen.maxY + 1, window.maxY - (value + sole) <= min(24, window.height / 3),
              value >= screen.minY else { return nil }
        return value
    }

    static func seatY(window: CGRect, screen: CGRect, pet: CGSize) -> CGFloat? {
        standY(window: window, screen: screen, pet: pet).map {
            $0 + offset(forRow: 43, pet: pet) - offset(forRow: 38, pet: pet)
        }
    }

    static func gripY(window: CGRect, screen: CGRect, pet: CGSize) -> CGFloat {
        // The highest hand spans rows 11–16. Keep the visible hand at the
        // upper rim even when a maximized window is flush with the menu bar.
        let grip = offset(forRow: 14, pet: pet)
        let y = min(window.maxY - grip, screen.maxY - pet.height)
        // At large mascot sizes the normal panel bound would stop its claw below
        // the title. The top six sprite rows contain no climbing ink.
        let clearTop = pet.height - offset(forRow: 6, pet: pet)
        return y + max(0, min(clearTop, window.maxY - (y + grip) - 24))
    }
}

/// Geometry in global AppKit points. A clear side can use the outside face, or
/// the inside of the same visible rim when the window is close to a display edge.
struct SceneryWindow: Equatable, Sendable {
    /// Each side surveys this much of the roof for an out-and-back route.
    static let surveyedRoofFraction: CGFloat = 0.55
    let id: CGWindowID
    let pid: pid_t
    let frame: CGRect
    let screen: CGRect
    let leftClear: Bool
    let rightClear: Bool
    let roofClear: Bool
    let leftRoofClear: Bool
    let rightRoofClear: Bool
    let leftInside: Bool
    let rightInside: Bool
    let isActive: Bool

    init(id: CGWindowID, pid: pid_t, frame: CGRect, screen: CGRect,
         leftClear: Bool, rightClear: Bool, roofClear: Bool = true,
         leftInside: Bool = false, rightInside: Bool = false,
         leftRoofClear: Bool? = nil, rightRoofClear: Bool? = nil, isActive: Bool = false) {
        self.id = id
        self.pid = pid
        self.frame = frame
        self.screen = screen
        self.leftClear = leftClear
        self.rightClear = rightClear
        self.roofClear = roofClear
        self.leftRoofClear = leftRoofClear ?? roofClear
        self.rightRoofClear = rightRoofClear ?? roofClear
        self.leftInside = leftInside
        self.rightInside = rightInside
        self.isActive = isActive
    }
}

enum WindowScenery {
    /// Call off the main thread. The window server returns this list front to back.
    /// Only geometry and window/owner identity are used. No image or window title is requested.
    static func snapshot(primaryTop: CGFloat, screens: [CGRect], petSize: CGSize,
                         activePID: pid_t? = nil, focusedFrame: CGRect? = nil,
                         displayFrames: [CGRect] = []) -> [SceneryWindow] {
        guard !screens.isEmpty,
              let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        return candidates(in: info, primaryTop: primaryTop, screens: screens, petSize: petSize,
                          ownPID: ProcessInfo.processInfo.processIdentifier, activePID: activePID,
                          focusedFrame: focusedFrame, displayFrames: displayFrames)
    }

    /// The pure half of discovery also accepts window-server fixtures for layout tests.
    static func candidates(in info: [[String: Any]], primaryTop: CGFloat, screens: [CGRect],
                           petSize: CGSize, ownPID: pid_t, activePID: pid_t? = nil,
                           focusedFrame: CGRect? = nil, displayFrames: [CGRect] = []) -> [SceneryWindow] {
        guard primaryTop.isFinite, petSize.width.isFinite, petSize.height.isFinite,
              petSize.width > 0, petSize.height > 0 else { return [] }
        let displays = screens.filter { !$0.isEmpty && !$0.isInfinite && !$0.isNull }
        var foreground: [(frame: CGRect, layer: Int)] = []
        var result: [SceneryWindow] = []
        var foundActive = false
        for entry in info {
            guard let layer = (entry[kCGWindowLayer as String] as? NSNumber)?.intValue, layer >= 0,
                  (entry[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0.025,
                  (entry[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue != false,
                  let owner = (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let coords = entry[kCGWindowBounds as String] as? NSDictionary,
                  let quartz = CGRect(dictionaryRepresentation: coords), !quartz.isEmpty, !quartz.isInfinite,
                  quartz.minX.isFinite, quartz.minY.isFinite,
                  owner != ownPID || layer == 0 else { continue }
            let frame = WindowPinTarget.quartzFlip(quartz, primaryTop: primaryTop)
            guard displays.contains(where: { $0.intersects(frame) }) else { continue }
            // Claw'd's transparent overlay panels must never veto their own route.
            // Its normal control window can still physically cover another window.
            let visibleCandidate = layer == 0 && owner > 0 && (owner != ownPID || (activePID == ownPID && focusedFrame != nil))
                && frame.width >= max(72, petSize.width * 0.9)
                && frame.height >= max(64, petSize.height * 0.9)
            if visibleCandidate, let id = (entry[kCGWindowNumber as String] as? NSNumber)?.uint32Value, id != 0,
               !systemSurfaces.contains(entry[kCGWindowOwnerName as String] as? String ?? "") {
                let isActive = !foundActive && owner == activePID && (focusedFrame.map {
                    max(abs($0.minX-frame.minX), abs($0.minY-frame.minY), abs($0.maxX-frame.maxX), abs($0.maxY-frame.maxY)) <= 3
                } ?? true)
                if isActive { foundActive = true }
                // A window spanning displays belongs to the usable screen with the
                // largest visible portion. Never invent a ledge at the display seam.
                let ordered = displays.sorted { intersectionArea($0, frame) > intersectionArea($1, frame) }
                for screen in ordered {
                    let index = screens.firstIndex(of: screen)
                    let fullDisplay = index.flatMap { displayFrames.indices.contains($0) ? displayFrames[$0] : nil } ?? screen
                    if let window = geometry(id: id, owner: owner, frame: frame, screen: screen, fullDisplay: fullDisplay,
                                             pet: petSize, foreground: foreground, isActive: isActive) {
                        result.append(window)
                        break
                    }
                }
            }
            foreground.append((frame, layer))
        }
        return result
    }

    // Dock/Stage Manager can also own plain layer-zero helper windows.
    // Finder's ordinary document windows remain eligible.
    private static let systemSurfaces: Set<String> = ["Dock", "WindowManager", "Window Server", "SystemUIServer"]
    private static let statusLevel = Int(CGWindowLevelForKey(.statusWindow))

    private static func intersectionArea(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let r = a.intersection(b)
        return r.isNull ? 0 : r.width * r.height
    }

    private static func geometry(id: CGWindowID, owner: pid_t, frame: CGRect, screen: CGRect,
                                 fullDisplay: CGRect, pet: CGSize, foreground: [(frame: CGRect, layer: Int)], isActive: Bool) -> SceneryWindow? {
        let visible = frame.intersection(screen)
        guard !visible.isNull, visible.height >= max(56, pet.height * 0.83),
              visible.width >= pet.width * 0.65 else { return nil }
        // An edge-to-edge surface filling the whole usable display has no distinct rim.
        guard !frame.insetBy(dx: -1, dy: -1).contains(fullDisplay), frame.maxY <= screen.maxY + 1 else { return nil }

        func unobstructed(_ path: CGRect) -> Bool {
            let corridor = path.intersection(screen)
            guard !corridor.isNull else { return false }
            return !foreground.contains { cover in
                // A status HUD can use a whole display as its transparent canvas.
                // Its bounds describe the canvas, whereas a compact status menu's
                // bounds are a meaningful obstacle. Apply this to each display.
                if cover.layer == statusLevel && cover.frame.contains(screen) { return false }
                let intersection = cover.frame.intersection(corridor)
                return !intersection.isNull && intersection.width > 1 && intersection.height > 1
            }
        }
        func clearance(left: Bool) -> (usable: Bool, inside: Bool) {
            let edge = left ? frame.minX : frame.maxX
            guard edge >= screen.minX - 1, edge <= screen.maxX + 1 else { return (false, false) }
            let outsideRoom = left ? edge - screen.minX : screen.maxX - edge
            let inside = outsideRoom < pet.width * 0.95 + 3
            guard !inside || visible.width >= pet.width * 1.3 else { return (false, false) }
            // The path includes the sprite's hands across the rim, its hanging body,
            // and clearance for the outward jump back toward the desktop floor.
            let extendsLeft = left != inside
            let large = pet.width * 1.72, overlap = pet.width * 0.16
            let lane = CGRect(x: edge - (extendsLeft ? large : overlap),
                              y: screen.minY,
                              width: large + overlap,
                              height: min(screen.maxY, frame.maxY + pet.height * 0.2) - screen.minY)
            return (unobstructed(lane), inside)
        }
        let left = clearance(left: true), right = clearance(left: false)
        guard left.usable || right.usable else { return nil }

        func roofClear(left: Bool) -> Bool {
            let depth = frame.width * SceneryWindow.surveyedRoofFraction
            let innerX = left ? frame.minX : frame.maxX - depth
            guard let stand = WindowLedge.standY(window: frame, screen: screen, pet: pet),
                  innerX >= screen.minX - 1, innerX + depth <= screen.maxX + 1 else { return false }
            // Include the hanging sprite until it passes the lip, and its head when peeking.
            let outside = pet.width * 0.92
            let band = CGRect(x: left ? innerX - outside : innerX, y: stand - pet.height * 0.04,
                              width: depth + outside, height: pet.height * 1.47)
            return unobstructed(band)
        }
        let leftRoof = roofClear(left: true), rightRoof = roofClear(left: false)
        return SceneryWindow(id: id, pid: owner, frame: frame, screen: screen,
                             leftClear: left.usable, rightClear: right.usable, roofClear: leftRoof && rightRoof,
                             leftInside: left.usable && left.inside, rightInside: right.usable && right.inside,
                             leftRoofClear: leftRoof, rightRoofClear: rightRoof, isActive: isActive)
    }
}
