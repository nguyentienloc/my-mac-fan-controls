import Foundation

public enum SensorError: Error, Equatable {
    case noValidReading
}

/// Nhiệt độ cao nhất giữa CPU (Tp*, Te*) và GPU (Tg*).
public final class SensorService {
    public static let validRange: ClosedRange<Double> = 0...130

    private let smc: SMCDevice
    public let keys: [String]

    public init(smc: SMCDevice) throws {
        self.smc = smc
        keys = try smc.allKeys().filter { key in
            guard ["Tp", "Te", "Tg"].contains(where: { key.hasPrefix($0) }) else { return false }
            return (try? smc.keyInfo(key).type) == "flt "
        }
    }

    public func readMaxTemperature() throws -> Double {
        let values = keys
            .compactMap { try? Double(smc.readFloat($0)) }
            .filter { Self.validRange.contains($0) }
        guard let maximum = values.max() else { throw SensorError.noValidReading }
        return maximum
    }
}
