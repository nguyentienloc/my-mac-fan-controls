import Foundation
import FanCore
import Shared

/// Đối tượng XPC. Mọi thao tác chạy trên queue của vòng điều khiển để không đua với `tick()`.
final class DaemonService: NSObject, NSXPCListenerDelegate, FanDaemonProtocol {
    private let queue: DispatchQueue
    private let loop: ControlLoop
    private let store: ConfigStore
    private let log: (String) -> Void

    init(queue: DispatchQueue, loop: ControlLoop, store: ConfigStore, log: @escaping (String) -> Void) {
        self.queue = queue
        self.loop = loop
        self.store = store
        self.log = log
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: FanDaemonProtocol.self)
        connection.exportedObject = self
        connection.resume()
        return true
    }

    func getStatus(reply: @escaping (Data) -> Void) {
        queue.async {
            reply((try? JSONEncoder().encode(self.loop.status)) ?? Data())
        }
    }

    func setMode(_ presetID: String, reply: @escaping (String?) -> Void) {
        edit(reply) { try $0.setActive(presetID) }
    }

    func savePreset(_ presetJSON: Data, reply: @escaping (String?) -> Void) {
        guard let preset = try? JSONDecoder().decode(Preset.self, from: presetJSON) else {
            reply("Dữ liệu chế độ không hợp lệ")
            return
        }
        edit(reply) { try $0.upsert(preset) }
    }

    func deletePreset(_ presetID: String, reply: @escaping (String?) -> Void) {
        edit(reply) { try $0.delete(presetID) }
    }

    private func edit(_ reply: @escaping (String?) -> Void, _ mutate: @escaping (inout Config) throws -> Void) {
        queue.async {
            do {
                try self.store.update(mutate)
                self.loop.tick() // áp dụng ngay, không đợi chu kỳ sau
                reply(nil)
            } catch let error as Config.EditError {
                reply(error.message)
            } catch {
                self.log("Lỗi lưu cấu hình: \(error)")
                reply("Không lưu được cấu hình")
            }
        }
    }
}
