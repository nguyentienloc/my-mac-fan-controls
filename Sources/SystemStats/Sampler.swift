import Foundation

/// Nguồn số liệu thô. `LiveSystemSource` đọc hệ thống thật; test dùng bản giả.
public protocol SystemSource {
    func cpuTicks() -> CPUTicks?
    func memoryCounts() -> MemoryCounts?
    func pageSize() -> UInt64
    func physicalMemory() -> UInt64
    func memoryPressureLevel() -> Int32
    func diskCapacity() -> (free: UInt64, total: UInt64)?
    func interfaceCounters() -> [String: InterfaceCounters]
}

/// Lấy mẫu định kỳ; giữ lần đọc CPU và mạng trước đó để tính % và tốc độ.
public final class SystemSampler {
    private let source: SystemSource
    private var lastTicks: CPUTicks?
    private var lastNetwork: (counters: [String: InterfaceCounters], time: Date)?

    public init(source: SystemSource) {
        self.source = source
    }

    public func sample(now: Date) -> SystemSnapshot {
        let ticks = source.cpuTicks()
        var cpuPercent: Double?
        if let previous = lastTicks, let ticks {
            cpuPercent = CPUUsage.usage(from: previous, to: ticks)
        }
        lastTicks = ticks

        let counters = source.interfaceCounters()
        var rates: NetworkRates?
        if let last = lastNetwork {
            rates = NetworkStats.rates(from: last.counters, to: counters, elapsed: now.timeIntervalSince(last.time))
        }
        lastNetwork = (counters, now)

        let disk = source.diskCapacity()
        return SystemSnapshot(
            cpuPercent: cpuPercent,
            memoryUsed: source.memoryCounts()?.usedBytes(pageSize: source.pageSize()) ?? 0,
            memoryTotal: source.physicalMemory(),
            memoryPressure: MemoryPressure(sysctlLevel: source.memoryPressureLevel()),
            diskFree: disk?.free,
            diskTotal: disk?.total,
            downloadBytesPerSecond: rates?.download,
            uploadBytesPerSecond: rates?.upload)
    }
}
