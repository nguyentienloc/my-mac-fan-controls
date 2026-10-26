import Foundation
import Testing
@testable import Shared

struct ConfigTests {
    func customPreset(id: String = "c1", name: String = "Chơi game") -> Preset {
        Preset(id: id, name: name, kind: .curve, curve: FanCurve(points: [
            CurvePoint(temp: 50, percent: 10), CurvePoint(temp: 80, percent: 100),
        ]))
    }

    @Test func builtInsHaveExpectedIDsAndNames() {
        #expect(Preset.builtIns.map(\.id) == ["auto", "silent", "balanced", "performance", "max"])
        #expect(Preset.builtIns.map(\.name) == ["Apple tự động", "Êm", "Cân bằng", "Hiệu năng", "Tối đa"])
        #expect(Preset.builtIns.allSatisfy { $0.isBuiltIn })
    }

    @Test func builtInCurvesAreValid() {
        for preset in Preset.builtIns where preset.kind == .curve {
            #expect(preset.curve.validate() == nil, "\(preset.id)")
        }
    }

    @Test func defaultConfigUsesBalanced() {
        #expect(Config.default.activePreset.id == Preset.balancedID)
    }

    @Test func activePresetFallsBackToBalancedForUnknownID() {
        let config = Config(activePresetID: "missing")
        #expect(config.activePreset.id == Preset.balancedID)
    }

    @Test func setActiveRejectsUnknownPreset() {
        var config = Config()
        #expect(throws: Config.EditError.unknownPreset) { try config.setActive("nope") }
    }

    @Test func setActiveAcceptsBuiltIn() throws {
        var config = Config()
        try config.setActive(Preset.maxID)
        #expect(config.activePresetID == "max")
    }

    @Test func upsertInsertsThenUpdates() throws {
        var config = Config()
        try config.upsert(customPreset())
        var renamed = customPreset()
        renamed.name = "Render"
        try config.upsert(renamed)
        #expect(config.customPresets.count == 1)
        #expect(config.customPresets[0].name == "Render")
        #expect(config.allPresets.count == 6)
    }

    @Test func upsertRejectsBuiltIn() {
        var config = Config()
        var preset = Preset.balanced
        preset.isBuiltIn = false
        #expect(throws: Config.EditError.builtInReadOnly) { try config.upsert(preset) }
    }

    @Test func upsertRejectsEmptyName() {
        var config = Config()
        #expect(throws: Config.EditError.emptyName) { try config.upsert(customPreset(name: "  ")) }
    }

    @Test func upsertRejectsNonCurve() {
        var config = Config()
        var preset = customPreset()
        preset.kind = .max
        #expect(throws: Config.EditError.notACurve) { try config.upsert(preset) }
    }

    @Test func upsertRejectsInvalidCurve() {
        var config = Config()
        var preset = customPreset()
        preset.curve.points = [CurvePoint(temp: 50, percent: 0)]
        #expect(throws: Config.EditError.invalidCurve(.tooFewPoints)) { try config.upsert(preset) }
    }

    @Test func deleteActiveCustomFallsBackToBalanced() throws {
        var config = Config()
        try config.upsert(customPreset())
        try config.setActive("c1")
        try config.delete("c1")
        #expect(config.customPresets.isEmpty)
        #expect(config.activePresetID == Preset.balancedID)
    }

    @Test func deleteRejectsBuiltInAndUnknown() {
        var config = Config()
        #expect(throws: Config.EditError.builtInReadOnly) { try config.delete(Preset.silentID) }
        #expect(throws: Config.EditError.unknownPreset) { try config.delete("nope") }
    }

    @Test func duplicatedPresetIsCustomAndSavable() throws {
        let copy = Preset.balanced.duplicated()
        #expect(copy.id != Preset.balancedID)
        #expect(copy.name == "Cân bằng (bản sao)")
        #expect(!copy.isBuiltIn)
        var config = Config()
        try config.upsert(copy)
        #expect(config.customPresets == [copy])
    }

    @Test func configRoundTripsThroughJSON() throws {
        var config = Config()
        try config.upsert(customPreset())
        let data = try JSONEncoder().encode(config)
        #expect(try JSONDecoder().decode(Config.self, from: data) == config)
    }

    @Test func statusRoundTripsThroughJSON() throws {
        let status = Status(
            temperature: 58.5,
            fans: [FanStatus(index: 0, rpm: 2450, minRPM: 1200, maxRPM: 5779, manual: true)],
            activePresetID: "balanced", presets: Preset.builtIns, safetyActive: false, error: nil)
        let data = try JSONEncoder().encode(status)
        #expect(try JSONDecoder().decode(Status.self, from: data) == status)
    }

    @Test func fanFractionIsClamped() {
        #expect(FanStatus(index: 0, rpm: 0, minRPM: 1200, maxRPM: 5200, manual: false).fraction == 0)
        #expect(FanStatus(index: 0, rpm: 3200, minRPM: 1200, maxRPM: 5200, manual: true).fraction == 0.5)
        #expect(FanStatus(index: 0, rpm: 9000, minRPM: 1200, maxRPM: 5200, manual: true).fraction == 1)
    }
}
