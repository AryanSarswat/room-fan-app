import Foundation
import ModernFormsKit

/// Command line probe for a Modern Forms fan. Lets you confirm the protocol
/// against real hardware from a Mac before involving the phone at all.
@main
struct MFCtl {
    static func main() async {
        var arguments = Array(CommandLine.arguments.dropFirst())
        guard let first = arguments.first else { exitWithUsage() }

        if first == "scan" {
            let fans = await FanDiscovery.scan()
            guard !fans.isEmpty else {
                print("No fans answered on \(FanDiscovery.localIPv4() ?? "this network").")
                return
            }
            for fan in fans { print("\(fan.host)  \(describe(fan.state))") }
            return
        }

        let address = ModernFormsClient.parse(address: arguments.removeFirst())
        guard let command = parse(arguments) else { exitWithUsage() }

        guard let client = ModernFormsClient(host: address.host, port: address.port) else {
            FileHandle.standardError.write(Data("Not a usable address.\n".utf8))
            exit(1)
        }

        do {
            let state = try await client.send(command)
            print(describe(state))
        } catch {
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    static func parse(_ arguments: [String]) -> FanCommand? {
        if arguments.count == 2, let value = Int(arguments[1]) {
            switch arguments[0] {
            case "speed": return .speed(value)
            case "brightness": return .brightness(value)
            default: return nil
            }
        }
        switch arguments {
        case [], ["status"]: return .query
        case ["fan", "on"]: return .fan(on: true)
        case ["fan", "off"]: return .fan(on: false)
        case ["light", "on"]: return .light(on: true)
        case ["light", "off"]: return .light(on: false)
        case ["breeze", "on"]: return .breeze(on: true)
        case ["breeze", "off"]: return .breeze(on: false)
        case ["forward"]: return .direction(.forward)
        case ["reverse"]: return .direction(.reverse)
        default: return nil
        }
    }

    static func describe(_ state: FanState) -> String {
        let breeze = state.breezeOn.map { "  breeze \($0 ? "on@\(state.breezeSpeed)" : "off")" } ?? ""
        return """
        fan \(state.fanOn ? "on" : "off") speed \(state.fanSpeed) \(state.direction.rawValue)  \
        light \(state.lightOn ? "on" : "off") \(state.brightness)%\(breeze)
        """
    }

    static func exitWithUsage() -> Never {
        print("""
        usage:
          mfctl scan
          mfctl <host> status
          mfctl <host> fan on|off
          mfctl <host> speed <1-6>
          mfctl <host> forward|reverse
          mfctl <host> light on|off
          mfctl <host> brightness <1-100>
          mfctl <host> breeze on|off
        """)
        exit(2)
    }
}
