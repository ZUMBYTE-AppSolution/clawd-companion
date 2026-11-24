import AppKit
import Foundation
import Security

enum UpdateInstallError: Error { case unsignedApp, invalidPackage, download, launch }

enum SignedUpdateInstaller {
    static func currentTeam() -> String? {
        var code: SecCode?, staticCode: SecStaticCode?, info: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let team = (info as NSDictionary?)?[kSecCodeInfoTeamIdentifier] as? String,
              team.range(of: #"^[A-Z0-9]{10}\z"#, options: .regularExpression) != nil else { return nil }
        return team
    }

    static func matchesInstallerLeaf(_ output: String, team: String) -> Bool {
        output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.contains {
            $0.hasPrefix("1. Developer ID Installer: ") && $0.hasSuffix("(" + team + ")")
        }
    }

    private static func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL": "C"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UpdateInstallError.invalidPackage }
        return String(decoding: data, as: UTF8.self)
    }

    /// A release image contains the app and a drag destination. Resolve the
    /// latter explicitly before showing a downloaded volume in Finder.
    static func appInVolume(_ volume: URL) throws -> URL {
        let fm = FileManager.default
        let names = try fm.contentsOfDirectory(atPath: volume.path).filter { !$0.hasPrefix(".") }
        let app = volume.appendingPathComponent("Clawd Companion.app")
        let type = try app.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard Set(names) == ["Clawd Companion.app", "Applications"], type.isDirectory == true,
              type.isSymbolicLink != true,
              try fm.destinationOfSymbolicLink(atPath: volume.appendingPathComponent("Applications").path) == "/Applications"
        else { throw UpdateInstallError.invalidPackage }
        return app
    }

    private static func verifyApp(_ app: URL, team: String, version: ReleaseVersion) throws {
        guard team.range(of: #"^[A-Z0-9]{10}\z"#, options: .regularExpression) != nil,
              let identifier = Bundle.main.bundleIdentifier,
              identifier == "de.zumbyte.clawdcompanion",
              let bundle = Bundle(url: app), bundle.bundleIdentifier == identifier,
              bundle.infoDictionary?["CFBundleShortVersionString"] as? String == version.raw
        else { throw UpdateInstallError.invalidPackage }
        // Check nested code as well as the outer seal. Apply the app-specific
        // requirement separately because its extension has its own identifier.
        _ = try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", "--all-architectures", app.path])
        let requirement = "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(team)\" and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
        _ = try run("/usr/bin/codesign", ["--verify", "--all-architectures", "-R=" + requirement, app.path])
        _ = try run("/usr/sbin/spctl", ["--assess", "--type", "execute", app.path])
    }

    static func prepare(_ release: CompanionRelease, team: String) async throws -> URL {
        guard let url = release.download, let filename = release.macPackage, ["pkg", "dmg"].contains(url.pathExtension)
        else { throw UpdateInstallError.invalidPackage }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForResource = 180
        let session = URLSession(configuration: config, delegate: CompanionRelease.Redirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (file, response) = try await session.download(from: url)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              CompanionRelease.trustedMetadataURL(response.url),
              let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              (1...(128 * 1024 * 1024)).contains(size) else { throw UpdateInstallError.download }
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent("clawd-update-" + UUID().uuidString)
        try fm.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let package = directory.appendingPathComponent(filename)
        let mount = directory.appendingPathComponent("Volume", isDirectory: true)
        var mounted = false
        do {
            try fm.moveItem(at: file, to: package)
            if url.pathExtension == "dmg" {
                try fm.createDirectory(at: mount, withIntermediateDirectories: false)
                _ = try run("/usr/bin/hdiutil", ["attach", "-readonly", "-nobrowse", "-noautoopen", "-verify",
                                                "-mount", "required", "-mountpoint", mount.path, package.path])
                mounted = true
                let app = try appInVolume(mount)
                try verifyApp(app, team: team, version: release.version)
                return app
            }
            let signature = try run("/usr/sbin/pkgutil", ["--check-signature", package.path])
            guard matchesInstallerLeaf(signature, team: team) else { throw UpdateInstallError.invalidPackage }
            _ = try run("/usr/sbin/spctl", ["--assess", "--type", "install", package.path])
            return package
        } catch {
            if !mounted || (try? run("/usr/bin/hdiutil", ["detach", mount.path])) != nil {
                try? fm.removeItem(at: directory)
            }
            throw error
        }
    }
}
