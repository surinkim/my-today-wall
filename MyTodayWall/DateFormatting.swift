import Foundation

extension Date {
    private static let bingFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }()

    /// Bing `startdate`와 같은 "yyyyMMdd" 형식
    var bingDateString: String { Self.bingFormatter.string(from: self) }
}

extension String {
    /// "20260926" → "2026.09.26"
    var bingDisplayDate: String {
        guard count == 8 else { return self }
        let chars = Array(self)
        return "\(String(chars[0..<4])).\(String(chars[4..<6])).\(String(chars[6..<8]))"
    }
}
