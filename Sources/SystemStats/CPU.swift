import Foundation

/// Tổng tick CPU tích lũy từ lúc khởi động (mọi nhân).
public struct CPUTicks: Equatable, Sendable {
    public var user: UInt64
    public var system: UInt64
    public var idle: UInt64
    public var nice: UInt64

    public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }
}

public enum CPUUsage {
    /// % CPU bận giữa hai lần đọc. `nil` khi không có tick nào trôi qua hoặc bộ đếm bị reset.
    public static func usage(from old: CPUTicks, to new: CPUTicks) -> Double? {
        guard new.user >= old.user, new.system >= old.system, new.idle >= old.idle, new.nice >= old.nice else {
            return nil
        }
        let busy = Double((new.user - old.user) + (new.system - old.system) + (new.nice - old.nice))
        let total = busy + Double(new.idle - old.idle)
        guard total > 0 else { return nil }
        return busy / total * 100
    }
}
