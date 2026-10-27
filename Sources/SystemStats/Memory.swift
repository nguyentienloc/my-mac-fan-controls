import Foundation

/// Số trang bộ nhớ lấy từ `vm_statistics64`.
public struct MemoryCounts: Equatable, Sendable {
    public var internalPages: UInt64
    public var purgeablePages: UInt64
    public var wiredPages: UInt64
    public var compressedPages: UInt64

    public init(internalPages: UInt64, purgeablePages: UInt64, wiredPages: UInt64, compressedPages: UInt64) {
        self.internalPages = internalPages
        self.purgeablePages = purgeablePages
        self.wiredPages = wiredPages
        self.compressedPages = compressedPages
    }

    /// "Memory Used" như Activity Monitor: bộ nhớ app (internal − purgeable) + wired + compressed.
    public func usedBytes(pageSize: UInt64) -> UInt64 {
        let appPages = internalPages > purgeablePages ? internalPages - purgeablePages : 0
        return (appPages + wiredPages + compressedPages) * pageSize
    }
}
