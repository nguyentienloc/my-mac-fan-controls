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

    @Test func formatsDecimalWithComma() {
        #expect(Format.decimal(11.2, digits: 1) == "11,2")
        #expect(Format.decimal(16.0, digits: 1) == "16")
        #expect(Format.decimal(181.6, digits: 0) == "182")
    }

    @Test func formatsMemoryInBinaryGigabytes() {
        #expect(Format.memory(12_025_908_428) == "11,2 GB")
        #expect(Format.memory(17_179_869_184) == "16 GB")
    }

    @Test func formatsDiskInDecimalUnits() {
        #expect(Format.disk(182_400_000_000) == "182 GB")
        #expect(Format.disk(494_384_795_648) == "494 GB")
        #expect(Format.disk(1_234_000_000_000) == "1,2 TB")
    }

    @Test func formatsNetworkRate() {
        #expect(Format.rate(nil) == "--")
        #expect(Format.rate(.nan) == "--")
        #expect(Format.rate(850) == "850 B/s")
        #expect(Format.rate(85_000) == "85 KB/s")
        #expect(Format.rate(1_234_567) == "1,2 MB/s")
    }

    @Test func formatsPercent() {
        #expect(Format.percent(23.4) == "23%")
        #expect(Format.percent(nil) == "--%")
        #expect(Format.percent(.infinity) == "--%")
    }

    @Test func roundsAcrossUnitBoundaries() {
        #expect(Format.rate(999) == "999 B/s")
        #expect(Format.rate(999.6) == "1 KB/s")
        #expect(Format.rate(999_600) == "1 MB/s")
        #expect(Format.rate(1_000_000) == "1 MB/s")
        #expect(Format.disk(999_600_000_000) == "1 TB")
        #expect(Format.disk(1_000_000_000_000) == "1 TB")
        #expect(Format.disk(0) == "0 GB")
        #expect(Format.memory(0) == "0 GB")
    }

    @Test func decimalGroupsAndHandlesNonFinite() {
        #expect(Format.decimal(1234.5, digits: 1) == "1.234,5")
        #expect(Format.decimal(.nan, digits: 1) == "--")
        #expect(Format.decimal(.infinity, digits: 1) == "--")
    }
}
