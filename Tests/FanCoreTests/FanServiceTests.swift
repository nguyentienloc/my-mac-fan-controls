import Testing
@testable import FanCore

struct FanServiceTests {
    @Test func discoversBothFans() throws {
        let fans = try FanService(smc: MockSMC.m1Pro()).discoverFans()
        #expect(fans == [
            FanInfo(index: 0, minRPM: 1200, maxRPM: 5779),
            FanInfo(index: 1, minRPM: 1200, maxRPM: 6241),
        ])
    }

    @Test func percentMapsToRPMAndClamps() {
        let fan = FanInfo(index: 0, minRPM: 1200, maxRPM: 5779)
        #expect(fan.rpm(forPercent: 50) == 3489.5)
        #expect(fan.rpm(forPercent: -10) == 1200)
        #expect(fan.rpm(forPercent: 150) == 5779)
    }

    @Test func manualCommandSetsModeAndTarget() throws {
        let smc = MockSMC.m1Pro()
        let fan = FanInfo(index: 1, minRPM: 1200, maxRPM: 6241)
        try FanService(smc: smc).apply(.manual(rpm: 3000), to: fan)
        #expect(smc.uint8("F1Md") == 1)
        #expect(smc.float("F1Tg") == 3000)
    }

    @Test func manualCommandIsClampedToFanRange() throws {
        let smc = MockSMC.m1Pro()
        let fan = FanInfo(index: 0, minRPM: 1200, maxRPM: 5779)
        try FanService(smc: smc).apply(.manual(rpm: 9999), to: fan)
        #expect(smc.float("F0Tg") == 5779)
        try FanService(smc: smc).apply(.manual(rpm: 10), to: fan)
        #expect(smc.float("F0Tg") == 1200)
    }

    @Test func autoCommandClearsManualMode() throws {
        let smc = MockSMC.m1Pro()
        smc.setUInt8("F0Md", 1)
        try FanService(smc: smc).apply(.auto, to: FanInfo(index: 0, minRPM: 1200, maxRPM: 5779))
        #expect(smc.uint8("F0Md") == 0)
    }

    @Test func readsCurrentRPMAndMode() throws {
        let smc = MockSMC.m1Pro()
        smc.setFloat("F0Ac", 2450)
        smc.setUInt8("F0Md", 1)
        let service = FanService(smc: smc)
        #expect(try service.currentRPM(0) == 2450)
        #expect(try service.isManual(0))
        #expect(try !service.isManual(1))
    }
}
