import XCTest
@testable import ClawdCompanion

final class ReleaseUpdateTests: XCTestCase {
    private func data(_ version: String = "0.10.0", assets: [String]? = nil) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["schema": 1, "version": version, "tag": "v" + version,
            "notes": "## Changes\n- Item", "notesByLanguage": ["de": "Änderungen", "pt-BR": "Brasil"],
            "assets": assets ?? ["Clawd-Companion-\(version)-macOS-universal.pkg"]])
    }

    func testSemVerOrderingIncludingPrereleasesAndInvalidInput() throws {
        let versions = ["0.6.2", "0.6.10", "1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-alpha.beta",
                        "1.0.0-beta", "1.0.0-beta.2", "1.0.0-beta.11", "1.0.0-rc.1", "1.0.0"]
        let parsed = try versions.map { try XCTUnwrap(ReleaseVersion($0)) }
        for (a, b) in zip(parsed, parsed.dropFirst()) { XCTAssertLessThan(a, b) }
        XCTAssertEqual(ReleaseVersion("1.2.3+abc"), ReleaseVersion("1.2.3+2"))
        for bad in ["01.0.1", "1.0", "1.0.0-01", "v1.0.0", "1.0.0\n", "../2.0.0", "1.0.0?url="] {
            XCTAssertNil(ReleaseVersion(bad), bad)
        }
    }

    func testNoAPIRequiresExactAssetAndSafeRedirects() throws {
        let release = try CompanionRelease(data: data())
        XCTAssertEqual(CompanionRelease.manifestURL.absoluteString,
                       "https://github.com/ZUMBYTE-AppSolution/clawd-companion/releases/latest/download/clawd-update.json")
        XCTAssertEqual(release.localizedNotes("de-DE"), "Änderungen")
        XCTAssertEqual(release.localizedNotes("pt_BR"), "Brasil")
        XCTAssertEqual(release.localizedNotes("en"), release.notes)
        XCTAssertEqual(release.download?.absoluteString,
                       "https://github.com/ZUMBYTE-AppSolution/clawd-companion/releases/download/v0.10.0/Clawd-Companion-0.10.0-macOS-universal.pkg")
        XCTAssertNil(try CompanionRelease(data: data(assets: ["malware.pkg", "file:///tmp/other"])).download)
        XCTAssertNotNil(try CompanionRelease(data: data(assets: ["Clawd-Companion-0.10.0-macOS-universal.zip"])).download)
        XCTAssertThrowsError(try CompanionRelease(data: data(assets: [])))
        XCTAssertThrowsError(try CompanionRelease(data: Data(count: CompanionRelease.limit + 1)))
        XCTAssertTrue(CompanionRelease.trustedMetadataURL(release.page))
        XCTAssertTrue(CompanionRelease.trustedMetadataURL(URL(string: "https://release-assets.githubusercontent.com/download")))
        for url in ["https://api.github.com/a", "https://github.com/some/other/repository",
                    "https://objects.githubusercontent.com:39/blob", "file:///tmp/something",
                    "http://release-assets.githubusercontent.com/a", "https://evil@release-assets.githubusercontent.com/path"] {
            XCTAssertFalse(CompanionRelease.trustedMetadataURL(URL(string: url)))
        }
    }

    @MainActor func testCheckingNotificationDeduplicationAndOfflineRecovery() async throws {
        let suite = "ClawdUpdates." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var offline = true
        var calls = 0
        let next = try CompanionRelease(data: data())
        let center = ReleaseUpdateCenter(defaults: defaults, installed: ReleaseVersion("0.6.0")!) {
            calls += 1
            if offline { throw URLError(.notConnectedToInternet) }
            return next
        }
        var notices: [String] = []
        center.onAvailable = { notices.append($0) }
        await center.check()?.value
        XCTAssertEqual(center.status, .failed)
        offline = false
        let pending = center.check()
        _ = center.check()
        await pending?.value
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(center.status, .available)
        await center.check()?.value
        XCTAssertEqual(notices, ["0.10.0"])
        let current = ReleaseUpdateCenter(defaults: defaults, installed: ReleaseVersion("0.10.0")!) { next }
        await current.check()?.value
        XCTAssertEqual(current.status, .current)
        center.stop()
    }
}
