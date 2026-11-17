import Foundation

public enum GPUStats {
    /// % GPU bận lấy từ từ điển `PerformanceStatistics` của IOAccelerator (khóa "Device Utilization %",
    /// cùng số Activity Monitor hiển thị). Kẹp 0...100; thiếu khóa hoặc sai kiểu → nil.
    public static func utilization(from statistics: [String: Any]) -> Double? {
        guard let number = statistics["Device Utilization %"] as? NSNumber else { return nil }
        let value = number.doubleValue
        guard value.isFinite else { return nil }
        return min(max(value, 0), 100)
    }
}
