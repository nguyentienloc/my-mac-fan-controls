import Foundation
import Shared

/// Ghép SMC + cảm biến + Controller + cấu hình. Không tự lập lịch:
/// daemon gọi `tick()` mỗi 2 giây trên một queue nối tiếp.
public final class ControlLoop {
    private let fanService: FanService
    private let sensors: SensorService
    private let controller: Controller
    private let store: ConfigStore
    private let dryRun: Bool
    private let log: (String) -> Void
    public private(set) var status: Status

    public init(smc: SMCDevice, store: ConfigStore, dryRun: Bool = false,
                settings: ControllerSettings = ControllerSettings(),
                log: @escaping (String) -> Void = { print($0) }) throws {
        let fanService = FanService(smc: smc)
        let fans = try fanService.discoverFans()
        self.fanService = fanService
        self.sensors = try SensorService(smc: smc)
        self.controller = Controller(fans: fans, settings: settings)
        self.store = store
        self.dryRun = dryRun
        self.log = log
        self.status = Status(
            temperature: nil,
            fans: fans.map { FanStatus(index: $0.index, rpm: 0, minRPM: $0.minRPM, maxRPM: $0.maxRPM, manual: false) },
            activePresetID: store.config.activePresetID,
            presets: store.config.allPresets,
            safetyActive: false,
            error: nil)
        log("Tìm thấy \(fans.count) quạt, \(sensors.keys.count) cảm biến nhiệt")
    }

    /// Khởi động: trả mọi quạt về Apple trước khi bắt đầu điều khiển.
    public func start() {
        releaseAll()
    }

    /// Trả mọi quạt về Apple (khi thoát hoặc gỡ cài đặt).
    public func releaseAll() {
        for fan in controller.fans { apply(.auto, to: fan) }
    }

    public func markWake() {
        controller.markNeedsRewrite()
    }

    public func tick() {
        let reading = try? sensors.readMaxTemperature()
        let output = controller.step(reading: reading, preset: store.config.activePreset)
        for fan in controller.fans {
            if let command = output.commands[fan.index] { apply(command, to: fan) }
        }
        refreshStatus(output)
    }

    private func apply(_ command: FanCommand, to fan: FanInfo) {
        if dryRun {
            log("[dry-run] quạt \(fan.index): \(command)")
            controller.commit(command, fan: fan.index, success: true)
            return
        }
        do {
            try fanService.apply(command, to: fan)
            controller.commit(command, fan: fan.index, success: true)
        } catch {
            log("Lỗi ghi quạt \(fan.index): \(error)")
            controller.commit(command, fan: fan.index, success: false)
        }
    }

    private func refreshStatus(_ output: ControlOutput) {
        status.temperature = output.smoothedTemperature
        status.safetyActive = output.safetyActive
        status.error = output.error
        // Báo preset thực đang dùng (có fallback khi id không tồn tại), không báo id thô trong config.
        status.activePresetID = store.config.activePreset.id
        status.presets = store.config.allPresets
        status.fans = controller.fans.map { fan in
            FanStatus(index: fan.index,
                      rpm: (try? fanService.currentRPM(fan.index)) ?? 0,
                      minRPM: fan.minRPM,
                      maxRPM: fan.maxRPM,
                      manual: (try? fanService.isManual(fan.index)) ?? false)
        }
    }
}
