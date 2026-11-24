import Foundation
import XCTest
@testable import ClawdCompanion

final class BrowserBridgeTests: XCTestCase {
    private let token = "test-pairing-secret"
    private let activity = #"{"type":"activity","state":"working"}"#

    private func request(_ payload: String, host: String = "127.0.0.1:49217",
                         origin: String? = nil, auth: String? = nil) -> Data {
        let extensionOrigin = origin.map { "Origin: \($0)\r\n" } ?? ""
        let header = "POST /v1/events HTTP/1.1\r\nHost: \(host)\r\nAuthorization: Bearer \(auth ?? token)\r\n\(extensionOrigin)Content-Type: application/json\r\nContent-Length: \(payload.utf8.count)\r\n\r\n"
        return Data((header + payload).utf8)
    }

    func testPacketBoundariesDoNotTruncateEvents() {
        let bytes = request(activity, origin: "chrome-extension://" + String(repeating: "a", count: 32))
        for size in 0..<bytes.count {
            XCTAssertEqual(BrowserRequest.parse(Data(bytes.prefix(size)), token: token), .incomplete)
        }
        XCTAssertEqual(BrowserRequest.parse(bytes, token: token), .event(.activity("working")))
    }

    func testOnlyPairedLoopbackWorkerCanPost() {
        XCTAssertEqual(BrowserRequest.parse(request(activity, host: "claude.example"), token: token), .reject(403))
        XCTAssertEqual(BrowserRequest.parse(request(activity, origin: "https://claude.ai"), token: token), .reject(403))
        XCTAssertEqual(BrowserRequest.parse(request(activity, auth: "incorrect"), token: token), .reject(401))
        XCTAssertEqual(BrowserRequest.parse(request(activity) + Data([13]), token: token), .reject(400))
        XCTAssertEqual(BrowserRequest.parse(request(String(repeating: "x", count: 4100)), token: token), .reject(413))
    }

    func testApprovalRequiresBooleanAndCanonicalPerBrowserIdentifier() {
        let id = "815cc349-15fe-4916-a60a-818f5d163745"
        let payload = "{\"type\":\"approval\",\"sourceID\":\"\(id)\",\"waiting\":true}"
        XCTAssertEqual(BrowserRequest.parse(request(payload), token: token), .event(.approval(sourceID: id, waiting: true)))
        for invalid in [payload.replacingOccurrences(of: "true", with: "\"true\""),
                        payload.replacingOccurrences(of: id, with: id.uppercased()),
                        payload.replacingOccurrences(of: id, with: "current-chat"),
                        payload.replacingOccurrences(of: "4916", with: "1916")] {
            XCTAssertEqual(BrowserRequest.parse(request(invalid), token: token), .reject(400))
        }
    }

    func testNoticeVocabularyBoundsAndPlainText() throws {
        func notice(_ title: String, _ message: String, kind: String = "warning") throws -> BrowserRequest.Result {
            let data = try JSONSerialization.data(withJSONObject: ["type": "notice", "title": title, "message": message, "kind": kind])
            return BrowserRequest.parse(request(String(decoding: data, as: UTF8.self)), token: token)
        }
        XCTAssertEqual(try notice(" Claude.ai ", "Zeitlimit\n erreicht"), .event(.notice(title: "Claude.ai", message: "Zeitlimit erreicht", kind: "warning")))
        XCTAssertEqual(try notice("Claude.ai", ""), .reject(400))
        XCTAssertEqual(try notice(String(repeating: "a", count: 66), "Limit"), .reject(400))
        XCTAssertEqual(try notice("Konto", String(repeating: "a", count: 221)), .reject(400))
        XCTAssertEqual(try notice("Status", "Unsichtbar\u{202e}x"), .reject(400))
        XCTAssertEqual(try notice("Konto", "Limit", kind: "script"), .reject(400))
    }

    func testQuotaIsValidatedAndOptionalResetIsPreserved() {
        let header = #"{"type":"usage","observedAt":"2026-01-03T16:00:00Z","windows":"#
        let payload = header + #"[{"kind":"session","remainingPercent":74,"resetLabel":"17:05 Uhr"},{"kind":"weekly","remainingPercent":9,"resetAt":"2026-01-08T08:00:00Z"}]}"#
        guard case let .event(.usage(_, windows)) = BrowserRequest.parse(request(payload), token: token) else {
            return XCTFail("Expected authenticated usage event")
        }
        XCTAssertNil(windows[0].resetAt)
        XCTAssertEqual(windows[0].resetLabel, "17:05 Uhr")
        XCTAssertEqual(windows[1].remainingPercent, 9)
        XCTAssertNotNil(windows[1].resetAt)
        XCTAssertEqual(BrowserRequest.parse(request(payload.replacingOccurrences(of: "74", with: "101")), token: token), .reject(400))
        XCTAssertEqual(BrowserRequest.parse(request(payload.replacingOccurrences(of: "weekly", with: "session")), token: token), .reject(400))
    }
}
