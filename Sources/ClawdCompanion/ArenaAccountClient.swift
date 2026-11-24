import Foundation
import Security

struct ArenaLogin: Codable, Equatable {
    let token: String
    let username: String
}

struct ArenaOnlinePlayer: Decodable, Identifiable {
    let rank: Int?
    let username: String
    let kills, deaths, wins, score: Int
    let kd: Double?
    var id: String { username }
}

struct ArenaOnlineFrame: Decodable {
    struct Point: Decodable { let x, y: Double }
    struct Enemy: Decodable {
        let id: Int
        let kind: String
        let x, y, radius: Double
        let hp, maxHP: Int
    }
    struct Pickup: Decodable {
        let id: Int
        let kind: String
        let x, y, radius: Double
    }
    struct Shot: Decodable { let x, y: Double; let hostile: Bool }
    enum Phase: String, Decodable { case wave, boss, dead, victory, expired }
    let id: String
    let phase: Phase
    let wave, hp: Int
    let hero: Point
    let enemies: [Enemy]
    let pickups: [Pickup]
    let shots: [Shot]
    let kills, assists, score, seq: Int
    let ranked: Bool
    var playing: Bool { phase == .wave || phase == .boss }
}

enum ArenaAccountFailure: Error, Equatable {
    case rejected(String)
    case unavailable
    case keychain

    var message: String {
        switch self {
        case .keychain: return "Der Schlüsselbund ist nicht verfügbar."
        case .rejected("invalid_credentials"): return "Zugangsdaten ungültig."
        case .rejected("reviving"): return "Claw’d ruht unter einem GIT-Grabstein"
        case .rejected("account_unavailable"): return "Benutzername oder E-Mail bereits vergeben."
        case .rejected("invalid_registration"): return "Prüfe Benutzername, E-Mail und Passwort."
        case .rejected("unauthorized"): return "Sitzung abgelaufen. Bitte erneut anmelden."
        case .rejected("rate_limited"): return "Zu viele Anfragen. Bitte kurz warten."
        case .rejected("not_found"): return "Die Runde ist nicht mehr verfügbar."
        default: return "Der Spielserver ist gerade nicht erreichbar."
        }
    }
}

protocol ArenaSessionVault {
    func read() throws -> ArenaLogin?
    func save(_ login: ArenaLogin) throws
    func clear() throws
}

struct ArenaKeychain: ArenaSessionVault {
    private var query: [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: "de.zumbyte.clawd-companion.ranked",
         kSecAttrAccount: "server-session", kSecAttrSynchronizable: false]
    }

    func read() throws -> ArenaLogin? {
        var options = query
        options[kSecReturnData] = true
        options[kSecMatchLimit] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(options as CFDictionary, &item)
        guard status != errSecItemNotFound else { return nil }
        guard status == errSecSuccess, let bytes = item as? Data,
              let session = try? JSONDecoder().decode(ArenaLogin.self, from: bytes) else {
            throw ArenaAccountFailure.keychain
        }
        return session
    }

    func save(_ login: ArenaLogin) throws {
        let updates: [CFString: Any] = [kSecValueData: try JSONEncoder().encode(login),
                                         kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, updates as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(updates) { _, value in value } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw ArenaAccountFailure.keychain }
    }

    func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw ArenaAccountFailure.keychain }
    }
}

private final class ArenaRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

private actor ArenaEndpointResolver {
    private let host: String
    private let discover: Bool
    private let session: URLSession
    private var origin: URL?
    private var pending: Task<URL, Error>?

    init(host: String, configured: String?, allowsDiscovery: Bool, session: URLSession) {
        self.host = host
        origin = configured.flatMap { Self.validatedOrigin($0, host: host) }
        discover = allowsDiscovery
        self.session = session
    }

    func resolve() async throws -> URL {
        if let origin { return origin }
        guard discover else { throw ArenaAccountFailure.unavailable }
        if let pending { return try await pending.value }
        let task = Task { [host, session] in try await Self.fetch(host: host, session: session) }
        pending = task
        defer { pending = nil }
        let result = try await task.value
        origin = result
        return result
    }

    private struct Discovery: Decodable { let arena: String }

    private static func fetch(host: String, session: URLSession) async throws -> URL {
        guard let url = URL(string: "https://" + host + "/.well-known/clawd-companion.json") else {
            throw ArenaAccountFailure.unavailable
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 6)
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (bytes, raw) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        guard let response = raw as? HTTPURLResponse, response.statusCode == 200, response.url == url,
              response.mimeType == "application/json", response.expectedContentLength <= 2048 else {
            throw ArenaAccountFailure.unavailable
        }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 2048 else { throw ArenaAccountFailure.unavailable }
            data.append(byte)
        }
        guard let info = try? JSONDecoder().decode(Discovery.self, from: data),
              let endpoint = validatedOrigin(info.arena, host: host) else { throw ArenaAccountFailure.unavailable }
        return endpoint
    }

    private static func validatedOrigin(_ input: String, host: String) -> URL? {
        let raw = input.trimmingCharacters(in: CharacterSet(charactersIn: " \t\r\n"))
        let prefix = "https://" + host
        guard raw.utf8.count <= 2048, raw.utf8.allSatisfy({ (33...126).contains($0) }),
              raw.lowercased().hasPrefix(prefix) else { return nil }
        let suffix = String(raw.dropFirst(prefix.count))
        guard suffix.isEmpty || suffix.first == "/" else { return nil }
        var path = suffix.dropFirst().split(separator: "/", omittingEmptySubsequences: false)
        if path.last?.isEmpty == true { path.removeLast() }
        // Allow only literal unreserved URL components. Percent-encoded separators and traversal are rejected.
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~".utf8)
        guard path.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && $0.utf8.allSatisfy(allowed.contains) }) else { return nil }
        return URL(string: prefix + (path.isEmpty ? "/" : "/" + path.joined(separator: "/") + "/"))
    }

}

struct ArenaAccountClient {
    private let endpoints: ArenaEndpointResolver
    private let session: URLSession

    init() {
        let file = Bundle.main.url(forResource: "ArenaEndpoint", withExtension: "txt")
        self.init(host: "zumbyte.de", configured: file.flatMap(Self.readConfiguration),
                  allowsDiscovery: file == nil, session: Self.transport(), discoverySession: Self.transport())
    }

    /// Fixture transports exercise a reserved host. The installed app uses only the bundled/operator configuration.
    init(session: URLSession, fixtureEndpoint: String? = nil, discoverySession: URLSession? = nil) {
        self.init(host: "arena.invalid", configured: fixtureEndpoint, allowsDiscovery: fixtureEndpoint == nil,
                  session: session, discoverySession: discoverySession ?? session)
    }

    private init(host: String, configured: String?, allowsDiscovery: Bool, session: URLSession, discoverySession: URLSession) {
        endpoints = ArenaEndpointResolver(host: host, configured: configured, allowsDiscovery: allowsDiscovery, session: discoverySession)
        self.session = session
    }

    private static func readConfiguration(_ file: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        guard let bytes = try? handle.read(upToCount: 2049), bytes.count <= 2048 else { return nil }
        return String(data: bytes, encoding: .ascii)
    }

    private static func transport() -> URLSession {
        let settings = URLSessionConfiguration.ephemeral
        settings.timeoutIntervalForRequest = 8
        settings.timeoutIntervalForResource = 14
        settings.httpShouldSetCookies = false
        settings.httpCookieStorage = nil
        settings.urlCredentialStorage = nil
        settings.urlCache = nil
        return URLSession(configuration: settings, delegate: ArenaRedirectPolicy(), delegateQueue: nil)
    }

    private struct Credentials: Encodable { let username: String; let email: String?; let password: String }
    private struct Click: Encodable { let x, y: Double; let seq: Int }
    private struct Leaderboard: Decodable { let players: [ArenaOnlinePlayer] }
    private struct ErrorBody: Decodable { let error: String }
    private struct Confirmation: Decodable { let ok: Bool }

    func authenticate(name: String, email: String?, password: String) async throws -> ArenaLogin {
        let body = try JSONEncoder().encode(Credentials(username: name, email: email, password: password))
        let login: ArenaLogin = try await request(email == nil ? "login" : "register", body: body)
        guard !login.token.isEmpty, login.token.utf8.count <= 2048,
              login.token.utf8.allSatisfy({ (33...126).contains($0) }),
              !login.username.isEmpty else { throw ArenaAccountFailure.unavailable }
        return login
    }

    func me(_ token: String) async throws -> ArenaOnlinePlayer { try await request("me", token: token) }
    func leaderboard(_ token: String) async throws -> [ArenaOnlinePlayer] {
        let board: Leaderboard = try await request("leaderboard", token: token)
        return board.players
    }
    func logout(_ token: String) async throws {
        let ack: Confirmation = try await request("logout", token: token, body: Data("{}".utf8))
        guard ack.ok else { throw ArenaAccountFailure.unavailable }
    }
    func start(_ token: String) async throws -> ArenaOnlineFrame {
        try await request("runs", token: token, body: Data("{}".utf8))
    }
    func frame(_ id: String, token: String) async throws -> ArenaOnlineFrame {
        try await request(try path(for: id), token: token)
    }
    func click(_ id: String, token: String, point: CGPoint, seq: Int) async throws -> ArenaOnlineFrame {
        let body = try JSONEncoder().encode(Click(x: point.x, y: point.y, seq: seq))
        return try await request(try path(for: id) + "/click", token: token, body: body)
    }

    private func path(for id: String) throws -> String {
        guard id.utf8.count == 32, id.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) })
        else { throw ArenaAccountFailure.unavailable }
        return "runs/" + id
    }

    private func request<T: Decodable>(_ path: String, token: String? = nil, body: Data? = nil) async throws -> T {
        let origin = try await endpoints.resolve()
        var request = URLRequest(url: origin.appendingPathComponent(path), cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = body == nil ? "GET" : "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        let (data, raw) = try await session.data(for: request)
        guard let response = raw as? HTTPURLResponse, response.url == request.url,
              data.count <= 512_000, response.mimeType?.lowercased() == "application/json" else {
            throw ArenaAccountFailure.unavailable
        }
        guard (200..<300).contains(response.statusCode) else {
            if response.statusCode == 401, token != nil { throw ArenaAccountFailure.rejected("unauthorized") }
            if response.statusCode == 429 { throw ArenaAccountFailure.rejected("rate_limited") }
            let code = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error ?? "unavailable"
            throw ArenaAccountFailure.rejected(code)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
