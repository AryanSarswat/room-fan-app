import Foundation
import Testing
@testable import ModernFormsKit

/// A response shaped like the one a Gen-3 receiver returns from `/mf`,
/// including keys this app ignores, to prove decoding tolerates extras.
private let fullResponse = Data("""
{"clientId":"ModernFormsFan_2A1B3C","fanOn":true,"fanSpeed":4,
 "fanDirection":"reverse","fanSleepTimer":0,"lightOn":true,
 "lightBrightness":37,"lightSleepTimer":0,"awayModeEnabled":false,
 "adaptiveLearning":false,"wind":false,"windSpeed":2,"decommission":false}
""".utf8)

private func encoded(_ command: FanCommand) throws -> [String: Any] {
    let data = try JSONEncoder().encode(command)
    return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

@Suite("Command encoding")
struct CommandEncodingTests {
    @Test("Every request asks for state, so a command doubles as a state refresh")
    func alwaysQueriesState() throws {
        for command in [FanCommand.query, .fan(on: true), .brightness(50)] {
            #expect(try encoded(command)["queryDynamicShadowData"] as? Bool == true)
        }
    }

    @Test("Unset properties are omitted so a command never disturbs the rest of the fan")
    func omitsUnsetProperties() throws {
        let body = try encoded(.light(on: true))
        #expect(body["lightOn"] as? Bool == true)
        #expect(body.keys.sorted() == ["lightOn", "queryDynamicShadowData"])
    }

    @Test("Speed is clamped into the six speeds the receiver accepts")
    func clampsSpeed() throws {
        #expect(try encoded(.speed(99))["fanSpeed"] as? Int == 6)
        #expect(try encoded(.speed(0))["fanSpeed"] as? Int == 1)
        #expect(try encoded(.speed(3))["fanSpeed"] as? Int == 3)
    }

    @Test("Brightness is clamped to 1...100; 0 would mean off, not dimmest")
    func clampsBrightness() throws {
        #expect(try encoded(.brightness(0))["lightBrightness"] as? Int == 1)
        #expect(try encoded(.brightness(1000))["lightBrightness"] as? Int == 100)
    }

    @Test("Choosing a speed or brightness also powers that load on, as the remote does")
    func impliesPower() throws {
        #expect(try encoded(.speed(2))["fanOn"] as? Bool == true)
        #expect(try encoded(.brightness(20))["lightOn"] as? Bool == true)
    }

    @Test("Direction is sent as the words the receiver expects")
    func directionWireFormat() throws {
        #expect(try encoded(.direction(.reverse))["fanDirection"] as? String == "reverse")
        #expect(try encoded(.direction(.forward))["fanDirection"] as? String == "forward")
    }
}

@Suite("State decoding")
struct StateDecodingTests {
    @Test("A full response maps onto the properties the UI drives")
    func decodesFullResponse() throws {
        let state = try JSONDecoder().decode(FanState.self, from: fullResponse)
        #expect(state == FanState(
            fanOn: true, fanSpeed: 4, direction: .reverse,
            lightOn: true, brightness: 37, breezeOn: false, breezeSpeed: 2
        ))
    }

    @Test("A receiver that never mentions wind is reported as not supporting Breeze")
    func absentWindMeansUnsupported() throws {
        let data = Data(#"{"fanOn":false,"fanSpeed":1,"lightOn":false}"#.utf8)
        let state = try JSONDecoder().decode(FanState.self, from: data)
        #expect(state.breezeOn == nil)
        #expect(state.supportsBreeze == false)
    }

    @Test("Breeze reported as off is supported, so the control stays visible")
    func windFalseMeansSupported() throws {
        let state = try JSONDecoder().decode(FanState.self, from: fullResponse)
        #expect(state.supportsBreeze)
    }

    @Test("A direction this app does not know falls back instead of failing the decode")
    func unknownDirectionFallsBack() throws {
        let data = Data(#"{"fanOn":true,"fanDirection":"sideways","fanSpeed":2}"#.utf8)
        let state = try JSONDecoder().decode(FanState.self, from: data)
        #expect(state.direction == .forward)
        #expect(state.fanSpeed == 2)
    }
}

@Suite("Discovery")
struct DiscoveryTests {
    @Test("An address may carry an explicit port, defaulting to 80")
    func parsesAddress() {
        #expect(ModernFormsClient.parse(address: "192.168.1.50") == ("192.168.1.50", 80))
        #expect(ModernFormsClient.parse(address: "192.168.1.50:8088") == ("192.168.1.50", 8088))
        #expect(ModernFormsClient.parse(address: "192.168.1.50:junk") == ("192.168.1.50", 80))
        // Seen while the address is still being typed.
        #expect(ModernFormsClient.parse(address: "192.168.1.50:") == ("192.168.1.50", 80))
    }

    @Test("A host that cannot form a URL yields no client instead of trapping")
    func rejectsUnusableHosts() {
        #expect(ModernFormsClient(host: "") == nil)
        #expect(ModernFormsClient(host: "192.168.1.50:") == nil)
        #expect(ModernFormsClient(host: "has space") == nil)
        #expect(ModernFormsClient(host: "192.168.1.50") != nil)
    }

    @Test("A /24 sweep targets the address's own subnet")
    func derivesSubnet() {
        #expect(FanDiscovery.subnetPrefix(of: "192.168.1.47") == "192.168.1")
        #expect(FanDiscovery.subnetPrefix(of: "10.0.0.2") == "10.0.0")
        #expect(FanDiscovery.subnetPrefix(of: "not-an-address") == nil)
    }
}
