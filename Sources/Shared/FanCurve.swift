import Foundation

/// Một điểm trên đường cong: tại `temp` °C quạt chạy `percent` % (0 = min, 100 = max của từng quạt).
public struct CurvePoint: Codable, Hashable, Sendable {
    public var temp: Double
    public var percent: Double

    public init(temp: Double, percent: Double) {
        self.temp = temp
        self.percent = percent
    }
}

public struct FanCurve: Codable, Hashable, Sendable {
    public var points: [CurvePoint]

    public init(points: [CurvePoint]) {
        self.points = points
    }

    public static let validTempRange: ClosedRange<Double> = 20...110
    public static let validPercentRange: ClosedRange<Double> = 0...100

    /// % tốc độ tại `temp`. `nil` nghĩa là dưới điểm đầu → trả quạt cho Apple.
    public func percent(at temp: Double) -> Double? {
        guard let first = points.first, let last = points.last, temp >= first.temp else { return nil }
        if temp >= last.temp { return last.percent }
        for (a, b) in zip(points, points.dropFirst()) where temp < b.temp {
            let t = (temp - a.temp) / (b.temp - a.temp)
            return a.percent + t * (b.percent - a.percent)
        }
        return last.percent
    }

    public enum ValidationError: Error, Equatable, Sendable {
        case tooFewPoints
        case tempOutOfRange
        case percentOutOfRange
        case tempNotIncreasing
        case percentDecreasing

        public var message: String {
            switch self {
            case .tooFewPoints: return "Cần ít nhất 2 điểm"
            case .tempOutOfRange: return "Nhiệt độ phải trong khoảng 20–110°C"
            case .percentOutOfRange: return "Tốc độ phải trong khoảng 0–100%"
            case .tempNotIncreasing: return "Nhiệt độ các điểm phải tăng dần"
            case .percentDecreasing: return "Tốc độ không được giảm khi nhiệt độ tăng"
            }
        }
    }

    public func validate() -> ValidationError? {
        guard points.count >= 2 else { return .tooFewPoints }
        if points.contains(where: { !Self.validTempRange.contains($0.temp) }) { return .tempOutOfRange }
        if points.contains(where: { !Self.validPercentRange.contains($0.percent) }) { return .percentOutOfRange }
        for (a, b) in zip(points, points.dropFirst()) {
            if b.temp <= a.temp { return .tempNotIncreasing }
            if b.percent < a.percent { return .percentDecreasing }
        }
        return nil
    }
}
