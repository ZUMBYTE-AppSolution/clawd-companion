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
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UpdateInstallError.invalidPackage }
        return String(decoding: data, as: UTF8.self)
    }

    static func prepare(_ release: CompanionRelease, team: String) async throws -> URL {
        guard let url = release.download, let filename = release.macPackage, filename.hasSuffix(".pkg")
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
        do {
            try fm.moveItem(at: file, to: package)
            let signature = try run("/usr/sbin/pkgutil", ["--check-signature", package.path])
            guard matchesInstallerLeaf(signature, team: team) else { throw UpdateInstallError.invalidPackage }
            _ = try run("/usr/sbin/spctl", ["--assess", "--type", "install", package.path])
            return package
        } catch {
            try? fm.removeItem(at: directory)
            throw error
        }
    }
}
