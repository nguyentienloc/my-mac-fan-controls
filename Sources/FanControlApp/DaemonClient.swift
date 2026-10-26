import Foundation
import Shared

enum DaemonError: LocalizedError {
    case rejected(String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .rejected(let message): return message
        case .badResponse: return "Phản hồi không hợp lệ từ helper"
        }
    }
}

/// Client XPC tới daemon. Kết nối tự tạo lại khi bị invalidate (daemon khởi động lại).
@MainActor
final class DaemonClient {
    private var connection: NSXPCConnection?

    func status() async throws -> Status {
        let data: Data = try await call { proxy, done in proxy.getStatus { done(.success($0)) } }
        guard let status = try? JSONDecoder().decode(Status.self, from: data) else { throw DaemonError.badResponse }
        return status
    }

    func setMode(_ presetID: String) async throws {
        try await mutation { proxy, reply in proxy.setMode(presetID, reply: reply) }
    }

    func savePreset(_ preset: Preset) async throws {
        let data = try JSONEncoder().encode(preset)
        try await mutation { proxy, reply in proxy.savePreset(data, reply: reply) }
    }

    func deletePreset(_ presetID: String) async throws {
        try await mutation { proxy, reply in proxy.deletePreset(presetID, reply: reply) }
    }

    private func mutation(_ body: (FanDaemonProtocol, @escaping (String?) -> Void) -> Void) async throws {
        let message: String? = try await call { proxy, done in body(proxy) { done(.success($0)) } }
        if let message { throw DaemonError.rejected(message) }
    }

    /// XPC đảm bảo chỉ gọi một trong hai: reply hoặc error handler.
    private func call<T>(_ body: (FanDaemonProtocol, @escaping (Result<T, Error>) -> Void) -> Void) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            guard let proxy = makeProxy(onError: { continuation.resume(throwing: $0) }) else {
                continuation.resume(throwing: DaemonError.badResponse)
                return
            }
            body(proxy) { continuation.resume(with: $0) }
        }
    }

    private func makeProxy(onError: @escaping (Error) -> Void) -> FanDaemonProtocol? {
        if connection == nil {
            let newConnection = NSXPCConnection(machServiceName: XPCConstants.machServiceName, options: .privileged)
            newConnection.remoteObjectInterface = NSXPCInterface(with: FanDaemonProtocol.self)
            newConnection.invalidationHandler = { [weak self] in
                Task { @MainActor in self?.connection = nil }
            }
            newConnection.resume()
            connection = newConnection
        }
        return connection?.remoteObjectProxyWithErrorHandler(onError) as? FanDaemonProtocol
    }
}
