import Foundation

#if canImport(Darwin)
import Darwin
#endif

/// Finds fans by probing every address on the phone's own /24 subnet.
///
/// Modern Forms receivers are not advertised over Bonjour, and the vendor app
/// finds them through the cloud, so a sweep of the local subnet is the only
/// purely-local option. A fan is anything that answers `/mf` with valid state.
public enum FanDiscovery {
    public struct Fan: Sendable, Equatable, Identifiable {
        public let host: String
        public let state: FanState
        public var id: String { host }
    }

    /// Probing all 254 addresses at once exhausts sockets on a busy network and
    /// silently loses answers, so they go out in waves.
    private static let maxConcurrentProbes = 48

    public static func scan(
        subnetOf address: String? = localIPv4(),
        timeout: TimeInterval = 2
    ) async -> [Fan] {
        guard let address, let prefix = subnetPrefix(of: address) else { return [] }
        let octets = Array(1...254)

        return await withTaskGroup(of: Fan?.self) { group in
            var next = 0
            while next < min(maxConcurrentProbes, octets.count) {
                let host = "\(prefix).\(octets[next])"
                group.addTask { await probe(host, timeout: timeout) }
                next += 1
            }

            var found: [Fan] = []
            while let result = await group.next() {
                if let fan = result { found.append(fan) }
                if next < octets.count {
                    let host = "\(prefix).\(octets[next])"
                    group.addTask { await probe(host, timeout: timeout) }
                    next += 1
                }
            }
            return found.sorted { $0.host.compare($1.host, options: .numeric) == .orderedAscending }
        }
    }

    private static func probe(_ host: String, timeout: TimeInterval) async -> Fan? {
        guard let client = ModernFormsClient(host: host, timeout: timeout),
              let state = try? await client.status() else { return nil }
        return Fan(host: host, state: state)
    }

    static func subnetPrefix(of address: String) -> String? {
        let octets = address.split(separator: ".")
        guard octets.count == 4 else { return nil }
        return octets.dropLast().joined(separator: ".")
    }

    /// The device's own IPv4 address on Wi-Fi, or `nil` when it has none.
    public static func localIPv4() -> String? {
        #if canImport(Darwin)
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let head else { return nil }
        defer { freeifaddrs(head) }

        for interface in sequence(first: head, next: { $0.pointee.ifa_next }) {
            let flags = Int32(interface.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0,
                  let addr = interface.pointee.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_INET),
                  // en0 is Wi-Fi on iOS and on Apple silicon Macs.
                  String(cString: interface.pointee.ifa_name) == "en0"
            else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(
                addr, socklen_t(addr.pointee.sa_len),
                &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST
            ) == 0 else { continue }
            return String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        }
        #endif
        return nil
    }
}
