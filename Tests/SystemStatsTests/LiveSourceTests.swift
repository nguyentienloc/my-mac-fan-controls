import Foundation
import Testing
@testable import SystemStats

/// Đọc số liệu thật của máy đang chạy test (chỉ đọc, không cần quyền đặc biệt).
struct LiveSourceTests {
    let source = LiveSystemSource()

    @Test func readsCPUTicks() {
        let ticks = source.cpuTicks()
        #expect(ticks != nil)
        #expect((ticks?.idle ?? 0) > 0)
    }

    @Test func readsMemory() throws {
        let counts = try #require(source.memoryCounts())
        let used = counts.usedBytes(pageSize: source.pageSize())
        #expect(used > 0)
        #expect(used <= source.physicalMemory())
        #expect([1, 2, 4].contains(source.memoryPressureLevel()))
    }

    @Test func readsDisk() throws {
        let disk = try #require(source.diskCapacity())
        #expect(disk.total > 0)
        #expect(disk.free <= disk.total)
    }

    @Test func readsOnlyPhysicalInterfaces() {
        let counters = source.interfaceCounters()
        // Máy không có Wi-Fi/Ethernet đang hoạt động (ví dụ đã tắt Wi-Fi) thì không có gì để kiểm tra.
        guard !counters.isEmpty else { return }
        #expect(counters.keys.allSatisfy { $0.hasPrefix("en") })
    }

    /// Bộ đếm 64-bit: en0 đã vượt 4 GB (giới hạn của số 32-bit), hoặc có giá trị không chia hết cho 1 KB.
    @Test func networkCountersMatch64Bit() {
        let counters = source.interfaceCounters()
        // Máy không có Wi-Fi/Ethernet đang hoạt động (ví dụ đã tắt Wi-Fi) thì không có gì để kiểm tra.
        guard !counters.isEmpty else { return }
        let values = counters.values.flatMap { [$0.received, $0.sent] }
        #expect(values.contains { $0 > UInt64(UInt32.max) } || values.contains { $0 != 0 && $0 % 1024 != 0 })
    }

    @Test func liveSamplerProducesRatesOnSecondSample() async throws {
        let sampler = SystemSampler()
        _ = sampler.sample(now: Date())
        try await Task.sleep(for: .milliseconds(300))
        let snapshot = sampler.sample(now: Date())
        let cpu = try #require(snapshot.cpuPercent)
        #expect((0...100).contains(cpu))
        // Tốc độ mạng chỉ kiểm tra khi có card Wi-Fi/Ethernet đang hoạt động.
        if !LiveSystemSource().interfaceCounters().isEmpty {
            #expect((snapshot.downloadBytesPerSecond ?? -1) >= 0)
            #expect((snapshot.uploadBytesPerSecond ?? -1) >= 0)
        }
    }
}
