import Foundation

/// Lệnh shell cài/gỡ daemon, chạy qua AppleScript với quyền admin.
public enum HelperScripts {
    public static let label = XPCConstants.machServiceName
    public static let helperPath = "/Library/PrivilegedHelperTools/fanctld"
    public static let plistPath = "/Library/LaunchDaemons/local.fancontrol.daemon.plist"

    public static func install(bundledHelper: String, bundledPlist: String) -> String {
        // Gỡ bản cũ (nếu có) rồi chờ launchd dọn xong trước khi nạp lại
        "launchctl bootout system/\(label) 2>/dev/null; sleep 1; " + [
            "mkdir -p /Library/PrivilegedHelperTools",
            "cp \(quote(bundledHelper)) \(quote(helperPath))",
            "chown root:wheel \(quote(helperPath))",
            "chmod 755 \(quote(helperPath))",
            "cp \(quote(bundledPlist)) \(quote(plistPath))",
            "chown root:wheel \(quote(plistPath))",
            "chmod 644 \(quote(plistPath))",
            "launchctl bootstrap system \(quote(plistPath))",
        ].joined(separator: " && ")
    }

    /// bootout gửi SIGTERM → daemon trả quạt về Apple rồi thoát.
    public static func uninstall() -> String {
        "launchctl bootout system/\(label) 2>/dev/null; rm -f \(quote(helperPath)) \(quote(plistPath))"
    }

    /// Bọc chuỗi trong dấu nháy đơn cho sh.
    public static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    public static func appleScript(running script: String) -> String {
        let escaped = script
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "do shell script \"\(escaped)\" with administrator privileges"
    }
}
