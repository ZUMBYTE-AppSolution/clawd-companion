import ApplicationServices
import XCTest
@testable import ClawdCompanion

final class ClaudeDesktopUsageReaderTests: XCTestCase {
    private typealias Reader = ClaudeDesktopUsageReader

    /// Stand-ins for AX handles; the fixture handles are never sent to another process.
    private final class Tree {
        var next = 17000
        var fields: [AXUIElement: [String: Any]] = [:]
        var kids: [AXUIElement: [AXUIElement]] = [:]
        var queried: [AXUIElement: Set<String>] = [:]

        func node(_ role: String, _ data: [String: Any] = [:], _ children: [AXUIElement] = []) -> AXUIElement {
            next += 1
            let item = AXUIElementCreateApplication(pid_t(next))
            fields[item] = data.merging([kAXRoleAttribute: role]) { _, value in value }
            kids[item] = children
            return item
        }
        func text(_ s: String) -> AXUIElement { node("AXStaticText", [kAXValueAttribute: s]) }
        func bar(_ title: String, _ value: String) -> AXUIElement {
            node("AXLevelIndicator", [kAXTitleAttribute: title, kAXValueDescriptionAttribute: value])
        }
        func window(_ web: AXUIElement) -> AXUIElement {
            let wrapper = node("AXWebArea", [kAXURLAttribute: "file:///Applications/Claude.app/index.html"], [web])
            return node("AXWindow", [:], [wrapper])
        }
        func read(_ window: AXUIElement) -> Reader.Result {
            let tree = Reader.Tree(prepare: { _ in }, values: { item, keys in
                self.queried[item, default: []].formUnion(keys)
                return keys.map { self.fields[item]?[$0] ?? NSNull() }
            }, children: { item, key, count in
                key == kAXChildrenAttribute ? Array((self.kids[item] ?? []).prefix(count)) : nil
            })
            return Reader.readVisibleUsage(in: window, tree: tree)
        }
        func assertNotRead(_ item: AXUIElement, file: StaticString = #filePath, line: UInt = #line) {
            let textKeys: Set<String> = [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXValueDescriptionAttribute]
            XCTAssertTrue((queried[item] ?? []).isDisjoint(with: textKeys), file: file, line: line)
        }
    }

    func testOnlyGenuineOriginAndKnownUsageRoutesQualify() {
        XCTAssertEqual(Reader.address("https://claude.ai/de-DE/settings/usage/"), .usage)
        XCTAssertEqual(Reader.address("https://claude.ai:443/settings/usage?view=all"), .usage)
        XCTAssertEqual(Reader.address("https://claude.ai/epitaxy/local_example#settings/usage"), .usageOverlay)
        XCTAssertEqual(Reader.address("https://claude.ai/chat/example#settings/usage"), .firstParty)
        XCTAssertEqual(Reader.address("https://claude.ai/%73ettings/usage"), .firstParty)
        XCTAssertEqual(Reader.address("file:///app/index.html"), .wrapper)
        for url in ["http://claude.ai/settings/usage", "https://claude.ai.example.net/settings/usage",
                    "https://example.net@claude.ai/settings/usage", "https://claude.ai:1234/settings/usage",
                    "https://example.test/#https://claude.ai/settings/usage", "file:///tmp/chat.html"] {
            XCTAssertEqual(Reader.address(url), .other)
        }
    }

    func testRealHashOverlayUsesNamedMetersAndNeverReadsChatOrProductData() {
        let t = Tree()
        let chat = t.text("Aktuelle Sitzung · 99 % verwendet")
        let privateInput = t.node("AXTextArea", [kAXValueAttribute:"private"])
        let product = t.bar("Claude Code", "61 % verwendet")
        let settings = t.node("AXGroup", [kAXDescriptionAttribute:"Einstellungen"], [
            t.text("Dein Verbrauch"), t.text("Aktuelle Sitzung"), t.text("Wird um 22:20 zurückgesetzt"),
            t.bar("Aktuelle Sitzung", "4 % verwendet"), t.text("4 % verwendet"),
            t.text("Diese Woche"), t.text("Zurücksetzung am Fr., 21:00"), t.bar("Diese Woche","38 % verwendet"),
            t.text("Nutzung nach Produkt"), product, t.bar("Chats", "39 % verwendet")])
        let web = t.node("AXWebArea", [kAXURLAttribute:"https://claude.ai/epitaxy/local_example#settings/usage"],
                         [chat, privateInput, settings])
        XCTAssertEqual(t.read(t.window(web)), .usage(["Aktuelle Sitzung", "Wird um 22:20 zurückgesetzt",
            "4 % verwendet", "Diese Woche", "Zurücksetzung am Fr., 21:00", "38 % verwendet"]))
        t.assertNotRead(chat)
        t.assertNotRead(privateInput)
        XCTAssertFalse(t.queried[product]?.contains(kAXValueDescriptionAttribute) == true)
    }

    func testPopoverRequiresGenuineLinkAndNamedLimitsGroup() {
        for linked in [true, false] {
            let t = Tree()
            let limits = t.node("AXGroup", [kAXTitleAttribute:"Nutzungslimits"], [
                t.text("5-Stunden-Limit"), t.text("Wird um 22:20 zurückgesetzt"), t.bar("5-Stunden-Limit","4 % genutzt"),
                t.text("Wöchentlich · alle Modelle"), t.text("Zurücksetzung am Fr., 21:00"), t.bar("Wöchentlich · alle Modelle","38 % genutzt")])
            let link = t.node("AXLink", [kAXURLAttribute: linked ? "https://claude.ai/settings/usage" : "https://example.test/settings/usage"])
            let panel = t.node("AXGroup", [kAXTitleAttribute:"Nutzung"], [link, limits])
            let chat = t.text("5-Stunden-Limit 100 % genutzt")
            let area = t.node("AXWebArea",[kAXURLAttribute:"https://claude.ai/epitaxy/local_example"],[chat, panel])
            let expected: Reader.Result = linked ? .usage(["5-Stunden-Limit","Wird um 22:20 zurückgesetzt","4 % genutzt",
                                                           "Wöchentlich · alle Modelle","Zurücksetzung am Fr., 21:00","38 % genutzt"]) : .unavailable
            XCTAssertEqual(t.read(t.window(area)), expected)
            t.assertNotRead(chat)
        }
    }

    func testClosedButtonRequiresComposerAndOtherControlsWithoutReadingTheirText() {
        for composer in [true, false] {
            let t = Tree()
            let title = "Nutzung: Wöchentlich · alle Modelle: 38%, Zurücksetzung am Fr., 21:00"
            let button = t.node("AXPopUpButton", [kAXTitleAttribute:title])
            let input = t.node("AXTextArea", [kAXValueAttribute:"private draft"])
            let other = t.node("AXPopUpButton", [kAXTitleAttribute:"Auto"])
            let group = t.node("AXGroup", [:], composer ? [input, button, other] : [button])
            let message = t.text(title)
            let main = t.node("AXGroup", [kAXSubroleAttribute:"AXLandmarkMain"], [message, group])
            let web = t.node("AXWebArea", [kAXURLAttribute:"https://claude.ai/chat/example"], [main])
            XCTAssertEqual(t.read(t.window(web)), composer ? .usageButton(title) : .unavailable)
            t.assertNotRead(input)
            t.assertNotRead(message)
            if !composer { t.assertNotRead(button) }
        }
    }

    func testEmbeddedUntrustedDocumentsAndChatImitationsCannotAuthorizeARead() {
        let t = Tree()
        let fake = t.text("Current session: 75% used")
        let tab = t.node("AXRadioButton", [kAXTitleAttribute:"Usage",kAXValueAttribute:1])
        let tabs = t.node("AXTabGroup", [:], [tab])
        let trap = t.node("AXWebArea", [kAXURLAttribute:"https://example.test/settings/usage"], [tabs, fake])
        let win = t.node("AXWindow", [kAXTitleAttribute:"Settings"], [trap])
        XCTAssertEqual(t.read(win), .unavailable)
        t.assertNotRead(fake)
        t.assertNotRead(tab)
        let chatOnly = t.node("AXWebArea", [kAXURLAttribute:"https://claude.ai/chat/example"], [fake, tabs])
        XCTAssertEqual(t.read(t.window(chatOnly)), .unavailable)
        t.assertNotRead(fake)
    }

    func testNativeSettingsRequireSelectedUsageTabAndDirectDocumentPreservesVisibleText() {
        for selected in [true, false] {
            let t = Tree()
            let control = t.node("AXRadioButton", [kAXTitleAttribute:"Usage",kAXValueAttribute:selected])
            let tabs = t.node("AXTabGroup", [:], [control])
            let label = t.text("Current session")
            let value = t.text("14% used")
            let win = t.node("AXWindow", [kAXTitleAttribute:"Settings"], [tabs, label, value])
            XCTAssertEqual(t.read(win), selected ? .usage(["Current session","14% used"]) : .unavailable)
            if !selected { t.assertNotRead(value) }
        }
        let t = Tree(), hidden = t.node("AXStaticText", [kAXValueAttribute:"private",kAXHiddenAttribute:true])
        let web = t.node("AXWebArea", [kAXURLAttribute:"https://claude.ai/settings/usage"], [t.text("Current session"),hidden,t.text("5% used")])
        XCTAssertEqual(t.read(t.window(web)), .usage(["Current session","5% used"]))
        t.assertNotRead(hidden)
    }

    func testOnlyUnambiguousProgressScalesAndDescriptionsAreUsed() {
        XCTAssertEqual(Reader.progress("38 % verwendet", value: 38, min: 0, max: 100), "38 % verwendet")
        XCTAssertEqual(Reader.progress(nil, value: 0.4, min: 0, max: 1), "40%")
        XCTAssertEqual(Reader.progress(nil, value: 3.2, min: 0, max: 100), "3.2%")
        XCTAssertNil(Reader.progress(nil, value: 4, min: nil, max: nil))
        XCTAssertNil(Reader.progress(nil, value: 4, min: 0, max: 5))
        XCTAssertNil(Reader.progress(nil, value: .infinity, min: 0, max: 100))
    }
}
