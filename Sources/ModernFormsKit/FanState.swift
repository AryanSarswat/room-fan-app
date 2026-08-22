import Foundation

/// Which way the blades turn. "forward" is Summer / counter-clockwise on the
/// physical remote; "reverse" is Winter / clockwise.
public enum FanDirection: String, Codable, Sendable, CaseIterable {
    case forward
    case reverse

    public var toggled: FanDirection { self == .forward ? .reverse : .forward }
}

/// Ranges the receiver accepts. Taken from the remote's documented behaviour
/// (6 fan speeds, dimming down to 1%) and confirmed against the fan's own API.
public enum FanLimits {
    public static let speed = 1...6
    public static let brightness = 1...100
    public static let breezeSpeed = 1...3
}

/// A snapshot of the fan, decoded from the receiver's `queryDynamicShadowData`
/// response. Unknown or missing keys fall back to safe defaults rather than
/// failing the whole decode, because this protocol is reverse-engineered and
/// firmware revisions differ in which keys they report.
public struct FanState: Sendable, Equatable, Decodable {
    public var fanOn: Bool
    public var fanSpeed: Int
    public var direction: FanDirection
    public var lightOn: Bool
    public var brightness: Int
    /// Breeze Mode. `nil` means this receiver never reported the key, i.e. it
    /// does not support Breeze — distinct from "supported but off".
    public var breezeOn: Bool?
    public var breezeSpeed: Int

    public init(
        fanOn: Bool = false,
        fanSpeed: Int = 1,
        direction: FanDirection = .forward,
        lightOn: Bool = false,
        brightness: Int = 100,
        breezeOn: Bool? = nil,
        breezeSpeed: Int = 2
    ) {
        self.fanOn = fanOn
        self.fanSpeed = fanSpeed
        self.direction = direction
        self.lightOn = lightOn
        self.brightness = brightness
        self.breezeOn = breezeOn
        self.breezeSpeed = breezeSpeed
    }

    enum CodingKeys: String, CodingKey {
        case fanOn, fanSpeed, fanDirection, lightOn, lightBrightness, wind, windSpeed
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawDirection = try c.decodeIfPresent(String.self, forKey: .fanDirection)
        self.init(
            fanOn: try c.decodeIfPresent(Bool.self, forKey: .fanOn) ?? false,
            fanSpeed: try c.decodeIfPresent(Int.self, forKey: .fanSpeed) ?? FanLimits.speed.lowerBound,
            direction: rawDirection.flatMap(FanDirection.init(rawValue:)) ?? .forward,
            lightOn: try c.decodeIfPresent(Bool.self, forKey: .lightOn) ?? false,
            brightness: try c.decodeIfPresent(Int.self, forKey: .lightBrightness) ?? FanLimits.brightness.upperBound,
            breezeOn: try c.decodeIfPresent(Bool.self, forKey: .wind),
            breezeSpeed: try c.decodeIfPresent(Int.self, forKey: .windSpeed) ?? 2
        )
    }

    public var supportsBreeze: Bool { breezeOn != nil }
}
