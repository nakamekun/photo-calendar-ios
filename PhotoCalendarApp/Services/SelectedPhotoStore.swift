import Foundation

enum DaySelectionSource: String, Codable, Hashable {
    case automatic
    case manual
}

struct CachedDaySelection: Codable, Hashable {
    let representativeIdentifier: String
    let latestAssetIdentifier: String
    let latestAssetCreationDate: Date?
    let source: DaySelectionSource
    let updatedAt: Date
}

protocol SelectedPhotoStoring {
    var selections: [String: String] { get }
    var currentStreak: Int { get }
    var lastSelectedDate: Date? { get }
    func representativeIdentifier(for date: Date) -> String?
    func cachedSelection(for date: Date) -> CachedDaySelection?
    func cachedSelections() -> [String: CachedDaySelection]
    func excludedIdentifiers(for date: Date) -> Set<String>
    func cachedExcludedIdentifiers() -> [String: Set<String>]
    func excludeIdentifier(_ identifier: String, for date: Date)
    func cachedAutoPickResolvedDates() -> Set<String>
    func setAutoPickResolved(_ isResolved: Bool, for date: Date)
    func setCachedSelection(_ selection: CachedDaySelection, for date: Date)
    func removeRepresentativeIdentifier(for date: Date)
    func resetAllRepresentativeSelections()
}

final class SelectedPhotoStore: SelectedPhotoStoring {
    private let userDefaults: UserDefaults
    private let storageKey = "selected-photo-by-day-v2"
    private let excludedStorageKey = "excluded-photo-identifiers-by-day-v1_1"
    private let autoPickResolvedStorageKey = "auto-pick-resolved-days-v1"
    private let legacyStorageKey = "selected-photo-by-day"
    private let streakKey = "current-photo-streak"
    private let lastSelectedDateKey = "last-selected-photo-date"
    private let calendar = Calendar.current
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(userDefaults: UserDefaults = .standard) {
        if userDefaults === UserDefaults.standard,
           let sharedDefaults = UserDefaults(suiteName: AppSharedConfiguration.appGroupIdentifier) {
            self.userDefaults = sharedDefaults
            migrateStandardDefaultsIfNeeded(to: sharedDefaults)
        } else {
            self.userDefaults = userDefaults
        }
    }

    var selections: [String: String] {
        cachedSelections().mapValues(\.representativeIdentifier)
    }

    var currentStreak: Int {
        userDefaults.integer(forKey: streakKey)
    }

    var lastSelectedDate: Date? {
        userDefaults.object(forKey: lastSelectedDateKey) as? Date
    }

    func representativeIdentifier(for date: Date) -> String? {
        cachedSelection(for: date)?.representativeIdentifier
    }

    func cachedSelection(for date: Date) -> CachedDaySelection? {
        cachedSelections()[DayKeyFormatter.dayString(from: date)]
    }

    func cachedSelections() -> [String: CachedDaySelection] {
        if let data = userDefaults.data(forKey: storageKey),
           let decoded = try? decoder.decode([String: CachedDaySelection].self, from: data) {
            return decoded
        }

        let legacy = userDefaults.dictionary(forKey: legacyStorageKey) as? [String: String] ?? [:]
        guard legacy.isEmpty == false else { return [:] }

        let migrated = legacy.reduce(into: [String: CachedDaySelection]()) { partialResult, entry in
            partialResult[entry.key] = CachedDaySelection(
                representativeIdentifier: entry.value,
                latestAssetIdentifier: entry.value,
                latestAssetCreationDate: nil,
                source: .manual,
                updatedAt: .now
            )
        }

        persist(migrated)
        userDefaults.removeObject(forKey: legacyStorageKey)
        return migrated
    }

    func excludedIdentifiers(for date: Date) -> Set<String> {
        cachedExcludedIdentifiers()[DayKeyFormatter.dayString(from: date)] ?? []
    }

    func cachedExcludedIdentifiers() -> [String: Set<String>] {
        guard let data = userDefaults.data(forKey: excludedStorageKey),
              let decoded = try? decoder.decode([String: [String]].self, from: data) else {
            return [:]
        }

        return decoded.reduce(into: [String: Set<String>]()) { partialResult, entry in
            partialResult[entry.key] = Set(entry.value)
        }
    }

    func excludeIdentifier(_ identifier: String, for date: Date) {
        let key = DayKeyFormatter.dayString(from: date)
        var updated = cachedExcludedIdentifiers()
        var identifiers = updated[key] ?? []
        identifiers.insert(identifier)
        updated[key] = identifiers
        persistExcludedIdentifiers(updated)
    }

    func cachedAutoPickResolvedDates() -> Set<String> {
        guard let stored = userDefaults.array(forKey: autoPickResolvedStorageKey) as? [String] else {
            return []
        }

        return Set(stored)
    }

    func setAutoPickResolved(_ isResolved: Bool, for date: Date) {
        let key = DayKeyFormatter.dayString(from: date)
        var updated = cachedAutoPickResolvedDates()

        if isResolved {
            updated.insert(key)
        } else {
            updated.remove(key)
        }

        userDefaults.set(Array(updated).sorted(), forKey: autoPickResolvedStorageKey)
    }

    func setCachedSelection(_ selection: CachedDaySelection, for date: Date) {
        updateStreak(for: date)

        var updated = cachedSelections()
        updated[DayKeyFormatter.dayString(from: date)] = selection
        persist(updated)
    }

    func removeRepresentativeIdentifier(for date: Date) {
        var updated = cachedSelections()
        updated.removeValue(forKey: DayKeyFormatter.dayString(from: date))
        persist(updated)
    }

    func resetAllRepresentativeSelections() {
        userDefaults.removeObject(forKey: storageKey)
        userDefaults.removeObject(forKey: legacyStorageKey)
        userDefaults.removeObject(forKey: streakKey)
        userDefaults.removeObject(forKey: lastSelectedDateKey)
        userDefaults.removeObject(forKey: autoPickResolvedStorageKey)
    }

    private func persist(_ selections: [String: CachedDaySelection]) {
        guard let data = try? encoder.encode(selections) else { return }
        userDefaults.set(data, forKey: storageKey)
    }

    private func persistExcludedIdentifiers(_ exclusions: [String: Set<String>]) {
        let serializable = exclusions.reduce(into: [String: [String]]()) { partialResult, entry in
            partialResult[entry.key] = Array(entry.value).sorted()
        }

        guard let data = try? encoder.encode(serializable) else { return }
        userDefaults.set(data, forKey: excludedStorageKey)
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

    private func migrateStandardDefaultsIfNeeded(to sharedDefaults: UserDefaults) {
        let migrationKey = "selected-photo-store-app-group-migrated-v1"
        guard sharedDefaults.bool(forKey: migrationKey) == false else { return }

        let standardDefaults = UserDefaults.standard
        [
            storageKey,
            excludedStorageKey,
            autoPickResolvedStorageKey,
            legacyStorageKey,
            streakKey,
            lastSelectedDateKey,
        ].forEach { key in
            guard sharedDefaults.object(forKey: key) == nil,
                  let value = standardDefaults.object(forKey: key)
            else {
                return
            }

            sharedDefaults.set(value, forKey: key)
        }

        sharedDefaults.set(true, forKey: migrationKey)
    }
}
