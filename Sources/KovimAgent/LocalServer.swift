import Foundation
import Network

@MainActor
final class LocalServer {
    private let config: KovimConfig
    private let inputSourceManager: InputSourceManager
    private let logger: Logger
    private var listener: NWListener?

    init(config: KovimConfig, inputSourceManager: InputSourceManager, logger: Logger) {
        self.config = config
        self.inputSourceManager = inputSourceManager
        self.logger = logger
    }

    func start() {
        guard config.enableLocalServer else { return }
        guard listener == nil else { return }

        do {
            let port = NWEndpoint.Port(rawValue: config.port)!
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            params.requiredLocalEndpoint = .hostPort(host: .ipv4(IPv4Address("127.0.0.1")!), port: port)
            let listener = try NWListener(using: params)
            self.listener = listener

            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.handle(connection: connection)
                }
            }
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready:
                        self?.logger.log("Local API listening on http://127.0.0.1:\(self?.config.port ?? 0)")
                    case .failed(let error):
                        self?.logger.log("Local API failed: \(error)")
                    default:
                        break
                    }
                }
            }
            listener.start(queue: .main)
        } catch {
            logger.log("Failed to start local API server: \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, _, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.logger.debug("HTTP receive error: \(error)")
                    connection.cancel()
                    return
                }
                guard let data, let request = String(data: data, encoding: .utf8) else {
                    self.respond(connection: connection, status: 400, body: ["ok": false, "error": "Invalid request"])
                    return
                }
                self.route(request: request, connection: connection)
            }
        }
    }

    private func route(request: String, connection: NWConnection) {
        let firstLine = request.split(separator: "\r\n", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        let parts = firstLine.split(separator: " ").map(String.init)
        guard parts.count >= 2 else {
            respond(connection: connection, status: 400, body: ["ok": false, "error": "Malformed request"])
            return
        }

        let method = parts[0]
        let path = parts[1].split(separator: "?", maxSplits: 1).first.map(String.init) ?? parts[1]

        do {
            switch (method, path) {
            case ("GET", "/health"):
                inputSourceManager.refresh()
                respond(connection: connection, body: stateBody(extra: ["status": "ok"]))
            case ("GET", "/ime/current"):
                inputSourceManager.refresh()
                respond(connection: connection, body: stateBody())
            case ("GET", "/ime/sources"):
                let sources = InputSourceManager.selectableInputSources().map { ["id": $0.id, "name": $0.name] }
                respond(connection: connection, body: ["ok": true, "sources": sources])
            case ("POST", "/ime/english"), ("POST", "/mode/normal"):
                try inputSourceManager.enterNormalMode()
                respond(connection: connection, body: stateBody(extra: ["mode": "normal"]))
            case ("POST", "/ime/restore"), ("POST", "/mode/insert"):
                try inputSourceManager.enterInsertMode(restoreIME: config.restorePreviousOnInsert)
                respond(connection: connection, body: stateBody(extra: ["mode": "insert"]))
            default:
                respond(connection: connection, status: 404, body: ["ok": false, "error": "Not found", "path": path])
            }
        } catch {
            logger.log("API \(method) \(path) failed: \(error)")
            respond(connection: connection, status: 500, body: ["ok": false, "error": String(describing: error)])
        }
    }

    private func stateBody(extra: [String: Any] = [:]) -> [String: Any] {
        var body: [String: Any] = [
            "ok": true,
            "currentInputSourceId": inputSourceManager.currentInputSourceId as Any,
            "previousInputSourceId": inputSourceManager.previousInputSourceId as Any,
            "englishInputSourceId": inputSourceManager.englishInputSourceId
        ]
        for (key, value) in extra {
            body[key] = value
        }
        return body
    }

    private func respond(connection: NWConnection, status: Int = 200, body: [String: Any]) {
        let statusText: String
        switch status {
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
        case 404: statusText = "Not Found"
        case 500: statusText = "Internal Server Error"
        default: statusText = "OK"
        }

        let payload: Data
        do {
            payload = try JSONSerialization.data(withJSONObject: sanitizeJSON(body), options: [.prettyPrinted, .sortedKeys])
        } catch {
            payload = Data("{\"ok\":false,\"error\":\"JSON serialization failed\"}".utf8)
        }

        var headers = "HTTP/1.1 \(status) \(statusText)\r\n"
        headers += "Content-Type: application/json; charset=utf-8\r\n"
        headers += "Content-Length: \(payload.count)\r\n"
        headers += "Connection: close\r\n"
        headers += "Access-Control-Allow-Origin: *\r\n"
        headers += "\r\n"

        var response = Data(headers.utf8)
        response.append(payload)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func sanitizeJSON(_ value: Any) -> Any {
        switch value {
        case Optional<Any>.none:
            return NSNull()
        case let optional as OptionalProtocol:
            return optional.anyValue.map(sanitizeJSON) ?? NSNull()
        case let dict as [String: Any]:
            return dict.mapValues(sanitizeJSON)
        case let array as [Any]:
            return array.map(sanitizeJSON)
        default:
            return value
        }
    }
}

private protocol OptionalProtocol {
    var anyValue: Any? { get }
}

extension Optional: OptionalProtocol {
    var anyValue: Any? {
        switch self {
        case .some(let value): return value
        case .none: return nil
        }
    }
}
