@testable import FanCore

/// SMC giả lập trong bộ nhớ, ghi lại mọi lệnh ghi.
final class MockSMC: SMCDevice {
    struct Entry {
        var type: String
        var bytes: [UInt8]
    }

    var entries: [String: Entry] = [:]
    var writes: [(key: String, bytes: [UInt8])] = []
    var failingReads: Set<String> = []
    var failWrites = false

    func setFloat(_ key: String, _ value: Float) {
        entries[key] = Entry(type: "flt ", bytes: withUnsafeBytes(of: value) { Array($0) })
    }

    func setUInt8(_ key: String, _ value: UInt8) {
        entries[key] = Entry(type: "ui8 ", bytes: [value])
    }

    func float(_ key: String) -> Float? {
        entries[key].map { $0.bytes.withUnsafeBytes { $0.loadUnaligned(as: Float.self) } }
    }

    func uint8(_ key: String) -> UInt8? {
        entries[key]?.bytes.first
    }

    func keyInfo(_ key: String) throws -> SMCKeyInfo {
        guard let entry = entries[key] else { throw SMCError.keyNotFound(key) }
        return SMCKeyInfo(size: UInt32(entry.bytes.count), type: entry.type)
    }

    func readBytes(_ key: String) throws -> [UInt8] {
        if failingReads.contains(key) { throw SMCError.callFailed(key, -1) }
        guard let entry = entries[key] else { throw SMCError.keyNotFound(key) }
        return entry.bytes
    }

    func writeBytes(_ key: String, _ bytes: [UInt8]) throws {
        if failWrites { throw SMCError.callFailed(key, -1) }
        guard entries[key] != nil else { throw SMCError.keyNotFound(key) }
        entries[key]!.bytes = bytes
        writes.append((key, bytes))
    }

    func allKeys() throws -> [String] {
        entries.keys.sorted()
    }

    /// Giống MacBook Pro M1 Pro: 2 quạt, 3 cảm biến hợp lệ, 1 key nhiễu kiểu ui8.
    static func m1Pro() -> MockSMC {
        let smc = MockSMC()
        smc.setUInt8("FNum", 2)
        for (index, maxRPM) in [(0, Float(5779)), (1, Float(6241))] {
            smc.setFloat("F\(index)Mn", 1200)
            smc.setFloat("F\(index)Mx", maxRPM)
            smc.setFloat("F\(index)Ac", 0)
            smc.setFloat("F\(index)Tg", 0)
            smc.setUInt8("F\(index)Md", 0)
        }
        smc.setFloat("Tp01", 50)
        smc.setFloat("Te05", 45)
        smc.setFloat("Tg05", 48)
        smc.setUInt8("Tp0Z", 77)
        return smc
    }
}
