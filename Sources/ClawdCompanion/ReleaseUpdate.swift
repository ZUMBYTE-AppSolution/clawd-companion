import Foundation
import Combine

struct ReleaseVersion: Comparable {
    let raw: String
    private let core: [Substring]
    private let prerelease: [Substring]

    init?(_ raw: String) {
        let expression = #"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?\z"#
        guard raw.utf8.count <= 100, raw.range(of: expression, options: .regularExpression) != nil else { return nil }
        let precedence = raw.split(separator: "+", maxSplits: 1)[0].split(separator: "-", maxSplits: 1)
        core = precedence[0].split(separator: ".")
        prerelease = precedence.count > 1 ? precedence[1].split(separator: ".") : []
        guard !prerelease.contains(where: { Self.numeric($0) && $0.count > 1 && $0.first == "0" }) else { return nil }
        self.raw = raw
    }

    private static func numeric(_ text: Substring) -> Bool { text.utf8.allSatisfy { (48...57).contains($0) } }
    private static func numberLess(_ a: Substring, _ b: Substring) -> Bool {
        a.count == b.count ? a < b : a.count < b.count
    }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.core == rhs.core && lhs.prerelease == rhs.prerelease }
    static func < (lhs: Self, rhs: Self) -> Bool {
        for (a, b) in zip(lhs.core, rhs.core) where a != b { return numberLess(a, b) }
        if lhs.prerelease.isEmpty != rhs.prerelease.isEmpty { return !lhs.prerelease.isEmpty }
        for (a, b) in zip(lhs.prerelease, rhs.prerelease) where a != b {
            let an = numeric(a), bn = numeric(b)
            if an != bn { return an }
            return an ? numberLess(a, b) : a < b
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }
}

struct CompanionRelease {
    static let repository = URL(string: "https://github.com/ZUMBYTE-AppSolution/clawd-companion")!
    static let manifestURL = repository.appendingPathComponent("releases/latest/download/clawd-update.json")
    static let limit = 768 * 1024
    static let installed = ReleaseVersion(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") ?? ReleaseVersion("0.7.1")!
    let version: ReleaseVersion
    let notes: String
    private let translations: [String: String]
    let macPackage: String?
    var page: URL { Self.repository.appendingPathComponent("releases/tag/v" + version.raw) }
    var download: URL? {
        macPackage.map { Self.repository.appendingPathComponent("releases/download/v" + version.raw).appendingPathComponent($0) }
    }

    func localizedNotes(_ code: String) -> String {
        let language = code.replacingOccurrences(of: "_", with: "-").lowercased()
        return translations[language] ?? translations[language.components(separatedBy: "-")[0]] ?? notes
    }

    init(data: Data) throws {
        struct Manifest: Decodable {
            let schema: Int, version: String, tag: String, notes: String, assets: [String]
            let notesByLanguage: [String: String]?
        }
        guard data.count <= Self.limit else { throw URLError(.dataLengthExceedsMaximum) }
        let payload = try JSONDecoder().decode(Manifest.self, from: data)
        guard payload.schema == 1, let parsed = ReleaseVersion(payload.version), payload.tag == "v" + parsed.raw,
              !payload.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              payload.notes.utf8.count <= 65_536, (1...64).contains(payload.assets.count) else {
            throw URLError(.cannotParseResponse)
        }
        version = parsed
        notes = payload.notes
        var localized: [String: String] = [:]
        guard (payload.notesByLanguage?.count ?? 0) <= 24 else { throw URLError(.cannotParseResponse) }
        for (language, body) in payload.notesByLanguage ?? [:] {
            guard language.range(of: #"^[a-z]{2,3}(-[a-zA-Z0-9]{2,8})*\z"#, options: .regularExpression) != nil,
                  !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, body.utf8.count <= 65_536 else {
                throw URLError(.cannotParseResponse)
            }
            localized[language.lowercased()] = body
        }
        translations = localized
        macPackage = ["pkg", "zip"].map { "Clawd-Companion-\(parsed.raw)-macOS-universal.\($0)" }
            .first { payload.assets.contains($0) }
    }

    static func trustedMetadataURL(_ url: URL?) -> Bool {
        guard let url, url.scheme == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443, let host = url.host?.lowercased() else { return false }
        if host == "github.com" { return url.path.lowercased().hasPrefix("/zumbyte-appsolution/clawd-companion/releases/") }
        return ["release-assets.githubusercontent.com", "objects.githubusercontent.com", "github-releases.githubusercontent.com"].contains(host)
    }

    private final class Redirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(CompanionRelease.trustedMetadataURL(request.url) ? request : nil)
        }
    }

    static func latest() async throws -> Self {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 20
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: manifestURL)
        request.setValue("Clawd-Companion/" + installed.raw, forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await session.bytes(for: request, delegate: Redirects())
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              trustedMetadataURL(response.url), response.expectedContentLength <= limit else { throw URLError(.badServerResponse) }
        var data = Data()
        for try await byte in bytes {
            guard data.count < limit else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        return try Self(data: data)
    }
}

@MainActor final class ReleaseUpdateCenter: ObservableObject {
    enum Status { case idle, checking, current, available, failed }
    @Published private(set) var status: Status = .idle
    @Published private(set) var release: CompanionRelease?
    var onAvailable: ((String) -> Void)?
    let installed: ReleaseVersion
    private let defaults: UserDefaults
    private let fetch: () async throws -> CompanionRelease
    private var inFlight: Task<Void, Never>?
    private var timer: Timer?

    init(defaults: UserDefaults, installed: ReleaseVersion = CompanionRelease.installed,
         fetch: @escaping () async throws -> CompanionRelease = { try await CompanionRelease.latest() }) {
        self.defaults = defaults
        self.installed = installed
        self.fetch = fetch
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.check() }
        }
        check()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        inFlight?.cancel()
        inFlight = nil
        if status == .checking { status = .idle }
    }

    @discardableResult func check() -> Task<Void, Never>? {
        if let inFlight { return inFlight }
        status = .checking
        let task = Task { [weak self, fetch] in
            do {
                let next = try await fetch()
                guard let self, !Task.isCancelled else { return }
                release = next
                status = next.version > installed ? .available : .current
                if status == .available, defaults.string(forKey: "lastUpdateNotice") != next.version.raw {
                    defaults.set(next.version.raw, forKey: "lastUpdateNotice")
                    onAvailable?(next.version.raw)
                }
            } catch {
                guard !Task.isCancelled else { return }
                self?.status = .failed
            }
            self?.inFlight = nil
        }
        inFlight = task
        return task
    }
}
