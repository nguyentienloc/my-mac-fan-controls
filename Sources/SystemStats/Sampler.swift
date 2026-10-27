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

    private var lastDisk: (value: (free: UInt64, total: UInt64)?, time: Date)?
    private let diskInterval: TimeInterval

    public init(source: SystemSource, diskInterval: TimeInterval = 30) {
        self.source = source
        self.diskInterval = diskInterval
    }

    /// Lấy mẫu từ hệ thống thật.
    public convenience init() {
        self.init(source: LiveSystemSource())
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

        // Dung lượng ổ đĩa đổi chậm và đọc tốn vài chục ms, nên chỉ đọc lại mỗi 30 giây.
        // Đồng hồ chạy lùi (now < time đã lưu) cũng buộc đọc lại.
        let disk: (free: UInt64, total: UInt64)?
        if let cached = lastDisk, now >= cached.time, now.timeIntervalSince(cached.time) < diskInterval {
            disk = cached.value
        } else {
            disk = source.diskCapacity()
            lastDisk = (disk, now)
        }
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
