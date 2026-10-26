import Foundation
import Shared

public struct ControllerSettings: Sendable {
    public var emaAlpha: Double
    public var safetyOn: Double
    public var safetyOff: Double
    public var autoHysteresis: Double
    public var maxDecreasePerTick: Double
    public var writeThreshold: Double
    public var maxConsecutiveFailures: Int

    public init(emaAlpha: Double = 0.3, safetyOn: Double = 95, safetyOff: Double = 90, autoHysteresis: Double = 3,
                maxDecreasePerTick: Double = 300, writeThreshold: Double = 50, maxConsecutiveFailures: Int = 3) {
        self.emaAlpha = emaAlpha
        self.safetyOn = safetyOn
        self.safetyOff = safetyOff
        self.autoHysteresis = autoHysteresis
        self.maxDecreasePerTick = maxDecreasePerTick
        self.writeThreshold = writeThreshold
        self.maxConsecutiveFailures = maxConsecutiveFailures
    }
}

public struct ControlOutput: Equatable {
    /// Chỉ gồm các quạt cần ghi ở chu kỳ này.
    public var commands: [Int: FanCommand]
    public var smoothedTemperature: Double?
    public var safetyActive: Bool
    public var error: String?
}

/// Máy trạng thái thuần: nhận nhiệt độ + chế độ, trả về lệnh cho từng quạt. Không làm I/O.
public final class Controller {
    public static let sensorErrorMessage = "Không đọc được cảm biến nhiệt độ"
    public static let writeErrorMessage = "Không ghi được tốc độ quạt"

    public let fans: [FanInfo]
    private let settings: ControllerSettings
    private var smoothed: Double?
    private var safetyActive = false
    private var curveEngaged = false
    private var readFailures = 0
    /// Đếm lỗi ghi liên tiếp theo từng quạt.
    private var writeFailures: [Int: Int] = [:]
    /// Đã bỏ cuộc ghi: giữ nguyên (latch) cho tới khi người dùng đổi chế độ.
    private var writeGaveUp = false
    private var gaveUpPresetID: String?
    private var lastWritten: [Int: FanCommand] = [:]
    private var forceRewrite = false

    public init(fans: [FanInfo], settings: ControllerSettings = ControllerSettings()) {
        self.fans = fans
        self.settings = settings
    }

    /// `reading == nil` hoặc không hữu hạn (NaN, vô cực) nghĩa là đọc cảm biến lỗi.
    public func step(reading: Double?, preset: Preset) -> ControlOutput {
        updateWriteGiveUp(preset: preset)

        var desired: [Int: FanCommand]
        var error: String?

        if let raw = reading, raw.isFinite {
            readFailures = 0
            let temp = smoothed.map { settings.emaAlpha * raw + (1 - settings.emaAlpha) * $0 } ?? raw
            smoothed = temp
            // Ngưỡng an toàn dùng giá trị thô để phản ứng ngay
            if raw >= settings.safetyOn {
                safetyActive = true
            } else if raw < settings.safetyOff {
                safetyActive = false
            }
            desired = desiredCommands(preset: preset, temp: temp)
        } else {
            readFailures += 1
            if readFailures < settings.maxConsecutiveFailures {
                return ControlOutput(commands: [:], smoothedTemperature: smoothed,
                                     safetyActive: safetyActive && !writeGaveUp,
                                     error: writeGaveUp ? Self.writeErrorMessage : nil)
            }
            error = Self.sensorErrorMessage
            safetyActive = false
            curveEngaged = false
            // Bỏ dữ liệu cũ để lần đọc tốt tiếp theo bắt đầu lại, không trộn với giá trị đã cũ
            smoothed = nil
            desired = allAuto()
        }

        if writeGaveUp {
            error = Self.writeErrorMessage
            curveEngaged = false
            desired = allAuto()
        }

        let commands = desired.filter { needsWrite($0.value, previous: lastWritten[$0.key]) }
        forceRewrite = false
        // Bỏ cuộc ghi được ưu tiên hơn an toàn: không ghi được thì không thể ép quạt tối đa,
        // firmware Apple có bảo vệ nhiệt riêng. Trạng thái an toàn nội bộ vẫn cập nhật theo nhiệt độ
        // để đúng khi hết bỏ cuộc; ở đây báo false vì ta không ép quạt tối đa.
        return ControlOutput(commands: commands, smoothedTemperature: smoothed,
                             safetyActive: safetyActive && !writeGaveUp, error: error)
    }

    /// Bên gọi báo kết quả ghi từng lệnh. Ghi lỗi thì lần sau ghi lại.
    public func commit(_ command: FanCommand, fan: Int, success: Bool) {
        if success {
            lastWritten[fan] = command
            writeFailures[fan] = 0
        } else {
            lastWritten[fan] = nil
            writeFailures[fan, default: 0] += 1
        }
    }

    /// Sau khi máy thức dậy SMC có thể đã reset: chu kỳ sau ghi lại toàn bộ.
    public func markNeedsRewrite() {
        forceRewrite = true
    }

    /// Bỏ cuộc khi BẤT KỲ quạt nào lỗi ghi liên tiếp đủ ngưỡng. Chỉ thoát khi người dùng đổi chế độ.
    private func updateWriteGiveUp(preset: Preset) {
        if writeGaveUp, preset.id != gaveUpPresetID {
            writeGaveUp = false
            gaveUpPresetID = nil
            writeFailures = [:]
        }
        if !writeGaveUp, writeFailures.values.contains(where: { $0 >= settings.maxConsecutiveFailures }) {
            writeGaveUp = true
            gaveUpPresetID = preset.id
        }
    }

    private func desiredCommands(preset: Preset, temp: Double) -> [Int: FanCommand] {
        if safetyActive { return percentCommands(100) }
        switch preset.kind {
        case .auto:
            curveEngaged = false
            return allAuto()
        case .max:
            curveEngaged = false
            return percentCommands(100)
        case .curve:
            if let percent = preset.curve.percent(at: temp) {
                curveEngaged = true
                return percentCommands(percent)
            }
            // Dưới điểm đầu: chỉ trả về Apple khi đã thấp hơn điểm đầu đủ hysteresis
            if curveEngaged, let first = preset.curve.points.first, temp >= first.temp - settings.autoHysteresis {
                return percentCommands(first.percent)
            }
            curveEngaged = false
            return allAuto()
        }
    }

    /// Tăng ngay, giảm tối đa `maxDecreasePerTick` mỗi chu kỳ so với lần ghi trước.
    private func percentCommands(_ percent: Double) -> [Int: FanCommand] {
        Dictionary(uniqueKeysWithValues: fans.map { fan in
            var rpm = fan.rpm(forPercent: percent)
            if case .manual(let previous)? = lastWritten[fan.index], rpm < previous {
                rpm = max(rpm, previous - settings.maxDecreasePerTick)
            }
            return (fan.index, FanCommand.manual(rpm: rpm))
        })
    }

    private func allAuto() -> [Int: FanCommand] {
        Dictionary(uniqueKeysWithValues: fans.map { ($0.index, FanCommand.auto) })
    }

    private func needsWrite(_ command: FanCommand, previous: FanCommand?) -> Bool {
        if forceRewrite { return true }
        switch (previous, command) {
        case (nil, _):
            return true
        case (.auto?, .auto):
            return false
        case let (.manual(old)?, .manual(new)):
            return abs(new - old) > settings.writeThreshold
        default:
            return true
        }
    }
}
