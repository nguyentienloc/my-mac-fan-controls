import Foundation

public enum XPCConstants {
    public static let machServiceName = "local.fancontrol.daemon"
    public static let teamID = "99G56BJA4B"
    /// Yêu cầu chữ ký của client XPC: chỉ nhận app do Apple cấp chứng chỉ (Developer ID)
    /// đúng team và đúng identifier. Bản build ký ad-hoc sẽ bị daemon từ chối.
    public static let clientRequirement =
        "anchor apple generic and identifier \"local.fancontrol.app\" and certificate leaf[subject.OU] = \"\(teamID)\""
}

/// Giao tiếp app ↔ daemon. Model truyền dưới dạng JSON `Data`;
/// các hàm sửa trả về chuỗi lỗi tiếng Việt, `nil` nghĩa là thành công.
@objc public protocol FanDaemonProtocol {
    func getStatus(reply: @escaping (Data) -> Void)
    func setMode(_ presetID: String, reply: @escaping (String?) -> Void)
    func savePreset(_ presetJSON: Data, reply: @escaping (String?) -> Void)
    func deletePreset(_ presetID: String, reply: @escaping (String?) -> Void)
}
