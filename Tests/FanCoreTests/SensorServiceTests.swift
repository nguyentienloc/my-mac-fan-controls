import Testing
@testable import FanCore

struct SensorServiceTests {
    @Test func discoversOnlyFloatCPUAndGPUKeys() throws {
        let sensors = try SensorService(smc: MockSMC.m1Pro())
        #expect(sensors.keys == ["Te05", "Tg05", "Tp01"])
    }

    @Test func returnsMaximumTemperature() throws {
        let smc = MockSMC.m1Pro()
        smc.setFloat("Tg05", 61.5)
        #expect(try SensorService(smc: smc).readMaxTemperature() == 61.5)
    }

    @Test func ignoresOutOfRangeValues() throws {
        let smc = MockSMC.m1Pro()
        smc.setFloat("Tg05", 200)
        smc.setFloat("Te05", -5)
        #expect(try SensorService(smc: smc).readMaxTemperature() == 50)
    }

    @Test func ignoresFailingSensors() throws {
        let smc = MockSMC.m1Pro()
        let sensors = try SensorService(smc: smc)
        smc.failingReads = ["Tp01"]
        #expect(try sensors.readMaxTemperature() == 48)
    }

    @Test func throwsWhenNoValidReading() throws {
        let smc = MockSMC.m1Pro()
        let sensors = try SensorService(smc: smc)
        smc.failingReads = ["Tp01", "Te05", "Tg05"]
        #expect(throws: SensorError.noValidReading) { try sensors.readMaxTemperature() }
    }
}
