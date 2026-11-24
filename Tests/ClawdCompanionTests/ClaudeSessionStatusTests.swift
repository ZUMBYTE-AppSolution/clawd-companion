import XCTest
@testable import ClawdCompanion

final class ClaudeSessionStatusTests: XCTestCase {
    func testDecodesOnlyDocumentedObservationsForRequestedIdentities() throws {
        let data = Data(#"""
        [
          {"sessionId":"a","status":"busy","cwd":"/unrelated","name":"ignored"},
          {"sessionId":"a","status":"waiting","waitingFor":"sandbox request"},
          {"sessionId":"b","status":"waiting","waitingFor":"permission prompt"},
          {"sessionId":"c","status":"waiting","waitingFor":"input needed"},
          {"sessionId":"d","state":"blocked"},
          {"sessionId":"e","status":"waiting","waitingFor":"a future status"},
          {"sessionId":"f","state":"done"},
          {"sessionId":"g","status":"busy"},
          {"id":"short-id","status":"waiting","waitingFor":"permission prompt"},
          {"sessionId":"other","status":"idle"}
        ]
        """#.utf8)
        let keys = Set(["a", "b", "c", "d", "e", "f", "g", "short-id"].map(ClaudeSessionStatus.sessionKey))
        let states = try XCTUnwrap(ClaudeAgentList.decode(data, sessionKeys: keys))
        XCTAssertEqual(ClaudeSessionStatus.sessionKey("a"), "ca978112ca1bbdcafac231b39a23dc4da786eff8147c4e72b9807785afee48bb")
        XCTAssertEqual(states, [
            ClaudeSessionStatus.sessionKey("a"): true, ClaudeSessionStatus.sessionKey("b"): true,
            ClaudeSessionStatus.sessionKey("c"): false, ClaudeSessionStatus.sessionKey("f"): false,
            ClaudeSessionStatus.sessionKey("g"): false
        ])
        XCTAssertNil(ClaudeAgentList.decode(Data("3 agents configured".utf8), sessionKeys: keys))
    }

    func testDebouncesTransientBusyAndNeverReusesPriorPermissionGeneration() {
        var samples = ClaudeApprovalSamples()
        let first = Date(timeIntervalSince1970: 100), second = first.addingTimeInterval(5)
        let requests = ["main": first, "independent": second]
        XCTAssertTrue(samples.observe(["main": false, "independent": true], requests: requests).isEmpty)
        XCTAssertTrue(samples.observe(["main": true, "independent": true], requests: requests).isEmpty)
        XCTAssertEqual(samples.observe(["main": false, "independent": true], requests: requests), ["main": first])
        let changed = ["main": second, "independent": second]
        samples.retain(changed)
        XCTAssertEqual(samples.observe(["main": false, "independent": false], requests: changed), ["independent": second])
        XCTAssertTrue(samples.observe([:], requests: changed).isEmpty)
        XCTAssertTrue(samples.observe(["main": false], requests: changed).isEmpty)
        XCTAssertEqual(samples.observe(["main": false], requests: changed), ["main": second])
        samples.retain([:])
        XCTAssertTrue(samples.observe(["main": false], requests: changed).isEmpty)
    }

    func testBoundedProcessReaderHandlesSuccessFailureLargeOutputAndTimeout() throws {
        let echo = URL(fileURLWithPath: "/bin/echo")
        let data = try XCTUnwrap(ClaudeAgentList.output(executable: echo, arguments: ["[]"], environment: [:]))
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "[]\n")
        XCTAssertNil(ClaudeAgentList.output(executable: echo, arguments: ["toolong"], environment: [:], limit: 3))
        XCTAssertNil(ClaudeAgentList.output(executable: URL(fileURLWithPath: "/usr/bin/false"), arguments: [], environment: [:]))
        let start = ProcessInfo.processInfo.systemUptime
        XCTAssertNil(ClaudeAgentList.output(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["4"],
                                           environment: [:], timeout: 0.12))
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 2)
    }

    @MainActor func testPendingWorkIsSingleFlightAndRestartDropsOldResult() async throws {
        final class Reader: @unchecked Sendable {
            let began = DispatchSemaphore(value: 0)
            let release = DispatchSemaphore(value: 0)
            private let lock = NSLock()
            private var calls = 0
            var count: Int { lock.withLock { calls } }
            func read(_ keys: Set<String>) -> [String: Bool]? {
                lock.withLock { calls += 1 }
                began.signal()
                _ = release.wait(timeout: .now() + 2)
                return Dictionary(uniqueKeysWithValues: keys.map { ($0, false) })
            }
        }
        let reader = Reader()
        var clock: TimeInterval = 0
        let status = ClaudeSessionStatus(read: { reader.read($0) }, uptime: { clock })
        let requested = ["main": Date(timeIntervalSince1970: 200)]
        var responses: [[String: Date]] = []
        func poll() { status.update(pending: requested) { responses.append($0) } }
        status.update(pending: [:]) { _ in XCTFail() }
        XCTAssertEqual(reader.count, 0)
        poll()
        XCTAssertEqual(reader.began.wait(timeout: .now() + 1), .success)
        poll()
        status.stop()
        poll()
        XCTAssertEqual(reader.count, 1)
        reader.release.signal()
        // Wait for the cancelled query to yield its slot.
        for _ in 0..<50 where reader.count < 2 {
            try await Task.sleep(nanoseconds: 5_000_000)
            poll()
        }
        XCTAssertEqual(reader.count, 2)
        reader.release.signal()
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertTrue(responses.isEmpty)
        // A fresh observation still needs its own confirming sample.
        clock = 5
        poll()
        XCTAssertEqual(reader.began.wait(timeout: .now() + 1), .success)
        reader.release.signal()
        for _ in 0..<50 where responses.isEmpty { try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertEqual(responses, [requested])
        status.stop()
    }
}
