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

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url else { return }
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "zumbyte.de")
        XCTAssertTrue(url.path.hasPrefix("/api/clawd/v1/"))
        let route = String(url.path.dropFirst("/api/clawd/v1/".count))
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

@MainActor final class ArenaAccountTests: XCTestCase {
    private func account(_ vault: MemoryArenaVault) -> ArenaAccountModel {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ArenaFixtureTransport.self]
        return ArenaAccountModel(client:ArenaAccountClient(session: URLSession(configuration:config)),vault:vault)
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
