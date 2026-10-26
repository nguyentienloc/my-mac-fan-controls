import Testing
@testable import Shared

struct FormatTests {
    @Test func groupsThousandsWithDots() {
        #expect(Format.grouped(0) == "0")
        #expect(Format.grouped(999) == "999")
        #expect(Format.grouped(2450) == "2.450")
        #expect(Format.grouped(12345) == "12.345")
        #expect(Format.grouped(1234567) == "1.234.567")
    }

    @Test func formatsRPM() {
        #expect(Format.rpm(2449.6) == "2.450 vòng/phút")
    }

    @Test func formatsTemperature() {
        #expect(Format.temperature(58.4) == "58°C")
        #expect(Format.temperature(nil) == "--°C")
        #expect(Format.shortTemperature(58.6) == "59°")
        #expect(Format.shortTemperature(nil) == "--°")
    }
}
