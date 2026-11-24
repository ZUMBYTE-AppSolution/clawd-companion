import XCTest
@testable import ClawdCompanion

final class SignedUpdateInstallerTests: XCTestCase {
    func testInstallerLeafMustBelongToRunningTeam() {
        let team = "TEAM123456"
        let match = SignedUpdateInstaller.matchesInstallerLeaf
        XCTAssertTrue(match("   1. Developer ID Installer: Example (TEAM123456)\n   2. Developer ID Certification Authority", team))
        XCTAssertFalse(match("1. Developer ID Installer: Example (OTHER12345)\n2. Developer ID Installer: Example (TEAM123456)", team))
        XCTAssertFalse(match("1. Developer ID Application: Example (TEAM123456)", team))
        XCTAssertFalse(match("Status: no signature", team))
    }
}
