import Foundation

public struct Config: Codable, Equatable, Sendable {
    public var activePresetID: String
    public var customPresets: [Preset]

    public init(activePresetID: String = Preset.balancedID, customPresets: [Preset] = []) {
        self.activePresetID = activePresetID
        self.customPresets = customPresets
    }

    public static let `default` = Config()

    public var allPresets: [Preset] { Preset.builtIns + customPresets }

    public var activePreset: Preset {
        allPresets.first { $0.id == activePresetID } ?? Preset.balanced
    }

    public enum EditError: Error, Equatable, Sendable {
        case unknownPreset
        case builtInReadOnly
        case emptyName
        case notACurve
        case invalidCurve(FanCurve.ValidationError)

        public var message: String {
            switch self {
            case .unknownPreset: return "Không tìm thấy chế độ này"
            case .builtInReadOnly: return "Chế độ có sẵn không thể sửa hoặc xóa"
            case .emptyName: return "Tên không được để trống"
            case .notACurve: return "Chế độ tùy chỉnh phải là đường cong"
            case .invalidCurve(let error): return error.message
            }
        }
    }

    public mutating func setActive(_ id: String) throws {
        guard allPresets.contains(where: { $0.id == id }) else { throw EditError.unknownPreset }
        activePresetID = id
    }

    /// Thêm mới hoặc cập nhật một chế độ tùy chỉnh.
    public mutating func upsert(_ preset: Preset) throws {
        if preset.isBuiltIn || Preset.builtIns.contains(where: { $0.id == preset.id }) {
            throw EditError.builtInReadOnly
        }
        if preset.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw EditError.emptyName }
        guard preset.kind == .curve else { throw EditError.notACurve }
        if let error = preset.curve.validate() { throw EditError.invalidCurve(error) }

        if let index = customPresets.firstIndex(where: { $0.id == preset.id }) {
            customPresets[index] = preset
        } else {
            customPresets.append(preset)
        }
    }

    public mutating func delete(_ id: String) throws {
        if Preset.builtIns.contains(where: { $0.id == id }) { throw EditError.builtInReadOnly }
        guard let index = customPresets.firstIndex(where: { $0.id == id }) else { throw EditError.unknownPreset }
        customPresets.remove(at: index)
        if activePresetID == id { activePresetID = Preset.balancedID }
    }
}
