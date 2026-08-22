import Foundation

/// Talks to a single Modern Forms fan receiver over its local HTTP API.
///
/// The receiver exposes one endpoint, `POST http://<host>/mf`, that takes a
/// JSON object of commands and answers with the fan's full state.
public actor ModernFormsClient {
    public enum Failure: Error, LocalizedError {
        case http(status: Int)
        case transport(any Error)
        case malformedResponse(any Error)

        public var errorDescription: String? {
            switch self {
            case .http(let status): "Fan returned HTTP \(status)."
            case .transport(let error): "Could not reach the fan: \(error.localizedDescription)"
            case .malformedResponse: "The fan sent a response this app could not read."
            }
        }
    }

    public let host: String
    private let endpoint: URL
    private let session: URLSession

    /// Fails when `host` is not something a URL can address, rather than
    /// trapping — callers hand this half-typed input.
    public init?(host: String, port: Int = 80, timeout: TimeInterval = 5) {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = port == 80 ? nil : port
        components.path = "/mf"
        guard !host.isEmpty, let url = components.url else { return nil }
        self.host = host
        self.endpoint = url

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.waitsForConnectivity = false
        self.session = URLSession(configuration: configuration)
    }

    /// Splits "192.168.1.50" or "192.168.1.50:8088" into its parts, so an
    /// address can be typed in one field and pointed at a non-standard port.
    public static func parse(address: String) -> (host: String, port: Int) {
        let trimmed = address.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return (trimmed, 80) }
        // A bare or unparseable port means the host was typed without one.
        return (String(parts[0]), Int(parts[1]) ?? 80)
    }

    public func status() async throws -> FanState {
        try await send(.query)
    }

    @discardableResult
    public func send(_ command: FanCommand) async throws -> FanState {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(command)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw Failure.transport(error)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw Failure.http(status: http.statusCode)
        }

        do {
            return try JSONDecoder().decode(FanState.self, from: data)
        } catch {
            throw Failure.malformedResponse(error)
        }
    }
}
