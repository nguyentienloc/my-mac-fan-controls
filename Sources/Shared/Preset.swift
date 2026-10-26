import Foundation

public enum PresetKind: String, Codable, Sendable {
    case auto   // trả quạt cho Apple
    case max    // luôn 100%
    case curve  // theo đường cong
}

public struct Preset: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var kind: PresetKind
    public var curve: FanCurve
    public var isBuiltIn: Bool

    public init(id: String, name: String, kind: PresetKind, curve: FanCurve = FanCurve(points: []), isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.kind = kind
        self.curve = curve
        self.isBuiltIn = isBuiltIn
    }

    public static let autoID = "auto"
    public static let silentID = "silent"
    public static let balancedID = "balanced"
    public static let performanceID = "performance"
    public static let maxID = "max"

    public static let builtIns: [Preset] = [
        Preset(id: autoID, name: "Apple tự động", kind: .auto, isBuiltIn: true),
        Preset(id: silentID, name: "Êm", kind: .curve, curve: FanCurve(points: [
            CurvePoint(temp: 65, percent: 0), CurvePoint(temp: 75, percent: 30),
            CurvePoint(temp: 85, percent: 60), CurvePoint(temp: 92, percent: 100),
        ]), isBuiltIn: true),
        Preset(id: balancedID, name: "Cân bằng", kind: .curve, curve: FanCurve(points: [
            CurvePoint(temp: 55, percent: 0), CurvePoint(temp: 65, percent: 35),
            CurvePoint(temp: 75, percent: 65), CurvePoint(temp: 85, percent: 100),
        ]), isBuiltIn: true),
        Preset(id: performanceID, name: "Hiệu năng", kind: .curve, curve: FanCurve(points: [
            CurvePoint(temp: 45, percent: 20), CurvePoint(temp: 60, percent: 50),
            CurvePoint(temp: 70, percent: 80), CurvePoint(temp: 78, percent: 100),
        ]), isBuiltIn: true),
        Preset(id: maxID, name: "Tối đa", kind: .max, isBuiltIn: true),
    ]

    public static var balanced: Preset { builtIns.first { $0.id == balancedID }! }

    /// Bản sao tùy chỉnh (id mới) để người dùng chỉnh sửa.
    public func duplicated() -> Preset {
        Preset(id: UUID().uuidString, name: "\(name) (bản sao)", kind: .curve, curve: curve, isBuiltIn: false)
    }
}
