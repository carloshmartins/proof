import Foundation
import Network

/// Minimal HTTP/1.1 server: one JSON request per connection, loopback only.
final class RunnerServer {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "proof.runner.server")
    private let handler: CommandHandler
    private let stopLock = NSLock()
    private var _shouldStop = false

    var shouldStop: Bool {
        stopLock.lock(); defer { stopLock.unlock() }
        return _shouldStop
    }

    init(port: UInt16, handler: CommandHandler) throws {
        self.handler = handler
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredInterfaceType = .loopback
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { throw RunnerError("invalid port \(port)") }
        listener = try NWListener(using: params, on: nwPort)
    }

    func start() {
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.start(queue: queue)
    }

    func stop() { listener.cancel() }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let request = HTTPRequest.parse(buffer) {
                self.respond(connection, request)
            } else if isComplete || error != nil {
                connection.cancel()
            } else {
                self.receive(connection, buffer: buffer)
            }
        }
    }

    private func respond(_ connection: NWConnection, _ request: HTTPRequest) {
        let body: Data
        switch request.path {
        case "/health":
            // The session proof gave this runner at start, so it can tell this runner from one that is still
            // shutting down on the same port.
            let health: [String: Any] = ["ok": true, "session": ProcessInfo.processInfo.environment["PROOF_SESSION"] ?? ""]
            body = (try? JSONSerialization.data(withJSONObject: health)) ?? Data(#"{"ok":true}"#.utf8)
        case "/shutdown":
            stopLock.lock(); _shouldStop = true; stopLock.unlock()
            body = Data(#"{"ok":true}"#.utf8)
        default:
            // XCUITest must run on the main thread; the test method keeps the main run loop spinning.
            body = DispatchQueue.main.sync { handler.handle(path: request.path, body: request.body) }
        }
        var response = Data("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }
}

struct HTTPRequest {
    let method: String
    let path: String
    let body: Data

    /// Returns nil until headers and the full body (per Content-Length) have arrived.
    static func parse(_ data: Data) -> HTTPRequest? {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerEnd = data.range(of: separator) else { return nil }
        let head = String(decoding: data[data.startIndex..<headerEnd.lowerBound], as: UTF8.self)
        let lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.first?.split(separator: " ") ?? []
        guard requestLine.count >= 2 else { return nil }
        var length = 0
        for line in lines.dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2, parts[0].lowercased() == "content-length" {
                length = Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }
        let bodyStart = headerEnd.upperBound
        guard data.distance(from: bodyStart, to: data.endIndex) >= length else { return nil }
        let body = data[bodyStart..<data.index(bodyStart, offsetBy: length)]
        return HTTPRequest(method: String(requestLine[0]), path: String(requestLine[1]), body: Data(body))
    }
}

struct RunnerError: Error, CustomStringConvertible {
    let description: String
    init(_ d: String) { description = d }
}
