import Foundation

/// Bộ đếm byte tích lũy của một card mạng.
public struct InterfaceCounters: Equatable, Sendable {
    public var received: UInt64
    public var sent: UInt64

    public init(received: UInt64, sent: UInt64) {
        self.received = received
        self.sent = sent
    }
}

public struct NetworkRates: Equatable, Sendable {
    public var download: Double
    public var upload: Double

    public init(download: Double, upload: Double) {
        self.download = download
        self.upload = upload
    }
}

public enum NetworkStats {
    /// Tốc độ (byte/giây) giữa hai lần đọc. Card mới xuất hiện hoặc có bộ đếm giảm (reset) thì bỏ qua card đó.
    public static func rates(from old: [String: InterfaceCounters], to new: [String: InterfaceCounters],
                             elapsed: TimeInterval) -> NetworkRates? {
        guard elapsed > 0 else { return nil }
        var received: UInt64 = 0
        var sent: UInt64 = 0
        for (name, current) in new {
            guard let previous = old[name], current.received >= previous.received, current.sent >= previous.sent else {
                continue
            }
            received += current.received - previous.received
            sent += current.sent - previous.sent
        }
        return NetworkRates(download: Double(received) / elapsed, upload: Double(sent) / elapsed)
    }

    /// Chỉ đếm card vật lý Wi-Fi/Ethernet (`en*`): lưu lượng của utun (VPN), bridge, awdl đi chồng qua `en*`.
    public static func isCounted(name: String) -> Bool {
        name.hasPrefix("en")
    }
}
