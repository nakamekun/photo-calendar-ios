import Foundation

@MainActor
final class CalendarViewModel: ObservableObject {
    @Published private(set) var displayedMonth: Date

    private let calendar: Calendar
    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()

    init(calendar: Calendar = .current, referenceDate: Date = .now) {
        self.calendar = calendar
        let components = calendar.dateComponents([.year, .month], from: referenceDate)
        self.displayedMonth = calendar.date(from: components) ?? referenceDate
    }

    var monthTitle: String {
        Self.monthFormatter.string(from: displayedMonth)
    }

    var isCurrentMonth: Bool {
        calendar.isDate(displayedMonth, equalTo: .now, toGranularity: .month)
    }

    var canShowNextMonth: Bool {
        isCurrentMonth == false
    }

    func showPreviousMonth() {
        displayedMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
    }

    func showNextMonth() {
        guard canShowNextMonth else { return }
        displayedMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
    }

    func jumpToToday() {
        let components = calendar.dateComponents([.year, .month], from: Date())
        displayedMonth = calendar.date(from: components) ?? displayedMonth
    }
}
