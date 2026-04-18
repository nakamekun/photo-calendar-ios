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

    var displayedYear: Int {
        calendar.component(.year, from: displayedMonth)
    }

    var displayedMonthNumber: Int {
        calendar.component(.month, from: displayedMonth)
    }

    var currentYear: Int {
        calendar.component(.year, from: .now)
    }

    var currentMonthNumber: Int {
        calendar.component(.month, from: .now)
    }

    var selectableYears: [Int] {
        Array(stride(from: currentYear, through: 2000, by: -1))
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

    func canSelect(year: Int, month: Int) -> Bool {
        let selected = calendar.date(from: DateComponents(year: year, month: month, day: 1))
        let current = calendar.date(from: DateComponents(year: currentYear, month: currentMonthNumber, day: 1))
        guard let selected, let current else { return false }
        return selected <= current
    }

    func setDisplayedMonth(year: Int, month: Int) {
        guard canSelect(year: year, month: month) else { return }
        displayedMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? displayedMonth
    }
}
