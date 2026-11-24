import Foundation
import Network

/// A browser worker publishes a small, authenticated vocabulary on IPv4 loopback.
final class BrowserBridge {
    struct UsageWindow: Equatable {
        let kind: String
        let remainingPercent: Int
        let resetAt: Date?
        let resetLabel: String?
        var resetApproximate: Bool? = nil
    }

    enum Event: Equatable {
        case activity(String)
        case approval(sourceID: String, waiting: Bool)
        case usage(Date, [UsageWindow])
        case notice(title: String, message: String, kind: String)
    }

    let token: String
    private let queue = DispatchQueue(label: "de.zumbyte.clawd.browser")
    private var listener: NWListener?
    private var clients: [ObjectIdentifier: BrowserClient] = [:]

    init(defaults: UserDefaults = .standard) {
        let key = "ClawdBrowserPairingTokenV1"
        if let saved = defaults.string(forKey: key), saved.utf8.count == 64,
           saved.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) {
            token = saved
        } else {
            var random = SystemRandomNumberGenerator()
            token = (0..<32).map { _ in String(format: "%02x", UInt8.random(in: 0...255, using: &random)) }.joined()
            defaults.set(token, forKey: key)
        }
    }

    func start(onEvent: @escaping (Event) -> Void, onStatus: @escaping (String?) -> Void) {
        queue.async { [self] in
            shutdown()
            let port = NWEndpoint.Port(rawValue: 49217)!
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: port)
            do {
                let server = try NWListener(using: parameters)
                listener = server
                server.stateUpdateHandler = { [weak self, weak server] state in
                    guard let self, let server, self.listener === server else { return }
                    switch state {
                    case .ready:
                        guard server.port == port else {
                            self.shutdown()
                            DispatchQueue.main.async { onStatus("Der Browser-Port 49217 konnte nicht gebunden werden.") }
                            return
                        }
                        DispatchQueue.main.async { onStatus(nil) }
                    case .waiting(let error):
                        DispatchQueue.main.async { onStatus(L("Die Browser-Verbindung wartet auf den lokalen Anschluss ({0}).", error.localizedDescription)) }
                    case .failed(let error):
                        self.shutdown()
                        DispatchQueue.main.async {
                            onStatus(L("Die lokale Browser-Verbindung auf Port 49217 ist nicht verfügbar ({0}).", error.localizedDescription))
                        }
                    default:
                        break
                    }
                }
                server.newConnectionHandler = { [weak self, weak server] connection in
                    guard let self, let server, self.listener === server, self.clients.count < 12,
                          case let .hostPort(host, _) = connection.endpoint,
                          case let .ipv4(ip) = host, ip.rawValue.first == 127 else {
                        connection.cancel()
                        return
                    }
                    let id = ObjectIdentifier(connection)
                    let client = BrowserClient(connection, token: self.token, queue: self.queue, onEvent: onEvent) { [weak self] in
                        self?.clients.removeValue(forKey: id)
                    }
                    self.clients[id] = client
                    client.start()
                }
                server.start(queue: queue)
            } catch {
                DispatchQueue.main.async {
                    onStatus(L("Die lokale Browser-Verbindung konnte nicht gestartet werden ({0}).", error.localizedDescription))
                }
            }
        }
    }

    func stop() { queue.async { [self] in shutdown() } }

    private func shutdown() {
        listener?.cancel()
        listener = nil
        let active = Array(clients.values)
        for client in active { client.finish() }
        clients.removeAll()
    }
}

private final class BrowserClient {
    let connection: NWConnection
    let token: String
    let queue: DispatchQueue
    let onEvent: (BrowserBridge.Event) -> Void
    let onClose: () -> Void
    var buffer = Data()
    var deadline: DispatchWorkItem?
    var isFinished = false

    init(_ connection: NWConnection, token: String, queue: DispatchQueue,
         onEvent: @escaping (BrowserBridge.Event) -> Void, onClose: @escaping () -> Void) {
        self.connection = connection
        self.token = token
        self.queue = queue
        self.onEvent = onEvent
        self.onClose = onClose
    }

    func start() {
        let timeout = DispatchWorkItem { [weak self] in self?.finish() }
        deadline = timeout
        queue.asyncAfter(deadline: .now() + 5, execute: timeout)
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: self?.finish()
            default: break
            }
        }
        connection.start(queue: queue)
        receive()
    }

    func finish() {
        guard !isFinished else { return }
        isFinished = true
        deadline?.cancel()
        deadline = nil
        connection.cancel()
        onClose()
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] chunk, _, ended, error in
            guard let self, !self.isFinished else { return }
            if let chunk { self.buffer.append(chunk) }
            switch BrowserRequest.parse(self.buffer, token: self.token) {
            case .event(let event):
                DispatchQueue.main.async { self.onEvent(event) }
                self.respond(200)
            case .reject(let code):
                self.respond(code)
            case .incomplete:
                if ended || error != nil { self.finish() } else { self.receive() }
            }
        }
    }

    private func respond(_ code: Int) {
        let reason = [200: "OK", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden",
                      404: "Not Found", 405: "Method Not Allowed", 413: "Content Too Large",
                      415: "Unsupported Media Type"][code] ?? "Bad Request"
        let body = code == 200 ? "{\"ok\":true}" : "{\"ok\":false}"
        let message = "HTTP/1.1 \(code) \(reason)\r\nContent-Type: application/json\r\nCache-Control: no-store\r\nConnection: close\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
        connection.send(content: Data(message.utf8), completion: .contentProcessed { [weak self] _ in self?.finish() })
    }
}

enum BrowserRequest {
    enum Result: Equatable {
        case incomplete
        case reject(Int)
        case event(BrowserBridge.Event)
    }

    private static let delimiter = Data([13, 10, 13, 10])
    private static let maxHeader = 8192
    private static let maxBody = 4096

    static func parse(_ bytes: Data, token: String) -> Result {
        guard bytes.count <= maxHeader + maxBody else { return .reject(413) }
        guard let end = bytes.range(of: delimiter) else {
            return bytes.count > maxHeader ? .reject(413) : .incomplete
        }
        guard end.upperBound <= maxHeader else { return .reject(413) }
        guard let header = String(data: bytes[..<end.lowerBound], encoding: .ascii) else { return .reject(400) }
        let lines = header.components(separatedBy: "\r\n")
        let first = lines[0].split(separator: " ", omittingEmptySubsequences: false)
        guard first.count == 3, first[2] == "HTTP/1.1" else { return .reject(400) }
        guard first[0] == "POST" else { return .reject(405) }
        guard first[1] == "/v1/events" else { return .reject(404) }
        var fields: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let split = line.firstIndex(of: ":") else { return .reject(400) }
            let name = line[..<split].lowercased()
            guard !name.isEmpty, name.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }),
                  fields[name] == nil else { return .reject(400) }
            let value = line[line.index(after: split)...].trimmingCharacters(in: .whitespaces)
            guard value.utf8.allSatisfy({ $0 >= 32 && $0 < 127 }) else { return .reject(400) }
            fields[name] = value
        }
        guard fields["host"] == "127.0.0.1:49217" else { return .reject(403) }
        if let origin = fields["origin"] {
            let prefix = "chrome-extension://"
            let id = origin.dropFirst(prefix.count)
            guard origin.hasPrefix(prefix), id.utf8.count == 32, id.utf8.allSatisfy({ (97...112).contains($0) }) else {
                return .reject(403)
            }
        }
        guard let auth = fields["authorization"], matches(auth, "Bearer " + token) else { return .reject(401) }
        let mediaType = fields["content-type"]?.components(separatedBy: ";").first?.trimmingCharacters(in: .whitespaces).lowercased()
        guard mediaType == "application/json" else { return .reject(415) }
        guard fields["transfer-encoding"] == nil, let length = fields["content-length"], !length.isEmpty,
              length.utf8.allSatisfy({ (48...57).contains($0) }), let count = Int(length), count > 0 else { return .reject(400) }
        guard count <= maxBody else { return .reject(413) }
        let size = bytes.count - end.upperBound
        guard size >= count else { return .incomplete }
        guard size == count else { return .reject(400) }
        guard let event = decode(Data(bytes.suffix(count))) else { return .reject(400) }
        return .event(event)
    }

    private static func matches(_ left: String, _ right: String) -> Bool {
        guard left.utf8.count == right.utf8.count else { return false }
        var difference: UInt8 = 0
        for (a, b) in zip(left.utf8, right.utf8) { difference |= a ^ b }
        return difference == 0
    }

    private struct IncomingEvent: Decodable {
        var type: String
        var state: String?
        var sourceID: String?
        var waiting: Bool?
        var observedAt: String?
        var windows: [Window]?
        var title: String?
        var message: String?
        var kind: String?
        struct Window: Decodable {
            var kind: String
            var remainingPercent: Int
            var resetAt: String?
            var resetLabel: String?
            var resetApproximate: Bool?
        }
    }

    private static func decode(_ data: Data) -> BrowserBridge.Event? {
        guard let event = try? JSONDecoder().decode(IncomingEvent.self, from: data) else { return nil }
        switch event.type {
        case "approval":
            guard let id = event.sourceID, let uuid = UUID(uuidString: id),
                  id == uuid.uuidString.lowercased(), uuid.uuid.6 >> 4 == 4,
                  uuid.uuid.8 >> 6 == 2, let waiting = event.waiting else { return nil }
            return .approval(sourceID: id, waiting: waiting)
        case "activity":
            guard let state = event.state, ["working", "thinking", "searching", "planning", "reading", "executing", "drawing",
                                          "done", "idle", "connected"].contains(state) else { return nil }
            return .activity(state)
        case "notice":
            guard let kind = event.kind, ["info", "success", "warning", "error", "attention"].contains(kind),
                  let title = noticeText(event.title, limit: 65),
                  let message = noticeText(event.message, limit: 220) else { return nil }
            return .notice(title: title, message: message, kind: kind)
        case "usage":
            guard let time = event.observedAt, let observedAt = instant(time),
                  observedAt.timeIntervalSinceNow <= 300, let items = event.windows,
                  (1...2).contains(items.count), Set(items.map(\.kind)).count == items.count else { return nil }
            var windows: [BrowserBridge.UsageWindow] = []
            for item in items {
                guard ["session", "weekly"].contains(item.kind), (0...100).contains(item.remainingPercent) else { return nil }
                let reset = item.resetAt.flatMap(instant)
                if item.resetAt != nil && reset == nil { return nil }
                if let label = item.resetLabel, label.count > 100 || label.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) { return nil }
                windows.append(.init(kind: item.kind, remainingPercent: item.remainingPercent, resetAt: reset,
                                     resetLabel: item.resetLabel, resetApproximate: item.resetApproximate))
            }
            return .usage(observedAt, windows)
        default:
            return nil
        }
    }

    private static func noticeText(_ input: String?, limit: Int) -> String? {
        guard let input else { return nil }
        let line = input.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !line.isEmpty, line.count <= limit else { return nil }
        // Keep emoji joiners and accents. Exclude terminal and direction-changing controls.
        let unsafe = line.unicodeScalars.contains { scalar in
            scalar.value < 0x20 || (0x7F...0x9F).contains(scalar.value)
                || (0x202A...0x202E).contains(scalar.value) || (0x2066...0x2069).contains(scalar.value)
        }
        return unsafe ? nil : line
    }

    private static func instant(_ text: String) -> Date? {
        let format = ISO8601DateFormatter()
        if let date = format.date(from: text) { return date }
        format.formatOptions.insert(.withFractionalSeconds)
        return format.date(from: text)
    }
}
