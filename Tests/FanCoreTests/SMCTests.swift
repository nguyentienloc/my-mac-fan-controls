import Foundation
import Testing
@testable import FanCore

struct SMCTests {
    @Test func paramStructMatchesCLayout() {
        #expect(MemoryLayout<SMCParamStruct>.stride == 80)
        #expect(MemoryLayout<SMCParamStruct>.offset(of: \.keyInfo) == 28)
        #expect(MemoryLayout<SMCParamStruct>.offset(of: \.result) == 40)
        #expect(MemoryLayout<SMCParamStruct>.offset(of: \.data32) == 44)
        #expect(MemoryLayout<SMCParamStruct>.offset(of: \.bytes) == 48)
    }

    @Test func fourCCRoundTrips() {
        #expect(fourCC("F0Ac") == 0x4630_4163)
        #expect(fourCCString(0x4630_4163) == "F0Ac")
        #expect(fourCCString(fourCC("flt ")) == "flt ")
    }

    @Test func floatRoundTripsThroughDevice() throws {
        let smc = MockSMC.m1Pro()
        try smc.writeFloat("F0Tg", 2450.5)
        #expect(try smc.readFloat("F0Tg") == 2450.5)
    }

    @Test func uint8RoundTripsThroughDevice() throws {
        let smc = MockSMC.m1Pro()
        try smc.writeUInt8("F0Md", 1)
        #expect(try smc.readUInt8("F0Md") == 1)
    }

    @Test func typedReadRejectsWrongType() {
        let smc = MockSMC.m1Pro()
        #expect(throws: SMCError.typeMismatch(key: "F0Md", expected: "flt ", actual: "ui8 ")) {
            try smc.readFloat("F0Md")
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["FANCTL_HW"] == "1"))
    func readsRealSMC() throws {
        let smc = try AppleSMC()
        #expect(try smc.readUInt8("FNum") >= 1)
        #expect(try smc.readFloat("F0Mx") > 1000)
        #expect(try smc.allKeys().contains("F0Ac"))
    }
}
