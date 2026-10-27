import Testing
@testable import SystemStats

struct CalculationTests {
    @Test func cpuUsageFromTickDeltas() {
        let old = CPUTicks(user: 100, system: 50, idle: 800, nice: 50)
        let new = CPUTicks(user: 130, system: 60, idle: 850, nice: 60)
        // bận = 30 + 10 + 10 = 50, tổng = 50 + 50 = 100
        #expect(CPUUsage.usage(from: old, to: new) == 50)
    }

    @Test func cpuUsageIsNilWithoutElapsedTicks() {
        let ticks = CPUTicks(user: 1, system: 1, idle: 1, nice: 1)
        #expect(CPUUsage.usage(from: ticks, to: ticks) == nil)
    }

    @Test func cpuUsageIsNilWhenCountersGoBackwards() {
        let old = CPUTicks(user: 100, system: 50, idle: 800, nice: 50)
        let new = CPUTicks(user: 90, system: 60, idle: 850, nice: 60)
        #expect(CPUUsage.usage(from: old, to: new) == nil)
    }

    @Test func memoryUsedMatchesActivityMonitorFormula() {
        let counts = MemoryCounts(internalPages: 500, purgeablePages: 100, wiredPages: 200, compressedPages: 50)
        // (500 − 100 + 200 + 50) × 16384
        #expect(counts.usedBytes(pageSize: 16384) == 650 * 16384)
    }

    @Test func memoryUsedNeverUnderflows() {
        let counts = MemoryCounts(internalPages: 10, purgeablePages: 20, wiredPages: 5, compressedPages: 0)
        #expect(counts.usedBytes(pageSize: 1) == 5)
    }

    @Test func memoryPressureMapping() {
        #expect(MemoryPressure(sysctlLevel: 1) == .normal)
        #expect(MemoryPressure(sysctlLevel: 2) == .warning)
        #expect(MemoryPressure(sysctlLevel: 4) == .critical)
        #expect(MemoryPressure(sysctlLevel: 0) == .normal)
    }

    @Test func networkRatesSumInterfaces() {
        let old = ["en0": InterfaceCounters(received: 1000, sent: 500), "en1": InterfaceCounters(received: 0, sent: 0)]
        let new = ["en0": InterfaceCounters(received: 3000, sent: 900), "en1": InterfaceCounters(received: 1000, sent: 100)]
        #expect(NetworkStats.rates(from: old, to: new, elapsed: 2) == NetworkRates(download: 1500, upload: 250))
    }

    @Test func networkRatesSkipNewAndResetInterfaces() {
        let old = ["en0": InterfaceCounters(received: 5000, sent: 5000)]
        let new = [
            "en0": InterfaceCounters(received: 100, sent: 100),       // bộ đếm giảm → bỏ qua
            "en5": InterfaceCounters(received: 9000, sent: 9000),     // card mới → bỏ qua
        ]
        #expect(NetworkStats.rates(from: old, to: new, elapsed: 1) == NetworkRates(download: 0, upload: 0))
    }

    @Test func networkRatesNeedPositiveElapsed() {
        #expect(NetworkStats.rates(from: [:], to: [:], elapsed: 0) == nil)
    }

    @Test func onlyPhysicalInterfacesAreCounted() {
        #expect(NetworkStats.isCounted(name: "en0"))
        #expect(NetworkStats.isCounted(name: "en7"))
        #expect(!NetworkStats.isCounted(name: "utun3"))
        #expect(!NetworkStats.isCounted(name: "bridge0"))
        #expect(!NetworkStats.isCounted(name: "awdl0"))
        #expect(!NetworkStats.isCounted(name: "lo0"))
    }
}
