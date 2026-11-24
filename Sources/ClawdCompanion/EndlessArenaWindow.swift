import AppKit
import SwiftUI
import WebKit

struct EndlessArenaCard: View {
    @AppStorage("endlessArenaBest") private var best = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(L("Endlos-Arena")) { EndlessArenaWindow.shared.open() }
                .buttonStyle(.borderedProminent)
            if best > 0 {
                Text("\(L("Bestleistung")) · \(L("Level")) \((best-1)/4+1) · \(L("Welle")) \((best-1)%4+1)")
                    .font(.caption)
            }
        }
    }
}

@MainActor
final class EndlessArenaWindow: NSObject, WKScriptMessageHandler, NSWindowDelegate {
    static let shared = EndlessArenaWindow()
    private var window: NSWindow?

    func open() {
        if let window { window.makeKeyAndOrderFront(nil); return }
        guard let directory = L10n.directory?.deletingLastPathComponent().appendingPathComponent("EndlessArena") else { return }
        let configuration = WKWebViewConfiguration()
        let controller = configuration.userContentController
        let labels = ["Endlos-Arena","Level","Welle","Bestleistung","Spielen","Pause","Spiel vorbei","Mehrfachschuss","Flächenschaden","Durchschuss","Schnellfeuer","Bewegen"].map { L($0) }
        let settings: [String: Any] = ["labels": labels,
            "volume": (UserDefaults.standard.object(forKey: "soundEnabled") as? Bool ?? true) ? (UserDefaults.standard.object(forKey: "soundVolume") as? Double ?? 0.28) : 0,
            "muted": UserDefaults.standard.stringArray(forKey: "mutedSounds") ?? [],
            "best": UserDefaults.standard.integer(forKey: "endlessArenaBest")]
        guard let data = try? JSONSerialization.data(withJSONObject: settings), let json = String(data: data, encoding: .utf8) else { return }
        controller.addUserScript(WKUserScript(source: "window.arenaSettings = \(json)", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        controller.add(self, name: "record")
        let web = WKWebView(frame: .zero, configuration: configuration)
        let frame = NSApp.keyWindow?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1024, height: 768)
        let window = NSWindow(contentRect: frame, styleMask: [.titled,.closable,.resizable,.miniaturizable], backing: .buffered, defer: false)
        window.title = L("Endlos-Arena")
        window.isReleasedWhenClosed = false
        window.contentView = web
        window.delegate = self
        self.window = window
        window.setFrame(frame, display: true)
        web.loadFileURL(directory.appendingPathComponent("index.html"), allowingReadAccessTo: directory)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(web)
        NSApp.activate(ignoringOtherApps: true)
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let progress = message.body as? Int,
              progress > UserDefaults.standard.integer(forKey: "endlessArenaBest") else { return }
        UserDefaults.standard.set(progress, forKey: "endlessArenaBest")
    }

    func windowWillClose(_ notification: Notification) { window = nil }
}
