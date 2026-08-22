import Foundation
import ModernFormsKit
import Observation

/// Owns the connection to one fan and the last state it reported.
///
/// Writes are optimistic: the UI moves immediately and rolls back if the fan
/// rejects the command, because a switch that lags a network round trip feels
/// broken even when the round trip is fast.
@MainActor
@Observable
final class FanController {
    private static let hostDefaultsKey = "fanHost"
    private static let pollInterval = Duration.seconds(5)

    var host: String {
        didSet {
            guard host != oldValue else { return }
            UserDefaults.standard.set(host, forKey: Self.hostDefaultsKey)
            client = Self.makeClient(host: host)
            state = nil
            errorMessage = nil
        }
    }

    private(set) var state: FanState?
    private(set) var errorMessage: String?
    private var client: ModernFormsClient?

    init() {
        host = UserDefaults.standard.string(forKey: Self.hostDefaultsKey) ?? ""
        client = Self.makeClient(host: host)
    }

    private static func makeClient(host: String) -> ModernFormsClient? {
        let address = ModernFormsClient.parse(address: host)
        return ModernFormsClient(host: address.host, port: address.port)
    }

    func refresh() async {
        await perform { try await $0.status() }
    }

    /// Applies `optimistic` locally, sends `command`, then reconciles with
    /// whatever the fan actually reports back.
    func send(_ command: FanCommand, optimistic: (inout FanState) -> Void) async {
        if state != nil { optimistic(&state!) }
        await perform { try await $0.send(command) }
    }

    /// Keeps state fresh so changes made with the physical remote show up here.
    func pollWhileVisible() async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: Self.pollInterval)
        }
    }

    private func perform(_ work: (ModernFormsClient) async throws -> FanState) async {
        guard let client else { return }
        let previous = state
        do {
            state = try await work(client)
            errorMessage = nil
        } catch {
            state = previous
            errorMessage = error.localizedDescription
        }
    }
}
