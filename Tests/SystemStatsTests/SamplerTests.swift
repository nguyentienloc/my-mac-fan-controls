import Foundation
import Testing
@testable import SystemStats

/// Nguồn giả: trả các giá trị được gán sẵn.
final class FakeSource: SystemSource {
    var ticks: CPUTicks? = CPUTicks(user: 0, system: 0, idle: 0, nice: 0)
    var counts: MemoryCounts? = MemoryCounts(internalPages: 100, purgeablePages: 0, wiredPages: 0, compressedPages: 0)
    var pressureLevel: Int32 = 1
    var disk: (free: UInt64, total: UInt64)? = (free: 100, total: 500)
    var counters: [String: InterfaceCounters] = ["en0": InterfaceCounters(received: 0, sent: 0)]

    func cpuTicks() -> CPUTicks? { ticks }
    func memoryCounts() -> MemoryCounts? { counts }
    func pageSize() -> UInt64 { 1024 }
    func physicalMemory() -> UInt64 { 1_048_576 }
    func memoryPressureLevel() -> Int32 { pressureLevel }
    func diskCapacity() -> (free: UInt64, total: UInt64)? { disk }
    func interfaceCounters() -> [String: InterfaceCounters] { counters }
}

struct SamplerTests {
    let start = Date(timeIntervalSince1970: 1_000)

    @Test func firstSampleHasNoRates() {
        let sampler = SystemSampler(source: FakeSource())
        let snapshot = sampler.sample(now: start)
        #expect(snapshot.cpuPercent == nil)
        #expect(snapshot.downloadBytesPerSecond == nil)
        #expect(snapshot.uploadBytesPerSecond == nil)
        #expect(snapshot.memoryUsed == 102_400)
        #expect(snapshot.memoryTotal == 1_048_576)
        #expect(snapshot.memoryPressure == .normal)
        #expect(snapshot.diskFree == 100)
        #expect(snapshot.diskTotal == 500)
    }

    @Test func secondSampleComputesCPUAndNetwork() {
        let source = FakeSource()
        let sampler = SystemSampler(source: source)
        _ = sampler.sample(now: start)
        source.ticks = CPUTicks(user: 25, system: 0, idle: 75, nice: 0)
        source.counters = ["en0": InterfaceCounters(received: 4000, sent: 1000)]
        let snapshot = sampler.sample(now: start.addingTimeInterval(2))
        #expect(snapshot.cpuPercent == 25)
        #expect(snapshot.downloadBytesPerSecond == 2000)
        #expect(snapshot.uploadBytesPerSecond == 500)
    }

    @Test func failedSourcesBecomeNilOrZero() {
        let source = FakeSource()
        source.ticks = nil
        source.counts = nil
        source.disk = nil
        source.pressureLevel = 4
        let sampler = SystemSampler(source: source)
        _ = sampler.sample(now: start)
        let snapshot = sampler.sample(now: start.addingTimeInterval(2))
        #expect(snapshot.cpuPercent == nil)
        #expect(snapshot.memoryUsed == 0)
        #expect(snapshot.diskFree == nil)
        #expect(snapshot.diskTotal == nil)
        #expect(snapshot.memoryPressure == .critical)
    }

    @Test func diskIsCachedBetweenRefreshes() {
        let source = FakeSource()
        source.disk = (free: 100, total: 500)
        let sampler = SystemSampler(source: source, diskInterval: 30)
        _ = sampler.sample(now: start)
        source.disk = (free: 50, total: 500)
        // Trong 30 giây: dùng giá trị đã lưu.
        #expect(sampler.sample(now: start.addingTimeInterval(10)).diskFree == 100)
        // Qua 30 giây: đọc lại.
        #expect(sampler.sample(now: start.addingTimeInterval(31)).diskFree == 50)
    }
}
