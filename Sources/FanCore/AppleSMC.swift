import Foundation
import IOKit

/// Layout khớp struct C `SMCParamStruct` (80 byte) của driver AppleSMC.
struct SMCParamStruct {
    var key: UInt32 = 0
    var vers: (UInt8, UInt8, UInt8, UInt8, UInt16) = (0, 0, 0, 0, 0)
    var pLimitData: (UInt16, UInt16, UInt32, UInt32, UInt32) = (0, 0, 0, 0, 0)
    // dataSize, dataType, dataAttributes + 3 byte đệm: Swift không tự đệm cuối tuple như C
    var keyInfo: (UInt32, UInt32, UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0, 0, 0)
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
        (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
         0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
}

/// SMC thật qua IOKit. Đọc không cần root; ghi cần root.
public final class AppleSMC: SMCDevice {
    private enum Command: UInt8 {
        case readBytes = 5
        case writeBytes = 6
        case readIndex = 8
        case readKeyInfo = 9
    }

    private static let kernelIndex: UInt32 = 2
    private static let keyNotFoundResult: UInt8 = 132
    private var connection: io_connect_t = 0

    public init() throws {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { throw SMCError.openFailed }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess else {
            throw SMCError.openFailed
        }
    }

    deinit {
        IOServiceClose(connection)
    }

    public func keyInfo(_ key: String) throws -> SMCKeyInfo {
        var input = SMCParamStruct()
        input.key = fourCC(key)
        input.data8 = Command.readKeyInfo.rawValue
        let output = try call(&input, key: key)
        return SMCKeyInfo(size: output.keyInfo.0, type: fourCCString(output.keyInfo.1))
    }

    public func readBytes(_ key: String) throws -> [UInt8] {
        let info = try keyInfo(key)
        var input = SMCParamStruct()
        input.key = fourCC(key)
        input.keyInfo.0 = info.size
        input.data8 = Command.readBytes.rawValue
        let output = try call(&input, key: key)
        return withUnsafeBytes(of: output.bytes) { Array($0.prefix(Int(info.size))) }
    }

    public func writeBytes(_ key: String, _ bytes: [UInt8]) throws {
        let info = try keyInfo(key)
        guard bytes.count == Int(info.size) else {
            throw SMCError.typeMismatch(key: key, expected: "\(info.size) byte", actual: "\(bytes.count) byte")
        }
        var input = SMCParamStruct()
        input.key = fourCC(key)
        input.keyInfo.0 = info.size
        input.data8 = Command.writeBytes.rawValue
        withUnsafeMutableBytes(of: &input.bytes) { buffer in
            for (offset, byte) in bytes.enumerated() { buffer[offset] = byte }
        }
        _ = try call(&input, key: key)
    }

    public func allKeys() throws -> [String] {
        // #KEY là ui32 big-endian
        let count = try readBytes("#KEY").reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        return try (0..<count).map { index in
            var input = SMCParamStruct()
            input.data8 = Command.readIndex.rawValue
            input.data32 = index
            return fourCCString(try call(&input, key: "#\(index)").key)
        }
    }

    private func call(_ input: inout SMCParamStruct, key: String) throws -> SMCParamStruct {
        var output = SMCParamStruct()
        var outputSize = MemoryLayout<SMCParamStruct>.stride
        let result = IOConnectCallStructMethod(
            connection, Self.kernelIndex, &input, MemoryLayout<SMCParamStruct>.stride, &output, &outputSize)
        guard result == kIOReturnSuccess else { throw SMCError.callFailed(key, result) }
        guard output.result == 0 else {
            throw output.result == Self.keyNotFoundResult
                ? SMCError.keyNotFound(key)
                : SMCError.callFailed(key, Int32(output.result))
        }
        return output
    }
}
