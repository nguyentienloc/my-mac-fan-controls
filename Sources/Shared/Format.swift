import Foundation

/// Định dạng số kiểu Việt (dấu chấm phân cách hàng nghìn), không phụ thuộc locale máy.
public enum Format {
    /// 2450 → "2.450 vòng/phút"
    public static func rpm(_ value: Double) -> String {
        "\(grouped(Int(value.rounded()))) vòng/phút"
    }

    /// 58.4 → "58°C"; nil → "--°C"
    public static func temperature(_ value: Double?) -> String {
        value.map { "\(Int($0.rounded()))°C" } ?? "--°C"
    }

    /// Dùng trên thanh menu: 58.6 → "59°"; nil → "--°"
    public static func shortTemperature(_ value: Double?) -> String {
        value.map { "\(Int($0.rounded()))°" } ?? "--°"
    }

    /// RAM theo hệ 1024 như Activity Monitor: 12_025_908_428 → "11,2 GB"; 16 GiB → "16 GB".
    public static func memory(_ bytes: UInt64) -> String {
        "\(decimal(Double(bytes) / 1_073_741_824, digits: 1)) GB"
    }

    /// Ổ đĩa theo hệ 1000 như Finder: 182_400_000_000 → "182 GB"; từ 1000 GB → "1,2 TB".
    public static func disk(_ bytes: UInt64) -> String {
        let gigabytes = Double(bytes) / 1_000_000_000
        if gigabytes >= 1000 { return "\(decimal(gigabytes / 1000, digits: 1)) TB" }
        return "\(decimal(gigabytes, digits: 0)) GB"
    }

    /// Tốc độ mạng theo hệ 1000: "850 B/s", "85 KB/s", "1,2 MB/s"; nil → "--".
    public static func rate(_ bytesPerSecond: Double?) -> String {
        guard let value = bytesPerSecond, value.isFinite, value >= 0 else { return "--" }
        if value < 1000 { return "\(Int(value.rounded())) B/s" }
        if value < 1_000_000 { return "\(Int((value / 1000).rounded())) KB/s" }
        return "\(decimal(value / 1_000_000, digits: 1)) MB/s"
    }

    /// 23.4 → "23%"; nil → "--%".
    public static func percent(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "--%" }
        return "\(Int(value.rounded()))%"
    }

    /// Làm tròn `digits` chữ số thập phân, dấu phẩy kiểu Việt, bỏ phần ",0".
    static func decimal(_ value: Double, digits: Int) -> String {
        let factor = pow(10, Double(digits))
        let rounded = (value * factor).rounded() / factor
        if rounded == rounded.rounded() { return grouped(Int(rounded)) }
        return String(format: "%.\(digits)f", rounded).replacingOccurrences(of: ".", with: ",")
    }

    static func grouped(_ number: Int) -> String {
        let digits = String(abs(number))
        var result = ""
        for (offset, character) in digits.enumerated() {
            if offset > 0 && (digits.count - offset) % 3 == 0 { result.append(".") }
            result.append(character)
        }
        return number < 0 ? "-" + result : result
    }
}
