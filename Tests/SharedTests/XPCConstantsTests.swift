import Security
import Testing
@testable import Shared

struct XPCConstantsTests {
    @Test func clientRequirementCompiles() {
        var requirement: SecRequirement?
        let status = SecRequirementCreateWithString(XPCConstants.clientRequirement as CFString, [], &requirement)
        #expect(status == errSecSuccess)
        #expect(requirement != nil)
    }

    @Test func clientRequirementPinsAppleSignedTeamAndIdentifier() {
        #expect(XPCConstants.clientRequirement.contains("anchor apple generic"))
        #expect(XPCConstants.clientRequirement.contains("identifier \"local.fancontrol.app\""))
        #expect(XPCConstants.clientRequirement.contains("certificate leaf[subject.OU] = \"99G56BJA4B\""))
    }
}
