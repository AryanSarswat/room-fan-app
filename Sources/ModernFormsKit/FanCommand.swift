import Foundation

/// One POST body for the receiver's `/mf` endpoint.
///
/// Every field is optional and omitted when `nil`, so a single request can set
/// any combination of properties. `queryDynamicShadowData` is always sent so
/// the receiver replies with its complete state instead of an empty body.
public struct FanCommand: Encodable, Sendable, Equatable {
    public var fanOn: Bool?
    public var fanSpeed: Int?
    public var fanDirection: FanDirection?
    public var lightOn: Bool?
    public var lightBrightness: Int?
    public var wind: Bool?
    public var windSpeed: Int?

    private let queryDynamicShadowData = true

    public init(
        fanOn: Bool? = nil,
        fanSpeed: Int? = nil,
        fanDirection: FanDirection? = nil,
        lightOn: Bool? = nil,
        lightBrightness: Int? = nil,
        wind: Bool? = nil,
        windSpeed: Int? = nil
    ) {
        self.fanOn = fanOn
        self.fanSpeed = fanSpeed
        self.fanDirection = fanDirection
        self.lightOn = lightOn
        self.lightBrightness = lightBrightness
        self.wind = wind
        self.windSpeed = windSpeed
    }

    /// Ask for state without changing anything.
    public static let query = FanCommand()

    public static func fan(on: Bool) -> FanCommand { FanCommand(fanOn: on) }
    public static func light(on: Bool) -> FanCommand { FanCommand(lightOn: on) }
    public static func direction(_ direction: FanDirection) -> FanCommand {
        FanCommand(fanDirection: direction)
    }

    /// Setting a speed also powers the fan on, matching what the physical
    /// remote does when you press speed-up on a stopped fan.
    public static func speed(_ speed: Int) -> FanCommand {
        FanCommand(fanOn: true, fanSpeed: speed.clamped(to: FanLimits.speed))
    }

    /// Setting a brightness also powers the light on, for the same reason.
    public static func brightness(_ percent: Int) -> FanCommand {
        FanCommand(lightOn: true, lightBrightness: percent.clamped(to: FanLimits.brightness))
    }

    public static func breeze(on: Bool, speed: Int? = nil) -> FanCommand {
        FanCommand(wind: on, windSpeed: speed?.clamped(to: FanLimits.breezeSpeed))
    }
}

extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
