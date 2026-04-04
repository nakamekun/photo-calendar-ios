import Foundation

protocol SelectedPhotoStoring {
    var selections: [String: String] { get }
    var currentStreak: Int { get }
    var lastSelectedDate: Date? { get }
    func representativeIdentifier(for date: Date) -> String?
    func setRepresentativeIdentifier(_ identifier: String, for date: Date)
    func removeRepresentativeIdentifier(for date: Date)
}

final class SelectedPhotoStore: SelectedPhotoStoring {
    private let userDefaults: UserDefaults
    private let storageKey = "selected-photo-by-day"
    private let streakKey = "current-photo-streak"
    private let lastSelectedDateKey = "last-selected-photo-date"
    private let calendar = Calendar.current

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var selections: [String: String] {
        userDefaults.dictionary(forKey: storageKey) as? [String: String] ?? [:]
    }

    var currentStreak: Int {
        userDefaults.integer(forKey: streakKey)
    }

    var lastSelectedDate: Date? {
        userDefaults.object(forKey: lastSelectedDateKey) as? Date
    }

    func representativeIdentifier(for date: Date) -> String? {
        selections[DayKeyFormatter.dayString(from: date)]
    }

    func setRepresentativeIdentifier(_ identifier: String, for date: Date) {
        updateStreak(for: date)

        var updated = selections
        updated[DayKeyFormatter.dayString(from: date)] = identifier
        userDefaults.set(updated, forKey: storageKey)
    }

    func removeRepresentativeIdentifier(for date: Date) {
        var updated = selections
        updated.removeValue(forKey: DayKeyFormatter.dayString(from: date))
        userDefaults.set(updated, forKey: storageKey)
    }

    private func updateStreak(for date: Date) {
        let selectedDay = calendar.startOfDay(for: date)

        guard calendar.isDateInToday(selectedDay) else { return }

        if let lastSelectedDate {
            let lastDay = calendar.startOfDay(for: lastSelectedDate)

            if calendar.isDate(lastDay, inSameDayAs: selectedDay) {
                return
            }

            if let yesterday = calendar.date(byAdding: .day, value: -1, to: selectedDay),
               calendar.isDate(lastDay, inSameDayAs: yesterday) {
                userDefaults.set(max(currentStreak, 0) + 1, forKey: streakKey)
            } else {
                userDefaults.set(1, forKey: streakKey)
            }
        } else {
            userDefaults.set(1, forKey: streakKey)
        }

        userDefaults.set(selectedDay, forKey: lastSelectedDateKey)
    }
}
