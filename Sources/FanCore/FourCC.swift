/// "F0Ac" → 0x46304163 (mã 4 ký tự big-endian mà SMC dùng làm key và kiểu dữ liệu).
func fourCC(_ string: String) -> UInt32 {
    string.utf8.prefix(4).reduce(0) { $0 << 8 | UInt32($1) }
}

func fourCCString(_ value: UInt32) -> String {
    String(decoding: [24, 16, 8, 0].map { UInt8((value >> $0) & 0xFF) }, as: UTF8.self)
}
