import Foundation

public enum XPCConstants {
    public static let machServiceName = "local.fancontrol.daemon"
}

/// Giao tiếp app ↔ daemon. Model truyền dưới dạng JSON `Data`;
/// các hàm sửa trả về chuỗi lỗi tiếng Việt, `nil` nghĩa là thành công.
@objc public protocol FanDaemonProtocol {
    func getStatus(reply: @escaping (Data) -> Void)
    func setMode(_ presetID: String, reply: @escaping (String?) -> Void)
    func savePreset(_ presetJSON: Data, reply: @escaping (String?) -> Void)
    func deletePreset(_ presetID: String, reply: @escaping (String?) -> Void)
}
