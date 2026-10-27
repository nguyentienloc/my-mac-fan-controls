import Foundation

public enum MemoryPressure: Equatable, Sendable {
    case normal
    case warning
    case critical

    /// Giá trị sysctl `kern.memorystatus_vm_pressure_level`: 1 bình thường, 2 cao, 4 nguy hiểm.
    public init(sysctlLevel: Int32) {
        switch sysctlLevel {
        case 2: self = .warning
        case 4: self = .critical
        default: self = .normal
        }
    }
}

/// Một lần lấy mẫu số liệu hệ thống. `nil` nghĩa là chưa có (lần đo đầu) hoặc đọc lỗi.
public struct SystemSnapshot: Equatable, Sendable {
    public var cpuPercent: Double?
    public var memoryUsed: UInt64
    public var memoryTotal: UInt64
    public var memoryPressure: MemoryPressure
    public var diskFree: UInt64?
    public var diskTotal: UInt64?
    public var downloadBytesPerSecond: Double?
    public var uploadBytesPerSecond: Double?

    public init(cpuPercent: Double?, memoryUsed: UInt64, memoryTotal: UInt64, memoryPressure: MemoryPressure,
                diskFree: UInt64?, diskTotal: UInt64?, downloadBytesPerSecond: Double?, uploadBytesPerSecond: Double?) {
        self.cpuPercent = cpuPercent
        self.memoryUsed = memoryUsed
        self.memoryTotal = memoryTotal
        self.memoryPressure = memoryPressure
        self.diskFree = diskFree
        self.diskTotal = diskTotal
        self.downloadBytesPerSecond = downloadBytesPerSecond
        self.uploadBytesPerSecond = uploadBytesPerSecond
    }
}
