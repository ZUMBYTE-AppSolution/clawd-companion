import AppKit
import ApplicationServices
import Security

/// Observes a visible usage pane in the signed Claude Desktop process. No input events,
/// navigation, file reads, or screen captures are involved.
enum ClaudeDesktopUsageReader {
    static let bundleIdentifier = "com.anthropic.claudefordesktop"

    enum Result: Equatable {
        case usage([String])
        case usageButton(String)
        case needsPermission
        case notRunning
        case identityUnavailable
        case unavailable
    }

    static var hasAccess: Bool { AXIsProcessTrusted() }

    static func requestAccess() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    // Anthropic's published Developer ID requirement for the desktop app. Check the
    // live guest, since an arbitrary bundle can declare the same CFBundleIdentifier.
    private static let requirement: SecRequirement? = {
        let expression = """
        identifier "\(bundleIdentifier)" and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = "Q6L2SF6YDW"
        """
        var result: SecRequirement?
        guard SecRequirementCreateWithString(expression as CFString, [], &result) == errSecSuccess else { return nil }
        return result
    }()

    private static func trusted(_ app: NSRunningApplication) -> Bool {
        guard app.bundleIdentifier == bundleIdentifier, let requirement, !app.isTerminated else { return false }
        let attributes = [kSecGuestAttributePid as String: NSNumber(value: app.processIdentifier)] as CFDictionary
        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess, let code else { return false }
        return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
    }

    static func read() -> Result {
        guard hasAccess else { return .needsPermission }
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        guard !apps.isEmpty else { return .notRunning }
        let verified = apps.prefix(4).filter(trusted)
        guard !verified.isEmpty else { return .identityUnavailable }
        let scan = Scan()
        for app in verified where !app.isHidden && scan.hasTime {
            let pid = app.processIdentifier
            let visible = visibleWindows(of: pid)
            guard !visible.isEmpty else { continue }
            let application = AXUIElementCreateApplication(pid)
            scan.prepare(application)
            // Electron documents this opt-in to expose its accessibility tree. It does
            // not focus the app or change the contents/selection of any UI control.
            if scan.attribute(application, "AXManualAccessibility") as? Bool != true {
                AXUIElementSetAttributeValue(application, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            }
            let main = scan.attribute(application, kAXMainWindowAttribute).flatMap {
                CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil
            }
            var windows = main.map { [$0] } ?? []
            for item in scan.children(application, attribute: kAXWindowsAttribute, count: 12)
                where !windows.contains(item) { windows.append(item) }
            for window in windows where scan.hasTime {
                guard let meta = scan.metadata(window), let bounds = meta.bounds,
                      meta.role == kAXWindowRole, !meta.hidden,
                      scan.attribute(window, kAXMinimizedAttribute) as? Bool != true,
                      visible.contains(where: { matchingWindows($0, bounds) }) else { continue }
                let result = scan.read(window)
                if result != .unavailable { return result }
            }
        }
        return .unavailable
    }

    /// Scans a single AX window. The application entry point validates the running
    /// process and its on-screen window before invoking the same scanner.
    static func readVisibleUsage(in window: AXUIElement, tree: Tree = .system) -> Result {
        Scan(tree: tree).read(window)
    }

    struct Tree {
        let prepare: (AXUIElement) -> Void
        let values: (AXUIElement, [String]) -> [Any]
        let children: (AXUIElement, String, Int) -> [AXUIElement]?

        static let system = Tree(prepare: { AXUIElementSetMessagingTimeout($0, 0.10) }, values: { item, names in
            var result: CFArray?
            guard AXUIElementCopyMultipleAttributeValues(item, names as CFArray, [], &result) == .success,
                  let entries = result as? [Any], entries.count == names.count else { return [] }
            return entries
        }, children: { item, name, limit in
            var result: CFArray?
            guard AXUIElementCopyAttributeValues(item, name as CFString, 0, limit, &result) == .success else { return nil }
            return result as? [AXUIElement]
        })
    }

    private static func visibleWindows(of pid: pid_t) -> [CGRect] {
        guard let entries = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                        kCGNullWindowID) as? [[String: Any]] else { return [] }
        return entries.compactMap { info in
            guard (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                  (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0,
                  let raw = info[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: raw as CFDictionary), !rect.isEmpty else { return nil }
            return rect
        }
    }

    private static func matchingWindows(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX-b.minX) <= 3 && abs(a.minY-b.minY) <= 3 &&
        abs(a.width-b.width) <= 3 && abs(a.height-b.height) <= 3
    }

    enum Address: Equatable { case unknown, wrapper, firstParty, settings, usage, usageOverlay, other }

    static func address(_ raw: String?) -> Address {
        guard let raw, !raw.isEmpty else { return .unknown }
        guard raw.utf8.count <= 2048, !raw.contains("\\"), let url = URLComponents(string: raw) else { return .other }
        // The signed Electron window hosts the actual HTTPS document in a nested web area.
        // The local index is a traversal boundary, never evidence for quota text.
        if url.scheme == "file", (url.host ?? "").isEmpty, url.percentEncodedPath.hasSuffix("/index.html") { return .wrapper }
        guard url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "claude.ai", url.port == nil || url.port == 443,
              url.user == nil, url.password == nil else { return .other }
        let path = url.percentEncodedPath
        let locale = "(?:[A-Za-z]{2,3}(?:-[A-Za-z]{2,8}){0,2}/)?"
        if path.range(of: "^/" + locale + "settings/usage/?$", options: .regularExpression) != nil { return .usage }
        if path.range(of: "^/" + locale + "settings/?$", options: .regularExpression) != nil { return .settings }
        if url.percentEncodedFragment == "settings/usage",
           path.range(of: "^/epitaxy/local_[a-zA-Z0-9_-]{1,160}/?$", options: .regularExpression) != nil {
            return .usageOverlay
        }
        return .firstParty
    }

    private static let settingsNames = Set(["settings", "einstellungen", "paramètres", "ajustes", "configuración",
        "configurações", "pengaturan", "设置", "設定", "सेटिंग", "सेटिंग्स", "সেটিংস", "الإعدادات", "ترتیبات"].map(fold))
    private static let usageNames = Set(["usage", "nutzung", "verwendung", "auslastung", "utilisation", "uso",
        "penggunaan", "使用情况", "使用量", "用量", "उपयोग", "ব্যবহার", "الاستخدام", "استعمال"].map(fold))

    private static let limitGroupNames = Set(["usage limits", "plan usage limits", "nutzungslimits", "nutzungslimits des plans"].map(fold))
    private static let cardNames = Set(["current session", "session limit", "5-hour limit", "5 hour limit",
        "aktuelle sitzung", "sitzungslimit", "5-stunden-limit", "this week", "weekly limits", "weekly · all models",
        "weekly · all-models", "weekly usage", "diese woche", "wochenlimit", "wöchentlich · alle modelle"].map(fold))

    private static func fold(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive],
                                                                    locale: Locale(identifier: "en_US_POSIX"))
    }

    static func progress(_ description: String?, value: Double?, min: Double?, max: Double?) -> String? {
        if let description = description?.trimmingCharacters(in: .whitespacesAndNewlines),
           description.count <= 120,
           description.range(of: #"[0-9]\s*[%٪％]"#, options: .regularExpression) != nil { return description }
        guard min == 0, let max, max == 1 || max == 100, let value, value.isFinite, (0...max).contains(value) else { return nil }
        let percent = value * (100/max)
        let digits = (percent * 10).rounded() / 10
        return digits.rounded() == digits ? "\(Int(digits))%" : "\(digits)%"
    }

    private struct Meta {
        let role: String
        let subrole: String
        let hidden: Bool
        let bounds: CGRect?
        var navigation: Bool {
            role == kAXTabGroupRole || ["AXLandmarkNavigation", "AXNavigation", "AXOutline"].contains(role) ||
            ["AXLandmarkNavigation", "AXSourceList", "AXSidebar"].contains(subrole)
        }
        var dialog: Bool {
            role == kAXSheetRole || role == "AXDialog" ||
            ["AXDialog", "AXSystemDialog", "AXApplicationDialog", "AXApplicationAlertDialog"].contains(subrole)
        }
        var document: Bool { role == "AXWebArea" || role == "AXDocument" }
        var indicator: Bool { role == kAXProgressIndicatorRole || role == "AXLevelIndicator" }
        var main: Bool { role == "AXLandmarkMain" || subrole == "AXLandmarkMain" }
        var messageList: Bool {
            ["AXList", "AXTable", "AXArticle", "AXDocumentArticle", "AXApplicationLog", "AXLog"].contains(role) ||
                ["AXDocumentArticle", "AXApplicationLog", "AXLog"].contains(subrole)
        }
        var input: Bool {
            ["AXTextArea", "AXTextField", "AXComboBox", "AXSearchField", "AXMenu", "AXMenuBar",
             "AXSecureTextField", "AXImage"].contains(role) || subrole == "AXSecureTextField"
        }
        var text: Bool { role == kAXStaticTextRole || role == "AXHeading" || role == "AXParagraph" }
    }

    private final class Scan {
        private let tree: Tree
        init(tree: Tree = .system) { self.tree = tree }

        private let deadline = ProcessInfo.processInfo.systemUptime + 2.5
        private var cache: [AXUIElement: Meta] = [:]
        private var descendantCache: [AXUIElement: [AXUIElement]] = [:]
        private var addresses: [AXUIElement: Address] = [:]
        private var parents: [AXUIElement: AXUIElement] = [:]
        private var exceeded = false
        var hasTime: Bool { !exceeded && ProcessInfo.processInfo.systemUptime < deadline }

        func prepare(_ element: AXUIElement) {
            tree.prepare(element)
        }
        func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
            guard hasTime else { return nil }
            return tree.values(element, [name]).first.map { $0 as CFTypeRef }
        }
        private func attributes(_ element: AXUIElement, _ names: [String]) -> [Any] {
            hasTime ? tree.values(element, names) : []
        }
        func children(_ element: AXUIElement, attribute name: String, count: Int) -> [AXUIElement] {
            hasTime ? (tree.children(element, name, count) ?? []) : []
        }

        func metadata(_ element: AXUIElement) -> Meta? {
            if let value = cache[element] { return value }
            guard cache.count < 640 else { exceeded = true; return nil }
            prepare(element)
            let a = attributes(element, [kAXRoleAttribute, kAXSubroleAttribute, kAXHiddenAttribute,
                                         kAXPositionAttribute, kAXSizeAttribute])
            guard a.count == 5, let role = a[0] as? String else { return nil }
            var p = CGPoint.zero, s = CGSize.zero
            let pos = a[3] as CFTypeRef, size = a[4] as CFTypeRef
            var rect: CGRect?
            if CFGetTypeID(pos) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID(),
               AXValueGetType(pos as! AXValue) == .cgPoint, AXValueGetType(size as! AXValue) == .cgSize,
               AXValueGetValue(pos as! AXValue, .cgPoint, &p), AXValueGetValue(size as! AXValue, .cgSize, &s) {
                rect = CGRect(origin: p, size: s)
            }
            let value = Meta(role: role, subrole: a[1] as? String ?? "", hidden: a[2] as? Bool == true, bounds: rect)
            cache[element] = value
            return value
        }

        private func descendants(_ element: AXUIElement) -> [AXUIElement] {
            if let value = descendantCache[element] { return value }
            let items = tree.children(element, kAXVisibleChildrenAttribute, 97) ??
                children(element, attribute: kAXChildrenAttribute, count: 97)
            if items.count > 96 { exceeded = true; return [] }
            for child in items where parents[child] == nil { parents[child] = element }
            descendantCache[element] = items
            return items
        }

        private enum Action { case descend, skip, stop }
        private func walk(_ root: AXUIElement, clip: CGRect?,
                          visit: (AXUIElement, Meta, Bool) -> Action) {
            var stack = [(root, 0, false, clip)]
            var seen = Set<AXUIElement>()
            while hasTime, let (item, depth, inNav, viewport) = stack.popLast() {
                guard seen.insert(item).inserted, let meta = metadata(item), !meta.hidden, !meta.input else { continue }
                if (meta.text || meta.indicator), meta.bounds?.isEmpty == true { continue }
                if let viewport, let rect = meta.bounds, !rect.isEmpty, !viewport.intersects(rect) { continue }
                switch visit(item, meta, inNav) {
                case .stop: return
                case .skip: continue
                case .descend: break
                }
                guard depth < 20, meta.role != kAXStaticTextRole, !meta.indicator else { continue }
                var nextClip = viewport
                if meta.role == kAXScrollAreaRole, let bounds = meta.bounds, !bounds.isEmpty {
                    nextClip = viewport?.intersection(bounds) ?? bounds
                }
                for child in descendants(item).reversed() { stack.append((child, depth+1, inNav || meta.navigation, nextClip)) }
            }
        }

        private func route(_ item: AXUIElement) -> Address {
            if let value = addresses[item] { return value }
            var found: Address = .unknown
            for raw in attributes(item, [kAXDocumentAttribute, kAXURLAttribute]) {
                let string = (raw as? URL)?.absoluteString ?? raw as? String
                guard let string else { continue }
                let current = ClaudeDesktopUsageReader.address(string)
                if current == .other { found = .other; break }
                if current != .unknown && (found == .unknown || found == .wrapper || current == .usage || current == .usageOverlay) {
                    found = current
                }
            }
            addresses[item] = found
            return found
        }

        private func names(_ item: AXUIElement) -> [String] {
            attributes(item, [kAXTitleAttribute, kAXDescriptionAttribute]).compactMap { raw in
                guard let value = raw as? String, value.utf8.count <= 120 else { return nil }
                return ClaudeDesktopUsageReader.fold(value)
            }
        }

        private func selectedUsage(in root: AXUIElement, clip: CGRect?) -> Bool {
            var matched = false
            walk(root, clip: clip) { item, meta, nav in
                if item != root && meta.document && ![Address.settings, .usage, .unknown].contains(self.route(item)) { return .skip }
                if nav && ["AXRadioButton", "AXTab", "AXButton", "AXLink", "AXRow"].contains(meta.role) {
                    let selection = self.attributes(item, [kAXSelectedAttribute, "AXARIACurrent", "AXCurrent",
                                                           kAXValueAttribute])
                    guard selection.count == 4 else { return .skip }
                    let checked = selection[0] as? Bool == true ||
                        selection[1...2].contains { ["true", "page", "location"].contains(($0 as? String)?.lowercased() ?? "") } ||
                        (meta.role == kAXRadioButtonRole && selection[3] as? Bool == true)
                    if checked && self.names(item).contains(where: ClaudeDesktopUsageReader.usageNames.contains) {
                        matched = true; return .stop
                    }
                }
                return .descend
            }
            return matched
        }

        private func ancestors(of item: AXUIElement, upTo root: AXUIElement) -> [AXUIElement] {
            var nodes: [AXUIElement] = [], cursor = parents[item]
            while let parent = cursor, nodes.count < 20, !nodes.contains(parent) {
                nodes.append(parent)
                if parent == root { break }
                cursor = parents[parent]
            }
            return nodes
        }

        private func indicatorText(_ item: AXUIElement) -> String? {
            let values = attributes(item, [kAXValueDescriptionAttribute, kAXValueAttribute, kAXMinValueAttribute, kAXMaxValueAttribute])
            guard values.count == 4 else { return nil }
            return ClaudeDesktopUsageReader.progress(values[0] as? String, value: (values[1] as? NSNumber)?.doubleValue,
                min: (values[2] as? NSNumber)?.doubleValue, max: (values[3] as? NSNumber)?.doubleValue)
        }

        private func label(_ item: AXUIElement) -> String? {
            attributes(item, [kAXTitleAttribute, kAXDescriptionAttribute]).compactMap { $0 as? String }
                .first { !$0.isEmpty && $0.utf8.count <= 240 }
        }

        private func quotaCards(in scope: AXUIElement, clip: CGRect?) -> [String] {
            var leaves: [(AXUIElement, Meta)] = [], result: [String] = []
            walk(scope, clip: clip) { item, meta, _ in
                if item != scope && (meta.document || meta.navigation || meta.input || meta.messageList) { return .skip }
                if meta.indicator || meta.role == kAXStaticTextRole { leaves.append((item, meta)); return .skip }
                return .descend
            }
            for (index, leaf) in leaves.enumerated() where leaf.1.indicator && hasTime {
                guard let title = label(leaf.0), ClaudeDesktopUsageReader.cardNames.contains(ClaudeDesktopUsageReader.fold(title)),
                      let value = indicatorText(leaf.0) else { continue }
                result.append(title)
                // In Claude's cards the reset is immediately before the named meter. Keep
                // only an explicit reset label; a product breakdown below is never a limit.
                if index > 0 && leaves[index-1].1.role == kAXStaticTextRole {
                    let prior = leaves[index-1].0
                    if let raw = attribute(prior, kAXValueAttribute) as? String ?? label(prior), raw.utf8.count <= 180 {
                        let key = ClaudeDesktopUsageReader.fold(raw)
                        if ["reset", "wird ", "zurücksetz", "zurucksetz", "réinitial", "reinitial"].contains(where: key.hasPrefix) {
                            result.append(raw)
                        }
                    }
                }
                result.append(value)
            }
            return result
        }

        private func containsUsageLink(_ root: AXUIElement, clip: CGRect?) -> Bool {
            var linked = false
            walk(root, clip: clip) { item, meta, _ in
                if item != root && (meta.document || meta.messageList) { return .skip }
                if meta.role == "AXLink" {
                    if self.route(item) == .usage { linked = true; return .stop }
                    return .skip
                }
                return .descend
            }
            return linked
        }

        private func composerOwns(_ button: AXUIElement, in document: AXUIElement) -> Bool {
            let path = ancestors(of: button, upTo: document)
            guard path.contains(document) else { return false }
            // Identify the input controls by their roles. Never ask the editor for its
            // value, description, selected text, or children.
            var compactControls = false
            for group in path.prefix(5) {
                guard group != document, let anchor = metadata(group), !anchor.main, !anchor.messageList else { break }
                var queue = [(group,0)], count = 0, popups = 0, editor = false
                while let (item, depth) = queue.popLast(), count < 80, hasTime {
                    count += 1
                    guard let m = metadata(item), !m.hidden, !m.document, !m.messageList else { continue }
                    if m.role == kAXTextAreaRole || m.role == kAXTextFieldRole { editor = true; continue }
                    if m.role == kAXPopUpButtonRole || m.role == kAXMenuButtonRole {
                        popups += 1; continue
                    }
                    if depth < 5 && !m.text && !m.input && !m.indicator {
                        for child in descendants(item) { queue.append((child,depth+1)) }
                    }
                }
                if editor && popups >= 2 { compactControls = true; break }
            }
            guard compactControls else { return false }
            var inMain = false
            for group in path where group != document {
                guard let m = metadata(group), !m.messageList else { return false }
                if m.main { inMain = true; break }
                guard m.role == kAXGroupRole else { continue }
                let groupNames = names(group)
                if groupNames.contains("chat-nachrichten") || groupNames.contains("chat messages") { return false }
                if groupNames.contains("hauptbereich") || groupNames.contains("main") { inMain = true; break }
            }
            return inMain
        }

        private func webControls(in document: AXUIElement, at location: Address, clip: CGRect?) -> Result {
            var indicators: [AXUIElement] = [], popups: [AXUIElement] = []
            walk(document, clip: clip) { item, meta, _ in
                if item != document && (meta.document || meta.navigation || meta.messageList) { return .skip }
                if meta.indicator { indicators.append(item); return .skip }
                if meta.role == kAXPopUpButtonRole { popups.append(item); return .skip }
                return meta.text ? .skip : .descend
            }
            var checked = Set<AXUIElement>()
            for meter in indicators {
                let path = ancestors(of: meter, upTo: document)
                for group in path.prefix(6) where group != document {
                    guard checked.insert(group).inserted, let m = metadata(group), m.role == kAXGroupRole || m.dialog else { continue }
                    let titles = names(group)
                    let settings = location == .usageOverlay && titles.contains(where: ClaudeDesktopUsageReader.settingsNames.contains)
                    let limits = titles.contains(where: ClaudeDesktopUsageReader.limitGroupNames.contains)
                    guard settings || limits else { continue }
                    if !settings {
                        // An open popover has a separately labelled limits group and a
                        // sibling link to the genuine account usage page in its panel.
                        guard let panel = parents[group], panel != document, containsUsageLink(panel, clip: clip) else { continue }
                    }
                    let lines = quotaCards(in: group, clip: clip)
                    if !lines.isEmpty && hasTime { return .usage(lines) }
                }
            }
            for button in popups where hasTime && composerOwns(button, in: document) {
                guard let title = label(button), title.hasPrefix("Nutzung:") || title.hasPrefix("Usage:") else { continue }
                return .usageButton(title)
            }
            return .unavailable
        }

        func read(_ window: AXUIElement) -> Result {
            guard let windowMeta = metadata(window), windowMeta.role == kAXWindowRole, !windowMeta.hidden else { return .unavailable }
            let clip = windowMeta.bounds
            var verified: AXUIElement?
            var web: [(AXUIElement, Address)] = []
            var candidates: [(AXUIElement, Address)] = []
            walk(window, clip: clip) { item, meta, _ in
                if item == window || meta.document || meta.dialog {
                    let location = self.route(item)
                    if location == .other { return .skip }
                    if location == .usage { verified = item; return .stop }
                    if meta.document && (location == .firstParty || location == .usageOverlay) {
                        web.append((item, location))
                        return .skip
                    }
                    if location == .settings || meta.dialog || (item == window && location == .unknown) {
                        candidates.append((item, location))
                    }
                }
                return .descend
            }
            if verified == nil {
                var compact: Result?
                for (item, location) in web where hasTime {
                    let found = webControls(in: item, at: location, clip: clip)
                    if case .usage = found { return found }
                    if case .usageButton = found { compact = found }
                }
                if let compact { return compact }
            }
            if verified == nil {
                // A chat title, headings, or a message containing quota-looking text cannot
                // attest a settings page. Require a selected Usage tab in a real navigator.
                for (candidate, location) in candidates.reversed() where hasTime {
                    if selectedUsage(in: candidate, clip: clip) &&
                        (location == .settings || names(candidate).contains(where: ClaudeDesktopUsageReader.settingsNames.contains)) {
                        verified = candidate
                        break
                    }
                }
            }
            guard let scope = verified, hasTime else { return .unavailable }
            var lines: [String] = []
            walk(scope, clip: clip) { item, meta, _ in
                if item != scope && (meta.dialog || meta.role == kAXWindowRole) { return .skip }
                if meta.document && ![Address.settings, .usage, .unknown].contains(self.route(item)) { return .skip }
                if item != scope && meta.document && self.metadata(scope)?.document == true && self.route(item) != .usage { return .skip }
                if meta.navigation || ["AXLink", "AXButton", "AXListBox", "AXScrollBar", "AXToolbar"].contains(meta.role) { return .skip }
                if meta.indicator {
                    if let text = self.indicatorText(item) { self.append(text, to: &lines) }
                    return .skip
                }
                if meta.text {
                    let parts = self.attributes(item, [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute])
                    if let text = parts.compactMap({ $0 as? String }).first(where: { !$0.isEmpty }) {
                        self.append(text, to: &lines)
                        return .skip
                    }
                }
                return .descend
            }
            return hasTime && !lines.isEmpty ? .usage(lines) : .unavailable
        }

        private func append(_ text: String, to lines: inout [String]) {
            guard text.utf8.count <= 1024 else { return }
            for line in text.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty && trimmed.utf8.count <= 256 && lines.last != trimmed { lines.append(trimmed) }
                if lines.count > 128 { exceeded = true; return }
            }
        }
    }
}
