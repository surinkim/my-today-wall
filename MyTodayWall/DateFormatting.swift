import Foundation

extension Date {
    private static let bingFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }()

    /// "yyyyMMdd", the same format as Bing `startdate`
    var bingDateString: String { Self.bingFormatter.string(from: self) }
}

extension String {
    /// "20260926" → "Sep 26, 2026" (formatted for the user's locale)
    var bingDisplayDate: String {
        guard count == 8,
              let year = Int(prefix(4)),
              let month = Int(dropFirst(4).prefix(2)),
              let day = Int(suffix(2)),
              let date = Calendar.current.date(from: DateComponents(year: year, month: month, day: day))
        else { return self }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}
