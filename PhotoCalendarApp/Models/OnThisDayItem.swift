import Foundation

struct OnThisDayItem: Identifiable, Hashable {
    let date: Date
    let asset: PhotoAssetItem
    let isRepresentative: Bool

    private static let englishDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d, EEE"
        return formatter
    }()

    var id: String { "\(DayKeyFormatter.dayString(from: date))-\(asset.id)" }

    var yearText: String {
        String(Calendar.current.component(.year, from: date))
    }

    var englishDateText: String {
        Self.englishDateFormatter.string(from: date)
    }
}
