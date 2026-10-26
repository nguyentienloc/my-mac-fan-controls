import Foundation

public struct FanStatus: Codable, Equatable, Sendable {
    public var index: Int
    public var rpm: Double
    public var minRPM: Double
    public var maxRPM: Double
    public var manual: Bool

    public init(index: Int, rpm: Double, minRPM: Double, maxRPM: Double, manual: Bool) {
        self.index = index
        self.rpm = rpm
        self.minRPM = minRPM
        self.maxRPM = maxRPM
        self.manual = manual
    }

    /// 0...1 cho thanh tiến độ (0 RPM khi Apple cho quạt nghỉ cũng hiển thị 0).
    public var fraction: Double {
        guard maxRPM > minRPM else { return 0 }
        return min(max((rpm - minRPM) / (maxRPM - minRPM), 0), 1)
    }
}

/// Trạng thái daemon gửi cho app mỗi lần app hỏi.
public struct Status: Codable, Equatable, Sendable {
    public var temperature: Double?
    public var fans: [FanStatus]
    public var activePresetID: String
    public var presets: [Preset]
    public var safetyActive: Bool
    public var error: String?

    public init(temperature: Double?, fans: [FanStatus], activePresetID: String, presets: [Preset], safetyActive: Bool, error: String?) {
        self.temperature = temperature
        self.fans = fans
        self.activePresetID = activePresetID
        self.presets = presets
        self.safetyActive = safetyActive
        self.error = error
    }
}
