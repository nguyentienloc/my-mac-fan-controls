import Foundation
import Shared

/// Đọc/ghi config.json. File thiếu hoặc hỏng → dùng mặc định và ghi đè.
public final class ConfigStore {
    public let url: URL
    public private(set) var config: Config

    public init(url: URL) {
        self.url = url
        if let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode(Config.self, from: data) {
            config = decoded
        } else {
            config = .default
            try? save(config)
        }
    }

    /// Chỉ giữ thay đổi khi `mutate` và việc lưu đều thành công; lỗi lưu thì `config` không đổi.
    public func update(_ mutate: (inout Config) throws -> Void) throws {
        var copy = config
        try mutate(&copy)
        try save(copy)
        config = copy
    }

    private func save(_ config: Config) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(config).write(to: url, options: .atomic)
    }
}
