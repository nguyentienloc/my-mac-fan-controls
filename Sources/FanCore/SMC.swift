import Foundation

public struct SMCKeyInfo: Equatable, Sendable {
    public var size: UInt32
    public var type: String

    public init(size: UInt32, type: String) {
        self.size = size
        self.type = type
    }
}

public enum SMCError: Error, Equatable {
    case openFailed
    case keyNotFound(String)
    case callFailed(String, Int32)
    case typeMismatch(key: String, expected: String, actual: String)
}

/// Truy cập thô vào SMC. `AppleSMC` là bản thật; test dùng `MockSMC`.
public protocol SMCDevice: AnyObject {
    func keyInfo(_ key: String) throws -> SMCKeyInfo
    func readBytes(_ key: String) throws -> [UInt8]
    func writeBytes(_ key: String, _ bytes: [UInt8]) throws
    func allKeys() throws -> [String]
}

public extension SMCDevice {
    /// `flt ` trên Apple Silicon là float32 little-endian.
    func readFloat(_ key: String) throws -> Float {
        try requireType(key, "flt ")
        let bytes = try readBytes(key)
        guard bytes.count >= 4 else {
            throw SMCError.typeMismatch(key: key, expected: "flt ", actual: "\(bytes.count) byte")
        }
        return bytes.withUnsafeBytes { $0.loadUnaligned(as: Float.self) }
    }

    func readUInt8(_ key: String) throws -> UInt8 {
        try requireType(key, "ui8 ")
        guard let value = try readBytes(key).first else {
            throw SMCError.typeMismatch(key: key, expected: "ui8 ", actual: "0 byte")
        }
        return value
    }

    func writeFloat(_ key: String, _ value: Float) throws {
        try requireType(key, "flt ")
        try writeBytes(key, withUnsafeBytes(of: value) { Array($0) })
    }

    func writeUInt8(_ key: String, _ value: UInt8) throws {
        try requireType(key, "ui8 ")
        try writeBytes(key, [value])
    }

    private func requireType(_ key: String, _ expected: String) throws {
        let actual = try keyInfo(key).type
        guard actual == expected else { throw SMCError.typeMismatch(key: key, expected: expected, actual: actual) }
    }
}
