import Foundation
import Shared

/// Cài/gỡ daemon bằng AppleScript `with administrator privileges` (macOS hỏi mật khẩu).
enum HelperInstaller {
    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: HelperScripts.plistPath)
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
        var error: NSDictionary?
        NSAppleScript(source: HelperScripts.appleScript(running: script))?.executeAndReturnError(&error)
        if let error {
            let message = error[NSAppleScript.errorMessage] as? String ?? "Lỗi không xác định"
            throw DaemonError.rejected(message)
        }
    }
}
