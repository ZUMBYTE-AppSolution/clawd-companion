import AppKit
import SwiftUI

if CommandLine.arguments.dropFirst().first == "--clawd-code-hook" {
    ClaudeHooks.receive()
    exit(0)
}
if QuotaStatusLine.handleCommandLine() { exit(0) }

@MainActor
final class CompanionDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let state = CompanionState()
    private var statusItem: NSStatusItem?
    private var window: NSWindow?
    private var desktop: OverlayController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        CompanionAppearance.apply(UserDefaults.standard.string(forKey: "appearance") ?? "system")
        let running = NSRunningApplication.current
        if let id = running.bundleIdentifier,
           let previous = NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .filter({ $0.processIdentifier != running.processIdentifier && !$0.isTerminated })
            .first(where: { $0.launchDate ?? .distantPast <= running.launchDate ?? .distantFuture }) {
            if let url = previous.bundleURL {
                let options = NSWorkspace.OpenConfiguration()
                options.activates = true
                NSWorkspace.shared.openApplication(at: url, configuration: options)
            }
            NSApp.terminate(nil)
            return
        }

        NSApp.setActivationPolicy(.accessory)
        installMainMenu()
        NotificationCenter.default.addObserver(self, selector: #selector(installMainMenu), name: .clawdLanguageChanged, object: nil)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menuMascot = item.button.map { MenuMascot(button: $0) }
        item.button?.target = self
        item.button?.action = #selector(statusPressed)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
        let overlay = OverlayController(onOpenPanel: { [weak self] in self?.showWindow() })
        desktop = overlay
        state.start(overlay: overlay, menuMascot: menuMascot)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(refreshUsageAfterWake(_:)),
                                                          name: NSWorkspace.didWakeNotification, object: nil)
        showWindow()
    }

    @objc private func installMainMenu() {
        let menuBar = NSMenu()
        let appEntry = menuBar.addItem(withTitle: "Claw’d", action: nil, keyEquivalent: "")
        let appMenu = NSMenu(title: "Claw’d")
        appMenu.addItem(withTitle: L("Claw’d beenden"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appEntry.submenu = appMenu
        let windows = menuBar.addItem(withTitle: L("Fenster"), action: nil, keyEquivalent: "")
        let windowMenu = NSMenu(title: L("Fenster"))
        windowMenu.addItem(withTitle: L("Fenster schließen"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windows.submenu = windowMenu
        NSApp.mainMenu = menuBar
    }

    @objc private func statusPressed() {
        if NSApp.currentEvent?.type == .rightMouseUp || NSEvent.modifierFlags.contains(.control) {
            let menu = NSMenu()
            menu.delegate = self
            let entries: [(String, Selector)] = [
                (L("Claw’d öffnen"), #selector(openFromMenu)),
                (state.showOverlay ? L("Figur ausblenden") : L("Figur einblenden"), #selector(toggleOverlay)),
                (L("Claw’d beenden"), #selector(quit))
            ]
            for (text, action) in entries {
                let item = menu.addItem(withTitle: text, action: action, keyEquivalent: "")
                item.target = self
            }
            if let button = statusItem?.button {
                menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY - 4), in: button)
            }
        } else if let window, window.isKeyWindow && window.isVisible { window.orderOut(nil) }
        else { showWindow() }
    }

    @objc private func openFromMenu() { showWindow() }
    @objc private func toggleOverlay() { state.showOverlay.toggle() }
    @objc private func quit() { NSApp.terminate(nil) }

    func showWindow() {
        if window == nil {
            let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 458, height: 580),
                                 styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                 backing: .buffered, defer: false)
            panel.title = "Claw’d Companion"
            panel.minSize = NSSize(width: 452, height: 518)
            panel.maxSize = NSSize(width: 590, height: 950)
            panel.isReleasedWhenClosed = false
            panel.backgroundColor = .windowBackgroundColor
            panel.contentView = NSHostingView(rootView: CompanionPanel(state: state))
            panel.center()
            panel.setFrameAutosaveName("ClawdCompanion.ControlPanel")
            window = panel
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.deminiaturize(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    @objc nonisolated private func refreshUsageAfterWake(_ notification: Notification) {
        Task { @MainActor [weak self] in self?.state.refreshDesktopUsage() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.removeObserver(self, name: NSWorkspace.didWakeNotification, object: nil)
        state.stop()
    }
}

MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = CompanionDelegate()
    application.delegate = delegate
    withExtendedLifetime(delegate) { application.run() }
}
