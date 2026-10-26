import Foundation
import Testing
import Shared
@testable import FanCore

struct ControlLoopTests {
    let smc = MockSMC.m1Pro()
    let store = ConfigStore(url: FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("config.json"))

    func makeLoop(dryRun: Bool = false) throws -> ControlLoop {
        try ControlLoop(smc: smc, store: store, dryRun: dryRun, log: { _ in })
    }

    @Test func startReleasesAllFans() throws {
        smc.setUInt8("F0Md", 1)
        smc.setUInt8("F1Md", 1)
        try makeLoop().start()
        #expect(smc.uint8("F0Md") == 0)
        #expect(smc.uint8("F1Md") == 0)
    }

    @Test func tickAppliesBalancedCurve() throws {
        let loop = try makeLoop()
        loop.start()
        smc.setFloat("Tp01", 70)
        loop.tick()
        #expect(smc.uint8("F0Md") == 1)
        #expect(smc.float("F0Tg") == 3489.5)
        #expect(smc.float("F1Tg") == 3720.5)
    }

    @Test func tickUpdatesStatus() throws {
        let loop = try makeLoop()
        loop.start()
        smc.setFloat("Tp01", 70)
        smc.setFloat("F0Ac", 3400)
        loop.tick()
        #expect(loop.status.temperature == 70)
        #expect(loop.status.fans.map(\.rpm) == [3400, 0])
        #expect(loop.status.fans[0].manual)
        #expect(loop.status.activePresetID == Preset.balancedID)
        #expect(loop.status.presets.count == 5)
        #expect(loop.status.error == nil)
    }

    @Test func dryRunNeverWrites() throws {
        let loop = try makeLoop(dryRun: true)
        loop.start()
        smc.setFloat("Tp01", 70)
        loop.tick()
        #expect(smc.writes.isEmpty)
    }

    @Test func releaseAllReturnsFansToApple() throws {
        let loop = try makeLoop()
        loop.start()
        smc.setFloat("Tp01", 70)
        loop.tick()
        loop.releaseAll()
        #expect(smc.uint8("F0Md") == 0)
        #expect(smc.uint8("F1Md") == 0)
    }

    @Test func followsActivePresetFromStore() throws {
        let loop = try makeLoop()
        loop.start()
        smc.setFloat("Tp01", 70)
        loop.tick()
        try store.update { try $0.setActive(Preset.autoID) }
        loop.tick()
        #expect(smc.uint8("F0Md") == 0)
        #expect(loop.status.activePresetID == Preset.autoID)
    }

    @Test func repeatedWriteFailuresSurfaceError() throws {
        let loop = try makeLoop()
        loop.start()
        smc.setFloat("Tp01", 70)
        smc.failWrites = true
        // Mỗi quạt lỗi 3 lần liên tiếp ở tick 1–3; bỏ cuộc và báo lỗi chỉ từ tick 4 (kiểm tra ở đầu chu kỳ).
        loop.tick()
        loop.tick()
        loop.tick()
        loop.tick()
        #expect(loop.status.error == Controller.writeErrorMessage)
    }

    @Test func repeatedSensorFailuresReleaseFans() throws {
        let loop = try makeLoop()
        loop.start()
        smc.setFloat("Tp01", 70)
        loop.tick()
        smc.failingReads = ["Tp01", "Te05", "Tg05"]
        loop.tick()
        loop.tick()
        loop.tick()
        #expect(loop.status.error == Controller.sensorErrorMessage)
        #expect(smc.uint8("F0Md") == 0)
    }
}
