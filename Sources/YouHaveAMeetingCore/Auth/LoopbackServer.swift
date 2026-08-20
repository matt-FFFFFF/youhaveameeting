import Foundation
import Network

/// A one-shot HTTP listener on the loopback interface, used as the OAuth
/// redirect target.
///
/// This replaces a custom URL scheme: Google's scheme is derived from the
/// client ID, which the user supplies at runtime, so it cannot be declared in
/// Info.plist at build time. A loopback redirect needs nothing in the bundle.
final class LoopbackServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.youhaveameeting.loopback")
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private var waiter: CheckedContinuation<[URLQueryItem], any Error>?
    private var delivered = false

    /// Binds an ephemeral loopback port and returns it.
    func start() async throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        // Loopback only - never expose the listener to the network.
        parameters.requiredInterfaceType = .loopback

        let listener: NWListener
        do {
            listener = try NWListener(using: parameters, on: .any)
        } catch {
            throw AuthError.listenerFailed(error.localizedDescription)
        }
        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }

        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard let port = listener.port?.rawValue else {
                        continuation.resume(throwing: AuthError.listenerFailed("no port assigned"))
                        return
                    }
                    listener.stateUpdateHandler = nil
                    continuation.resume(returning: port)
                case let .failed(error):
                    listener.stateUpdateHandler = nil
                    continuation.resume(
                        throwing: AuthError.listenerFailed(error.localizedDescription)
                    )
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    /// Resolves with the query items of the first request received.
    func waitForCallback() async throws -> [URLQueryItem] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                guard !delivered else {
                    continuation.resume(throwing: AuthError.userCancelled)
                    return
                }
                waiter = continuation
            }
        }
    }

    func stop() {
        queue.async { [self] in
            listener?.cancel()
            listener = nil
            for connection in connections {
                connection.cancel()
            }
            connections.removeAll()
            if let waiter, !delivered {
                delivered = true
                self.waiter = nil
                waiter.resume(throwing: AuthError.userCancelled)
            }
        }
    }

    // MARK: - Connection handling

    private func accept(_ connection: NWConnection) {
        queue.async { [self] in
            connections.append(connection)
        }
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 8192
        ) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            var buffer = buffer
            if let data {
                buffer.append(data)
            }

            if error != nil {
                connection.cancel()
                return
            }

            // Only the request line is needed, so stop at the end of headers.
            if let text = String(data: buffer, encoding: .utf8), text.contains("\r\n\r\n") {
                handle(requestHead: text, on: connection)
                return
            }

            if isComplete {
                connection.cancel()
                return
            }

            receive(on: connection, buffer: buffer)
        }
    }

    private func handle(requestHead: String, on connection: NWConnection) {
        let items = Self.queryItems(fromRequestHead: requestHead)
        respond(on: connection, success: items.contains { $0.name == "code" })

        guard !delivered, let waiter else { return }
        delivered = true
        self.waiter = nil
        waiter.resume(returning: items)
    }

    private func respond(on connection: NWConnection, success: Bool) {
        let message = success
            ? "Signed in. You can close this tab and go back to You Have a Meeting."
            : "Sign-in did not complete. You can close this tab and try again."
        let body = """
        <!doctype html><meta charset="utf-8">
        <title>You Have a Meeting</title>
        <body style="font: 16px -apple-system, sans-serif; padding: 3rem">\(message)</body>
        """
        let response = """
        HTTP/1.1 200 OK\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """
        connection.send(
            content: Data(response.utf8),
            completion: .contentProcessed { _ in connection.cancel() }
        )
    }

    /// Pulls the query out of an HTTP request line such as
    /// `GET /callback?code=abc&state=xyz HTTP/1.1`.
    static func queryItems(fromRequestHead head: String) -> [URLQueryItem] {
        guard let requestLine = head.split(separator: "\r\n").first else { return [] }
        let fields = requestLine.split(separator: " ")
        guard fields.count >= 2 else { return [] }
        var components = URLComponents()
        components.scheme = "http"
        components.host = "127.0.0.1"
        let target = String(fields[1])
        guard let parsed = URLComponents(string: "http://127.0.0.1\(target)") else { return [] }
        components = parsed
        return components.queryItems ?? []
    }
}
