import XCTest
@testable import ClawdCompanion

private final class MemoryArenaVault: ArenaSessionVault {
    var login: ArenaLogin?
    func read() throws -> ArenaLogin? { login }
    func save(_ login: ArenaLogin) throws { self.login = login }
    func clear() throws { login = nil }
}

private final class ArenaFixtureTransport: URLProtocol {
    static let runID = "0123456789abcdef0123456789abcdef"
    static let origin = "https://arena.invalid/fixture/site"

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url else { return }
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "arena.invalid")
        XCTAssertTrue(url.path.hasPrefix("/fixture/site/"))
        let route = String(url.path.dropFirst("/fixture/site/".count))
        let me: [String:Any] = ["username":"demo","score":30,"wins":1,"kd":2.0,"kills":2,"deaths":1]
        var body: [String: Any] = [:]
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data(), bytes = [UInt8](repeating: 0, count: 2048)
            while stream.hasBytesAvailable {
                let n = stream.read(&bytes, maxLength: bytes.count)
                if n <= 0 { break }
                data.append(contentsOf: bytes.prefix(n))
            }
            body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        } else if let data = request.httpBody {
            body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        }
        let mortal = request.value(forHTTPHeaderField: "Authorization") == "Bearer mortal"
        var code = 200, output: [String: Any] = [:]
        func frame(_ terminal: Bool) -> [String: Any] {
            ["id": Self.runID, "phase": terminal ? (mortal ? "dead":"victory"):"wave", "wave":1, "hp":100, "hero":["x":40,"y":80],
             "enemies":[], "pickups":[], "shots":[], "kills":terminal ? 1:0, "assists":terminal ? 1:0,
             "ranked":terminal, "seq":terminal ? 1:0, "score":terminal ? 12:0]
        }
        switch route {
        case "register":
            XCTAssertEqual(Set(body.keys), ["username","email","password"])
            XCTAssertEqual(body["username"] as? String,"demo")
            XCTAssertEqual(request.httpMethod,"POST")
            output = ["username":"demo","token":"sample-token"]
        case "me":
            if request.value(forHTTPHeaderField:"Authorization") == "Bearer expired" {
                code=401; output=["error":"unauthorized"]
            } else { output=me }
        case "leaderboard":
            let newcomer: [String: Any] = ["rank":2,"username":"new","score":0,"wins":0,"kd":NSNull(),"kills":0,"deaths":0]
            output=["players":[me.merging(["rank":1]) { _, v in v }, newcomer]]
        case "runs": output=frame(false)
        case "runs/" + Self.runID: output=frame(false)
        case "runs/" + Self.runID + "/click":
            XCTAssertEqual(Set(body.keys), ["x","y","seq"])
            XCTAssertEqual(body["seq"] as? Int, 1)
            XCTAssertEqual(body["x"] as? Double, 33)
            XCTAssertEqual(body["y"] as? Double, 47)
            output=frame(true)
        case "logout": output=["ok":true]
        default: XCTFail("Unexpected fixture route"); code=404;output=["error":"not_found"]
        }
        if route != "register", !mortal, request.value(forHTTPHeaderField:"Authorization") != "Bearer expired" {
            XCTAssertEqual(request.value(forHTTPHeaderField:"Authorization"),"Bearer sample-token")
        }
        let response = HTTPURLResponse(url:url,statusCode:code,httpVersion:"HTTP/1.1",headerFields:["Content-Type":"application/json"])!
        client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:(try? JSONSerialization.data(withJSONObject:output)) ?? Data())
        client?.urlProtocolDidFinishLoading(self)
    }
}

private final class DiscoveryFixtureTransport: URLProtocol {
    private static let lock = NSLock()
    private static var reply = Data()
    private static var status = 200
    private static var responseURL: URL?
    private static var count = 0

    static var requests: Int { lock.withLock { count } }

    static func configure(_ bytes: Data, status: Int = 200, responseURL: URL? = nil) {
        lock.withLock {
            reply = bytes
            self.status = status
            self.responseURL = responseURL
            count = 0
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let (data, code, redirected) = Self.lock.withLock {
            Self.count += 1
            return (Self.reply, Self.status, Self.responseURL)
        }
        guard let url = request.url else { return XCTFail("Missing discovery URL") }
        XCTAssertEqual(url.absoluteString, "https://arena.invalid/.well-known/clawd-companion.json")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertFalse(request.httpShouldHandleCookies)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        XCTAssertNil(request.httpBody)
        XCTAssertNil(request.httpBodyStream)
        let response = HTTPURLResponse(url: redirected ?? url, statusCode: code, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}

@MainActor final class ArenaAccountTests: XCTestCase {
    private func transport(_ kind: URLProtocol.Type) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [kind]
        return URLSession(configuration: config)
    }

    private func fixture(_ configured: String?) -> ArenaAccountClient {
        ArenaAccountClient(session: transport(ArenaFixtureTransport.self), fixtureEndpoint: configured,
                           discoverySession: transport(DiscoveryFixtureTransport.self))
    }

    private func account(_ vault: MemoryArenaVault) -> ArenaAccountModel {
        ArenaAccountModel(client: fixture(ArenaFixtureTransport.origin), vault: vault)
    }

    func testEmbeddedConfigurationTakesPriorityAndRejectsMalformedOriginsWithoutDiscovery() async throws {
        DiscoveryFixtureTransport.configure(Data())
        let client = fixture(ArenaFixtureTransport.origin + "/\r\n")
        let me = try await client.me("sample-token")
        XCTAssertEqual(me.username, "demo")
        for invalid in ["", "http://arena.invalid", "https://elsewhere.invalid",
                        "https://arena.invalid.evil.invalid/a", "https://a@arena.invalid/z", "https://arena.invalid:443/z",
                        "https://arena.invalid/../z", "https://arena.invalid/%2e%2e/z", "https://arena.invalid/%2F",
                        "https://arena.invalid//z", "https://arena.invalid?x=1", "https://arena.invalid/#"] {
            do {
                _ = try await fixture(invalid).authenticate(name: "demo", email: nil, password: "fixture-password")
                XCTFail("Invalid configured endpoint was accepted")
            } catch let error as ArenaAccountFailure {
                XCTAssertEqual(error, .unavailable)
            }
        }
        XCTAssertEqual(DiscoveryFixtureTransport.requests, 0)
    }

    func testNoConfigurationDiscoversOnceBeforeParallelAuthenticatedRequests() async throws {
        let config = try JSONSerialization.data(withJSONObject: ["arena": ArenaFixtureTransport.origin + "/"])
        DiscoveryFixtureTransport.configure(config)
        let client = fixture(nil)
        XCTAssertEqual(DiscoveryFixtureTransport.requests, 0)
        async let me = client.me("sample-token")
        async let board = client.leaderboard("sample-token")
        let (player, leaders) = try await (me, board)
        XCTAssertEqual(player.username, "demo")
        XCTAssertEqual(leaders.count, 2)
        XCTAssertEqual(DiscoveryFixtureTransport.requests, 1)
        _ = try await client.me("sample-token")
        XCTAssertEqual(DiscoveryFixtureTransport.requests, 1)
    }

    func testOfflineOrUnsafeDiscoveryDoesNotCacheAPathOrSendTheOriginalRequest() async throws {
        let good = try JSONSerialization.data(withJSONObject: ["arena": ArenaFixtureTransport.origin])
        let untrusted = URL(string: "https://elsewhere.invalid/redirect")!
        let responses: [(Data, Int, URL?)] = [
            (Data("{}".utf8), 200, nil), (Data(repeating: 65, count: 2049), 200, nil),
            (Data(#"{"arena":"https://elsewhere.invalid/one"}"#.utf8), 200, nil),
            (Data(#"{"arena":"https://arena.invalid/../other"}"#.utf8), 200, nil),
            (Data(#"{"arena":"https://arena.invalid:443/"}"#.utf8), 200, nil),
            (good, 302, nil), (good, 200, untrusted), (Data(), 503, nil)
        ]
        for (data, status, redirected) in responses {
            DiscoveryFixtureTransport.configure(data, status: status, responseURL: redirected)
            let client = fixture(nil)
            do {
                _ = try await client.authenticate(name: "demo", email: nil, password: "fixture-password")
                XCTFail("Malformed discovery response was accepted")
            } catch let error as ArenaAccountFailure {
                XCTAssertEqual(error, .unavailable)
            }
            XCTAssertEqual(DiscoveryFixtureTransport.requests, 1)
            DiscoveryFixtureTransport.configure(good)
            let me = try await client.me("sample-token")
            XCTAssertEqual(me.username, "demo")
            XCTAssertEqual(DiscoveryFixtureTransport.requests, 1)
        }
    }

    func testInvalidRunRouteDoesNotTriggerDiscovery() async throws {
        DiscoveryFixtureTransport.configure(Data())
        let client = fixture(nil)
        for id in ["../me", "//elsewhere.invalid", "/runs", "a?b", "a%2fb", "a#b", String(repeating: "f", count: 33)] {
            do {
                _ = try await client.frame(id, token: "sample-token")
                XCTFail("Invalid run ID was accepted")
            } catch let error as ArenaAccountFailure {
                XCTAssertEqual(error, .unavailable)
            }
        }
        XCTAssertEqual(DiscoveryFixtureTransport.requests, 0)
    }

    func testRegistrationRankedClickAndLogoutUseServerFrames() async {
        let vault=MemoryArenaVault(), model=account(vault)
        await model.appear()
        XCTAssertNil(model.username)
        await model.authenticate(name:"demo",email:"demo@example.invalid",password:"fixture-only-password")
        XCTAssertEqual(vault.login?.token,"sample-token")
        XCTAssertEqual(model.leaders.first?.rank,1)
        XCTAssertNil(model.leaders.last?.kd)
        XCTAssertEqual(model.player?.kills,2)
        await model.startRound()
        XCTAssertEqual(model.round?.seq,0)
        XCTAssertEqual(model.round?.ranked,false)
        await model.updateRound(tapping:CGPoint(x:33,y:47))
        XCTAssertEqual(model.round?.phase,.victory)
        XCTAssertEqual(model.round?.score,12)
        XCTAssertEqual(model.round?.ranked,true)
        await model.logout()
        XCTAssertNil(vault.login)
        XCTAssertNil(model.username)
        XCTAssertNil(model.round)
        XCTAssertTrue(model.leaders.isEmpty)
    }

    func testConfirmedRankedDeathNotifiesOnceAcrossPollingAndSignOut() async {
        let vault = MemoryArenaVault()
        vault.login = ArenaLogin(token:"mortal",username:"demo")
        let model = account(vault)
        var deaths: [String] = []
        model.onRankedDeath = { deaths.append($0) }
        await model.appear()
        await model.startRound()
        await model.updateRound(tapping:CGPoint(x:33,y:47))
        await model.updateRound()
        await model.refresh()
        await model.logout()
        XCTAssertEqual(deaths, [ArenaFixtureTransport.runID])
    }

    func testLocalAndAuthorizedServerRoundsExcludeOneAnother() async {
        let suite = "ArenaMutex-" + UUID().uuidString, defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "soundEnabled")
        let vault = MemoryArenaVault()
        vault.login = ArenaLogin(token: "sample-token", username: "demo")
        let online = account(vault)
        let state = CompanionState(defaults: defaults, arenaAccount: online)
        await online.appear()
        state.startManualArena()
        await online.startRound()
        XCTAssertNil(online.round)
        state.manualArena.end()
        await online.startRound()
        XCTAssertTrue(online.occupiesArena)
        XCTAssertTrue(state.panelArenaReserved)
        XCTAssertFalse(state.canStartManualArena)
        state.startManualArena()
        XCTAssertFalse(state.manualArena.playing)
        await online.updateRound(tapping: CGPoint(x: 33, y: 47))
        XCTAssertFalse(online.occupiesArena)
        XCTAssertTrue(state.canStartManualArena)
    }

    func testExpiredRestoredTokenClearsProtectedState() async {
        let vault=MemoryArenaVault()
        vault.login=ArenaLogin(token:"expired",username:"demo")
        let model=account(vault)
        await model.appear()
        XCTAssertNil(vault.login)
        XCTAssertNil(model.username)
        XCTAssertNil(model.player)
        XCTAssertTrue(model.leaders.isEmpty)
        XCTAssertEqual(model.message,ArenaAccountFailure.rejected("unauthorized").message)
    }
}
