import SwiftUI

private struct ReleaseNotes: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(markdown.components(separatedBy: .newlines).enumerated()), id: \.offset) { _, line in
                let text = line.trimmingCharacters(in: .whitespaces)
                if !text.isEmpty {
                    let heading = text.prefix(while: { $0 == "#" })
                    let isHeading = !heading.isEmpty && text.dropFirst(heading.count).first == " "
                    let bullet = text.hasPrefix("- ") || text.hasPrefix("* ")
                    let content = isHeading ? String(text.dropFirst(heading.count + 1)) :
                        (bullet ? "• " + String(text.dropFirst(2)) : text)
                    Text((try? AttributedString(markdown: content, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                         ?? AttributedString(content))
                        .font(.system(size: isHeading ? 13 : 12, weight: isHeading ? .semibold : .regular))
                }
            }
        }.textSelection(.enabled).environment(\.openURL, OpenURLAction { _ in .discarded })
    }
}

private final class ReleaseInstallState: ObservableObject {
    @Published var installing = false
    @Published var message: String?
}

struct ReleaseInfoView: View {
    @StateObject private var install = ReleaseInstallState()
    @ObservedObject var updates: ReleaseUpdateCenter

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SmallLabel(text: "Info & Updates")
            Text("Claw’d Companion").font(.system(size: 22, weight: .medium, design: .serif))
            Text(L("Version {0}", updates.installed.raw)).font(.system(size: 12, design: .monospaced))
            if let message = statusLabel {
                Text(message).font(.system(size: 12, weight: .medium))
                    .foregroundStyle(updates.status == .available ? Ink.mint : Ink.dim)
            }
            HStack {
                Button(L("Nach Updates suchen")) { updates.check() }.disabled(updates.status == .checking)
                Link(L("Veröffentlichung öffnen"), destination: updates.release?.page ?? CompanionRelease.repository.appendingPathComponent("releases/latest"))
            }.font(.system(size: 12))
            if let release = updates.release {
                if release.version > updates.installed, let url = release.download {
                    if let team = SignedUpdateInstaller.currentTeam(), ["pkg", "dmg"].contains(url.pathExtension) {
                        Button {
                            install.installing = true
                            install.message = nil
                            Task {
                                defer { install.installing = false }
                                do {
                                    let file = try await SignedUpdateInstaller.prepare(release, team: team)
                                    if url.pathExtension == "dmg" {
                                        NSWorkspace.shared.activateFileViewerSelecting([file])
                                        install.message = "Ziehe Claw’d im Finder auf Programme, um das Update zu installieren."
                                    } else if !NSWorkspace.shared.open(file) {
                                        throw UpdateInstallError.launch
                                    }
                                } catch {
                                    install.message = "Update konnte nicht geprüft oder geöffnet werden."
                                }
                            }
                        } label: { Label(L("Update installieren"), systemImage: "arrow.down.circle") }
                        .disabled(install.installing)
                        if install.installing { ProgressView().controlSize(.small) }
                        if let message = install.message { Text(L(message)).font(.caption) }
                    } else {
                        Link(destination: url) { Label(L("Paket herunterladen"), systemImage: "arrow.down.circle") }
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
                Divider()
                Text(L("Änderungen in Version {0}", release.version.raw)).font(.system(size: 13, weight: .semibold))
                ReleaseNotes(markdown: release.localizedNotes(L10n.code))
            }
            Divider()
            Text("Zumbyte · AppSolution").font(.system(size: 14, weight: .semibold))
            Text(verbatim: "Andreas Zumbansen\nKastanienallee 16a · 59174 Kamen · DE\ninfo@zumbyte.de · +49 177 4149667")
                .textSelection(.enabled).font(.system(size: 12))
            Text(L("USt-IdNr. {0}", "DE347723697")).font(.system(size: 11)).foregroundStyle(Ink.dim)
            HStack {
                Link("Zumbyte.de", destination: URL(string: "https://zumbyte.de/")!)
                Link(L("Impressum"), destination: URL(string: "https://zumbyte.de/impressum/")!)
            }.font(.system(size: 12))
            Text(L("Liebe Grüße an die gesamte AI Coding Community. Danke fürs Bauen, Teilen und gegenseitige Helfen!"))
                .font(.system(size: 12)).foregroundStyle(Ink.dim)
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Ink.card))
    }

    private var statusLabel: String? {
        switch updates.status {
        case .idle: return nil
        case .checking: return L("Wird geprüft …")
        case .current: return L("Du verwendest die aktuelle Version.")
        case .available: return L("Version {0} ist verfügbar.", updates.release?.version.raw ?? "")
        case .failed: return L("Updates konnten nicht geprüft werden.")
        }
    }
}

struct ReleaseNoticeRow: View {
    @ObservedObject var updates: ReleaseUpdateCenter
    let open: () -> Void

    var body: some View {
        if let release = updates.release, release.version > updates.installed {
            Button(action: open) {
                Label(L("Version {0} ist verfügbar.", release.version.raw), systemImage: "arrow.down.circle")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Ink.mint)
            }.buttonStyle(.plain)
        }
    }
}
