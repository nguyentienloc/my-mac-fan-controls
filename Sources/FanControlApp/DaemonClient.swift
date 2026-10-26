import Foundation
import Shared

enum DaemonError: LocalizedError {
    case rejected(String)
    case badResponse
    case timeout
    /// Người dùng huỷ hộp thoại mật khẩu admin — không phải lỗi.
    case cancelled

    var errorDescription: String? {
        switch self {
        case .timeout: return "Helper không phản hồi"
        case .cancelled: return "Đã huỷ"
        case .rejected(let message): return message
        case .badResponse: return "Phản hồi không hợp lệ từ helper"
        }
    }
}

/// Đảm bảo continuation chỉ được resume đúng một lần (reply, error handler và timeout có thể tranh nhau).
private final class OnceBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    private let continuation: CheckedContinuation<T, Error>

    init(_ continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    /// Trả true nếu lần gọi này là lần đầu (và đã resume).
    @discardableResult
    func resume(with result: Result<T, Error>) -> Bool {
        lock.lock()
        let first = !done
        done = true
        lock.unlock()
        if first { continuation.resume(with: result) }
        return first
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

    /// Reply, error handler và timeout (5 giây) đều đi qua OnceBox nên continuation chỉ resume một lần.
    private func call<T>(_ body: (FanDaemonProtocol, @escaping (Result<T, Error>) -> Void) -> Void) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            let once = OnceBox<T>(continuation)
            guard let proxy = makeProxy(onError: { once.resume(with: .failure($0)) }) else {
                once.resume(with: .failure(DaemonError.badResponse))
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) { [weak self] in
                // Chỉ huỷ kết nối khi timeout thật sự thắng, để lần gọi sau tạo kết nối mới
                guard once.resume(with: .failure(DaemonError.timeout)) else { return }
                Task { @MainActor in
                    self?.connection?.invalidate()
                    self?.connection = nil
                }
            }
            body(proxy) { once.resume(with: $0) }
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
