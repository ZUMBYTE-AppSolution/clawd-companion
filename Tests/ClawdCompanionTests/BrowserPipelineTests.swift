import Foundation
import CryptoKit
import JavaScriptCore
import XCTest
@testable import ClawdCompanion

final class BrowserPipelineTests: XCTestCase {
    func testPairedWorkerUpdatesMascotAndBothQuotas() async throws {
        try await MainActor.run {
            let suite = "ClawdCompanionTests." + UUID().uuidString
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let state = CompanionState(defaults: defaults)
            state.webEnabled = true

            let context = try XCTUnwrap(JSContext())
            var errors: [String] = []
            context.exceptionHandler = { _, exception in errors.append(exception?.toString() ?? "JS error") }
            let token = String(repeating: "c", count: 64)
            var poses: [MascotPose] = []
            var notices: [BrowserBridge.Event] = []
            var approvalSignals: [Bool] = []
            let digest: @convention(block) ([NSNumber]) -> [NSNumber] = { input in
                SHA256.hash(data: Data(input.map(\.uint8Value))).map { NSNumber(value: $0) }
            }
            let transport: @convention(block) (String, String, String, String, String) -> Int = { url, method, contentType, auth, json in
                guard let address = URLComponents(string: url), let host = address.host, let port = address.port else { return 400 }
                let request = [
                    "\(method) \(address.path) HTTP/1.1", "Host: \(host):\(port)", "Authorization: \(auth)",
                    "Content-Type: \(contentType)", "Origin: chrome-extension://abcdefghijklmnopabcdefghijklmnop",
                    "Content-Length: \(json.utf8.count)", "", json
                ].joined(separator: "\r\n")
                switch BrowserRequest.parse(Data(request.utf8), token: token) {
                case .event(let event):
                    state.receive(event)
                    if case .activity = event { poses.append(state.pose) }
                    if case .notice = event { notices.append(event) }
                    if case let .approval(_, waiting) = event {
                        approvalSignals.append(waiting)
                        XCTAssertEqual(state.isAwaitingApproval, waiting)
                        if waiting { XCTAssertEqual(state.presentedPose, .awaitingApproval) }
                    }
                    return 200
                case .reject(let status): return status
                case .incomplete: return 400
                }
            }
            context.setObject(transport, forKeyedSubscript: "nativeRequest" as NSString)
            context.setObject(digest, forKeyedSubscript: "nativeSHA256" as NSString)
            context.setObject(token, forKeyedSubscript: "pairingCode" as NSString)
            let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            for source in ["BrowserTests/mac-transport.js", "BrowserExtension/signals.js", "BrowserExtension/background.js"] {
                let path = project.appendingPathComponent(source)
                context.evaluateScript(try String(contentsOf: path, encoding: .utf8), withSourceURL: path)
            }
            context.evaluateScript("exerciseWorker(pairingCode).then(() => globalThis.result = 'ok', e => globalThis.result = String(e))")
            XCTAssertEqual(errors, [])
            XCTAssertEqual(context.objectForKeyedSubscript("result")?.toString(), "ok")
            XCTAssertEqual(poses, [.idle, .thinking, .typing, .happy])
            XCTAssertEqual(approvalSignals, [true, false])
            XCTAssertEqual(notices, [.notice(title: "Claude.ai", message: "Bitte erneut versuchen.", kind: "error")])
            XCTAssertEqual(state.pose, .worried)
            XCTAssertTrue(state.webConnected)
            XCTAssertEqual(state.webReport?.session?.remaining, 75)
            XCTAssertEqual(state.webReport?.week?.remaining, 60)
            let report = try XCTUnwrap(state.webReport)
            XCTAssertEqual(try XCTUnwrap(report.session?.reset).timeIntervalSince(report.seen), 7200, accuracy: 1)
            XCTAssertEqual(try XCTUnwrap(report.week?.reset).timeIntervalSince(report.seen), 4 * 86400, accuracy: 1)
        }
    }
}
