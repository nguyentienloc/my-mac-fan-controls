import Testing
import Shared
@testable import FanCore

struct ControllerTests {
    let fans = [
        FanInfo(index: 0, minRPM: 1200, maxRPM: 5779),
        FanInfo(index: 1, minRPM: 1200, maxRPM: 6241),
    ]
    let balanced = Preset.balanced
    let autoPreset = Preset.builtIns.first { $0.id == Preset.autoID }!
    let maxPreset = Preset.builtIns.first { $0.id == Preset.maxID }!

    /// α = 1 để tắt làm mượt, giúp test dễ tính.
    func makeController() -> Controller {
        Controller(fans: fans, settings: ControllerSettings(emaAlpha: 1))
    }

    /// Một bước điều khiển, giả lập daemon ghi thành công mọi lệnh.
    @discardableResult
    func run(_ controller: Controller, _ temp: Double?, _ preset: Preset) -> ControlOutput {
        let output = controller.step(reading: temp, preset: preset)
        for (fan, command) in output.commands { controller.commit(command, fan: fan, success: true) }
        return output
    }

    @Test func autoPresetReleasesFansOnce() {
        let c = makeController()
        #expect(run(c, 60, autoPreset).commands == [0: .auto, 1: .auto])
        #expect(run(c, 60, autoPreset).commands == [:])
    }

    @Test func curveInterpolatesToPerFanRPM() {
        let c = makeController()
        #expect(run(c, 70, balanced).commands == [0: .manual(rpm: 3489.5), 1: .manual(rpm: 3720.5)])
    }

    @Test func belowFirstPointWithoutEngagingIsAuto() {
        let c = makeController()
        #expect(run(c, 50, balanced).commands == [0: .auto, 1: .auto])
    }

    @Test func hysteresisHoldsFirstPointBeforeReleasing() {
        let c = makeController()
        #expect(run(c, 55, balanced).commands == [0: .manual(rpm: 1200), 1: .manual(rpm: 1200)])
        #expect(run(c, 53, balanced).commands == [:])
        #expect(run(c, 51.9, balanced).commands == [0: .auto, 1: .auto])
    }

    @Test func rampsDownAtMost300PerTick() {
        let c = makeController()
        run(c, 85, balanced)
        #expect(run(c, 55, balanced).commands == [0: .manual(rpm: 5479), 1: .manual(rpm: 5941)])
    }

    @Test func rampsUpImmediately() {
        let c = makeController()
        run(c, 55, balanced)
        #expect(run(c, 85, balanced).commands == [0: .manual(rpm: 5779), 1: .manual(rpm: 6241)])
    }

    @Test func skipsChangesOf50RPMOrLess() {
        let c = makeController()
        run(c, 70, balanced)
        #expect(run(c, 70.2, balanced).commands == [:])
    }

    @Test func safetyForcesMaxEvenInAutoModeWithHysteresis() {
        let c = makeController()
        let hot = run(c, 96, autoPreset)
        #expect(hot.commands == [0: .manual(rpm: 5779), 1: .manual(rpm: 6241)])
        #expect(hot.safetyActive)

        let cooling = run(c, 92, autoPreset)
        #expect(cooling.safetyActive)
        #expect(cooling.commands == [:])

        let cool = run(c, 89, autoPreset)
        #expect(!cool.safetyActive)
        #expect(cool.commands == [0: .auto, 1: .auto])
    }

    @Test func smoothsWithEMA() {
        let c = Controller(fans: fans)
        #expect(c.step(reading: 60, preset: balanced).smoothedTemperature == 60)
        let second = c.step(reading: 70, preset: balanced).smoothedTemperature!
        #expect(abs(second - 63) < 1e-9)
    }

    @Test func safetyUsesRawTemperatureNotSmoothed() {
        let c = Controller(fans: fans)
        run(c, 60, balanced)
        let output = run(c, 96, balanced)
        #expect(output.smoothedTemperature! < 95)
        #expect(output.safetyActive)
        #expect(output.commands == [0: .manual(rpm: 5779), 1: .manual(rpm: 6241)])
    }

    @Test func threeReadFailuresReleaseToAuto() {
        let c = makeController()
        run(c, 70, balanced)
        let first = run(c, nil, balanced)
        #expect(first.commands == [:])
        #expect(first.error == nil)
        run(c, nil, balanced)
        let third = run(c, nil, balanced)
        #expect(third.commands == [0: .auto, 1: .auto])
        #expect(third.error == Controller.sensorErrorMessage)

        let recovered = run(c, 70, balanced)
        #expect(recovered.error == nil)
        #expect(recovered.commands == [0: .manual(rpm: 3489.5), 1: .manual(rpm: 3720.5)])
    }

    @Test func failedWritesAreRetriedThenReleaseToAuto() {
        let c = makeController()
        let first = c.step(reading: 70, preset: balanced)
        for (fan, command) in first.commands { c.commit(command, fan: fan, success: false) }

        let retry = c.step(reading: 70, preset: balanced)
        #expect(retry.commands == [0: .manual(rpm: 3489.5), 1: .manual(rpm: 3720.5)])
        #expect(retry.error == nil)
        c.commit(.manual(rpm: 3489.5), fan: 0, success: false)

        let giveUp = c.step(reading: 70, preset: balanced)
        #expect(giveUp.error == Controller.writeErrorMessage)
        #expect(giveUp.commands == [0: .auto, 1: .auto])
    }

    @Test func maxPresetRunsFullSpeed() {
        let c = makeController()
        #expect(run(c, 40, maxPreset).commands == [0: .manual(rpm: 5779), 1: .manual(rpm: 6241)])
    }

    @Test func markNeedsRewriteResendsUnchangedCommandsOnce() {
        let c = makeController()
        run(c, 70, balanced)
        c.markNeedsRewrite()
        #expect(run(c, 70, balanced).commands == [0: .manual(rpm: 3489.5), 1: .manual(rpm: 3720.5)])
        #expect(run(c, 70, balanced).commands == [:])
    }
}
