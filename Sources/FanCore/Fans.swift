import Foundation

public struct FanInfo: Equatable, Sendable {
    public let index: Int
    public let minRPM: Double
    public let maxRPM: Double

    public init(index: Int, minRPM: Double, maxRPM: Double) {
        self.index = index
        self.minRPM = minRPM
        self.maxRPM = maxRPM
    }

    /// % (0–100) → RPM, kẹp trong [min, max].
    public func rpm(forPercent percent: Double) -> Double {
        let clamped = min(max(percent, 0), 100)
        return minRPM + clamped / 100 * (maxRPM - minRPM)
    }
}

public enum FanCommand: Equatable, Sendable {
    case auto
    case manual(rpm: Double)
}

/// Đọc/ghi quạt qua các key SMC: FNum, FxMn, FxMx, FxAc, FxMd (0 = Apple, 1 = manual), FxTg.
public final class FanService {
    private let smc: SMCDevice

    public init(smc: SMCDevice) {
        self.smc = smc
    }

    public func discoverFans() throws -> [FanInfo] {
        let count = Int(try smc.readUInt8("FNum"))
        return try (0..<count).map { index in
            FanInfo(index: index,
                    minRPM: Double(try smc.readFloat("F\(index)Mn")),
                    maxRPM: Double(try smc.readFloat("F\(index)Mx")))
        }
    }

    public func currentRPM(_ index: Int) throws -> Double {
        Double(try smc.readFloat("F\(index)Ac"))
    }

    public func isManual(_ index: Int) throws -> Bool {
        try smc.readUInt8("F\(index)Md") != 0
    }

    public func apply(_ command: FanCommand, to fan: FanInfo) throws {
        switch command {
        case .auto:
            try smc.writeUInt8("F\(fan.index)Md", 0)
        case .manual(let rpm):
            try smc.writeUInt8("F\(fan.index)Md", 1)
            try smc.writeFloat("F\(fan.index)Tg", Float(min(max(rpm, fan.minRPM), fan.maxRPM)))
        }
    }
}
