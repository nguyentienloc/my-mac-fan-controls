import Foundation
import Shared

/// Cài/gỡ daemon bằng AppleScript `with administrator privileges` (macOS hỏi mật khẩu).
enum HelperInstaller {
    static var isInstalled: Bool {
        let fileManager = FileManager.default
        return fileManager.fileExists(atPath: HelperScripts.plistPath)
            && fileManager.fileExists(atPath: HelperScripts.helperPath)
    }

    static func install() throws {
        guard let helper = Bundle.main.path(forResource: "fanctld", ofType: nil),
              let plist = Bundle.main.path(forResource: "local.fancontrol.daemon", ofType: "plist") else {
            throw DaemonError.rejected("Không tìm thấy fanctld trong app. Hãy build bằng `make app`.")
        }
        try runAsAdmin(HelperScripts.install(bundledHelper: helper, bundledPlist: plist))
    }

    static func uninstall() throws {
        try runAsAdmin(HelperScripts.uninstall())
    }

    private static func runAsAdmin(_ script: String) throws {
        guard let appleScript = NSAppleScript(source: HelperScripts.appleScript(running: script)) else {
            throw DaemonError.rejected("Không tạo được lệnh cài đặt")
        }
        var error: NSDictionary?
        appleScript.executeAndReturnError(&error)
        if let error {
            // -128: người dùng bấm Hủy ở hộp thoại mật khẩu
            if error[NSAppleScript.errorNumber] as? Int == -128 { throw DaemonError.cancelled }
            let message = error[NSAppleScript.errorMessage] as? String ?? "Lỗi không xác định"
            throw DaemonError.rejected("Không chạy được lệnh cài đặt: \(message)")
        }
    }
}
