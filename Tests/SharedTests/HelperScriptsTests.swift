import Testing
@testable import Shared

struct HelperScriptsTests {
    @Test func quotesForShell() {
        #expect(HelperScripts.quote("/a b/c") == "'/a b/c'")
        #expect(HelperScripts.quote("it's") == "'it'\\''s'")
    }

    @Test func installScriptCopiesAndBootstraps() {
        let script = HelperScripts.install(bundledHelper: "/Apps/Fan Control.app/fanctld", bundledPlist: "/Apps/p.plist")
        #expect(script.hasPrefix("launchctl bootout system/local.fancontrol.daemon 2>/dev/null; sleep 1; "))
        #expect(script.contains("cp '/Apps/Fan Control.app/fanctld' '/Library/PrivilegedHelperTools/fanctld' && "))
        #expect(script.contains("chown root:wheel '/Library/LaunchDaemons/local.fancontrol.daemon.plist'"))
        #expect(script.hasSuffix("launchctl bootstrap system '/Library/LaunchDaemons/local.fancontrol.daemon.plist'"))
    }

    @Test func uninstallScriptBootsOutAndRemoves() {
        #expect(HelperScripts.uninstall() ==
            "launchctl bootout system/local.fancontrol.daemon 2>/dev/null; rm -f '/Library/PrivilegedHelperTools/fanctld' '/Library/LaunchDaemons/local.fancontrol.daemon.plist'")
    }

    @Test func appleScriptEscapesQuotesAndBackslashes() {
        #expect(HelperScripts.appleScript(running: #"echo "a\b""#) ==
            #"do shell script "echo \"a\\b\"" with administrator privileges"#)
    }
}
