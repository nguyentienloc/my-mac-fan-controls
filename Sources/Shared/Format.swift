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
