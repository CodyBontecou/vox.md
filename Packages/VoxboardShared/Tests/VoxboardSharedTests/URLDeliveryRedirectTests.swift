import Network
import XCTest
@testable import VoxboardShared

final class URLDeliveryRedirectTests: XCTestCase {
    /// Real URLSession delegate path, not a mocked redirect callback. Both the
    /// original and potential redirect target are synthetic loopback endpoints.
    func testRedirectNeverForwardsPostBodyOrAuthentication() async throws {
        for status in [301, 302, 303, 307, 308] {
            let server = try URLDeliveryLoopbackServer(redirectStatus: status)
            defer { server.stop() }
            let ready = expectation(description: "Loopback listener ready")
            server.start { ready.fulfill() }
            await fulfillment(of: [ready], timeout: 3)
            let port = try XCTUnwrap(server.port)
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("URLRedirect-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: directory) }
            let sender = TranscriptURLDeliverer(receiptsDirectoryURL: directory,
                                                tokenProvider: { _ in "synthetic-token" }, logger: { _ in }, sleeper: { _ in })
            let settings = CapturePresetURLDeliverySettings(
                enabled: true, urlString: "http://127.0.0.1:\(port)/redirect", hasBearerToken: true,
                customHeaders: ["X-Signature": "synthetic-signature"], allowingInsecureLocal: true
            )
            let event = await sender.deliverCapture(id: UUID(), text: "Synthetic redirect body", date: Date(), settings: settings)
            guard case .failed(_, false) = event.result else {
                return XCTFail("HTTP \(status) must be rejected, not silently followed")
            }
            XCTAssertEqual(event.attempts, 1)
            XCTAssertEqual(server.requests.count, 1, "No request may reach the redirect target")
            XCTAssertTrue(server.requests.first?.contains("Bearer synthetic-token") == true)
            XCTAssertTrue(server.requests.first?.contains("synthetic-signature") == true)
        }
    }

    func testSameOriginAndHTTPSDowngradeRedirectsAreAlsoRefused() {
        let delegate = URLDeliveryRedirectBlocker()
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: URL(string: "https://example.invalid/original")!)
        let response = HTTPURLResponse(url: URL(string: "https://example.invalid/original")!, statusCode: 307,
                                       httpVersion: nil, headerFields: nil)!
        for target in ["https://example.invalid/new", "https://other.invalid/new", "http://example.invalid/new"] {
            var redirected = URLRequest(url: URL(string: target)!)
            redirected.setValue("Bearer synthetic-token", forHTTPHeaderField: "Authorization")
            delegate.urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: redirected) { permitted in
                XCTAssertNil(permitted)
            }
        }
        task.cancel()
    }
}

private final class URLDeliveryLoopbackServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "URLDeliveryLoopbackServer")
    private let lock = NSLock()
    private var storage: [String] = []
    private let redirectStatus: Int

    var port: UInt16? { listener.port?.rawValue }
    var requests: [String] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }

    init(redirectStatus: Int) throws {
        self.redirectStatus = redirectStatus
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(IPv4Address("127.0.0.1")!), port: .any)
        listener = try NWListener(using: parameters)
    }

    func start(ready: @escaping @Sendable () -> Void) {
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready, .failed:
                self?.listener.stateUpdateHandler = nil
                ready()
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { connection.cancel(); return }
            connection.start(queue: self.queue)
            self.receive(connection, buffered: Data())
        }
        listener.start(queue: queue)
    }

    func stop() { listener.cancel() }

    private func receive(_ connection: NWConnection, buffered: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, complete, error in
            guard let self, error == nil else { connection.cancel(); return }
            var buffer = buffered
            if let data { buffer.append(data) }
            guard buffer.count <= 64 * 1024 else { connection.cancel(); return }
            let raw = String(decoding: buffer, as: UTF8.self)
            guard let headerEnd = raw.range(of: "\r\n\r\n") else {
                if complete { connection.cancel() } else { self.receive(connection, buffered: buffer) }
                return
            }
            let header = String(raw[..<headerEnd.lowerBound])
            let length = header.components(separatedBy: "\r\n").first { $0.lowercased().hasPrefix("content-length:") }
                .flatMap { Int($0.split(separator: ":")[1].trimmingCharacters(in: .whitespaces)) } ?? 0
            let body = raw[headerEnd.upperBound...]
            if body.utf8.count < length, !complete {
                self.receive(connection, buffered: buffer)
                return
            }
            self.lock.lock()
            self.storage.append(raw)
            self.lock.unlock()
            let redirect = raw.hasPrefix("POST /redirect")
            let status = redirect ? "\(self.redirectStatus) Redirect" : "200 OK"
            // localhost differs from 127.0.0.1: this is a cross-origin redirect.
            let location = redirect ? "Location: http://localhost:\(self.port!)/target\r\n" : ""
            let response = "HTTP/1.1 \(status)\r\n\(location)Content-Length: 0\r\nConnection: close\r\n\r\n"
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
        }
    }
}
