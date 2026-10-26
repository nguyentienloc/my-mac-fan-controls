import Foundation
import Testing
import Shared
@testable import FanCore

struct ConfigStoreTests {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("config.json")

    @Test func missingFileCreatesDefault() throws {
        let store = ConfigStore(url: url)
        #expect(store.config == .default)
        let saved = try JSONDecoder().decode(Config.self, from: Data(contentsOf: url))
        #expect(saved == .default)
    }

    @Test func corruptFileIsReplacedWithDefault() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("không phải json".utf8).write(to: url)
        let store = ConfigStore(url: url)
        #expect(store.config == .default)
        #expect(try JSONDecoder().decode(Config.self, from: Data(contentsOf: url)) == .default)
    }

    @Test func updatePersistsAcrossInstances() throws {
        try ConfigStore(url: url).update { try $0.setActive(Preset.maxID) }
        #expect(ConfigStore(url: url).config.activePresetID == Preset.maxID)
    }

    @Test func failedUpdateLeavesConfigUnchanged() throws {
        let store = ConfigStore(url: url)
        #expect(throws: Config.EditError.unknownPreset) { try store.update { try $0.setActive("nope") } }
        #expect(store.config == .default)
        #expect(ConfigStore(url: url).config == .default)
    }

    @Test func failedSaveLeavesConfigUnchanged() throws {
        let store = ConfigStore(url: url)
        // Thư mục cha bị thay bằng file thường → không thể tạo/ghi config.json.
        try FileManager.default.removeItem(at: url.deletingLastPathComponent())
        try Data().write(to: url.deletingLastPathComponent())
        #expect(throws: (any Error).self) { try store.update { try $0.setActive(Preset.maxID) } }
        #expect(store.config == .default)
    }
}
