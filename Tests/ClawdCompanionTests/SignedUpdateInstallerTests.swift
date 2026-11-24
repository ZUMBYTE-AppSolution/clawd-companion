import XCTest
@testable import ClawdCompanion

final class SignedUpdateInstallerTests: XCTestCase {
    func testImageLayoutRequiresTheRealAppAndApplicationsDestination() throws {
        let fm = FileManager.default
        let volume = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: volume, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: volume) }
        let app = volume.appendingPathComponent("Clawd Companion.app")
        let destination = volume.appendingPathComponent("Applications")
        try fm.createDirectory(at: app, withIntermediateDirectories: false)
        try fm.createSymbolicLink(atPath: destination.path, withDestinationPath: "/Applications")
        XCTAssertEqual(try SignedUpdateInstaller.appInVolume(volume).path, app.path)

        let unexpected = volume.appendingPathComponent("Installer.command")
        try Data().write(to: unexpected)
        XCTAssertThrowsError(try SignedUpdateInstaller.appInVolume(volume))
        try fm.removeItem(at: unexpected)
        try fm.removeItem(at: destination)
        try fm.createSymbolicLink(atPath: destination.path, withDestinationPath: "/tmp")
        XCTAssertThrowsError(try SignedUpdateInstaller.appInVolume(volume))
        try fm.removeItem(at: destination)
        try fm.createSymbolicLink(atPath: destination.path, withDestinationPath: "/Applications")
        try fm.removeItem(at: app)
        try fm.createSymbolicLink(atPath: app.path, withDestinationPath: "/Applications")
        XCTAssertThrowsError(try SignedUpdateInstaller.appInVolume(volume))
    }

    func testInstallerLeafMustBelongToRunningTeam() {
        let team = "TEAM123456"
        let match = SignedUpdateInstaller.matchesInstallerLeaf
        XCTAssertTrue(match("   1. Developer ID Installer: Example (TEAM123456)\n   2. Developer ID Certification Authority", team))
        XCTAssertFalse(match("1. Developer ID Installer: Example (OTHER12345)\n2. Developer ID Installer: Example (TEAM123456)", team))
        XCTAssertFalse(match("1. Developer ID Application: Example (TEAM123456)", team))
        XCTAssertFalse(match("Status: no signature", team))
    }
}
