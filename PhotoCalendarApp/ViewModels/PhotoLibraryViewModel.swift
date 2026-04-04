import Foundation
import Photos

@MainActor
final class PhotoLibraryViewModel: ObservableObject {
    @Published private(set) var authorizationState: PhotoAuthorizationState
    @Published private(set) var isLoading = false
    @Published private(set) var lastUpdated = Date()
    @Published private(set) var currentStreak: Int
    @Published private(set) var lastSelectedDate: Date?
    @Published private(set) var previewItems: [CalendarPreviewItem] = []
    @Published private(set) var onThisDayPreviewItems: [OnThisDayItem] = []
    @Published private(set) var memoryTimelinePreviewItems: [MemoryTimelineEntry] = []

    let isPreviewMode: Bool
    let isMockDataEnabled: Bool
    let showsPreviewDebugBadge: Bool

    private let photoLibraryService: PhotoLibraryServicing
    private let permissionService: PermissionServicing
    private let selectedPhotoStore: SelectedPhotoStoring
    private let calendar: Calendar
    private var hasStartedInitialLoad = false
    private var reloadTask: Task<Void, Never>?
    private var calendarDaysCache: [String: [CalendarDay]] = [:]

    private struct SamplePreviewAsset {
        let fileName: String
        let kind: MockCalendarPhoto.Kind
    }

    private static let samplePreviewAssets: [SamplePreviewAsset] = [
        SamplePreviewAsset(fileName: "Geraldine_s+Family+(Edited)-221.jpg", kind: .child),
        SamplePreviewAsset(fileName: "Vui-Choi-Ngoai-Troi.jpg", kind: .child),
        SamplePreviewAsset(fileName: "Minneapolis+lifestyle+home+newborn+photography+by+Alyssa+Lund+Photography-03.webp", kind: .dailyLife),
        SamplePreviewAsset(fileName: "i-r35H4ws-M.jpg", kind: .dailyLife),
        SamplePreviewAsset(fileName: "breakfast-snack-plate-2.webp", kind: .food),
    ]

    private(set) var assetLookup: [String: PhotoAssetItem] = [:]
    private(set) var assetsByDay: [String: [PhotoAssetItem]] = [:]
    private(set) var representativeSelections: [String: String]

    init(
        photoLibraryService: PhotoLibraryServicing = PhotoLibraryService(),
        permissionService: PermissionServicing = PermissionService(),
        selectedPhotoStore: SelectedPhotoStoring = SelectedPhotoStore(),
        isPreviewMode: Bool = false,
        isMockDataEnabled: Bool = false,
        showsPreviewDebugBadge: Bool = true,
        calendar: Calendar = .current
    ) {
        self.photoLibraryService = photoLibraryService
        self.permissionService = permissionService
        self.selectedPhotoStore = selectedPhotoStore
        self.isPreviewMode = isPreviewMode
        self.isMockDataEnabled = isPreviewMode || isMockDataEnabled
        self.showsPreviewDebugBadge = isPreviewMode && showsPreviewDebugBadge
        self.calendar = calendar
        self.authorizationState = permissionService.currentStatus()
        self.representativeSelections = selectedPhotoStore.selections
        self.currentStreak = isPreviewMode ? 11 : selectedPhotoStore.currentStreak
        self.lastSelectedDate = isPreviewMode ? calendar.startOfDay(for: .now) : selectedPhotoStore.lastSelectedDate
    }

    func refreshAuthorizationStatus() {
        authorizationState = permissionService.currentStatus()
    }

    func handleInitialLoad() {
        guard hasStartedInitialLoad == false else { return }
        hasStartedInitialLoad = true

        if isPreviewMode {
            rebuildDerivedCaches()
            lastUpdated = Date()
            return
        }

        refreshAuthorizationStatus()

        if authorizationState.canReadLibrary && assetsByDay.isEmpty {
            reloadLibrary()
        }
    }

    func requestPhotoAccess() async {
        authorizationState = await permissionService.requestAuthorization()
        if authorizationState.canReadLibrary {
            reloadLibrary()
        }
    }

    func reloadLibrary() {
        guard authorizationState.canReadLibrary else { return }
        guard isLoading == false else { return }

        reloadTask?.cancel()
        isLoading = true

        reloadTask = Task { [photoLibraryService, calendar] in
            let result = await Task.detached(priority: .userInitiated) {
                let assets = photoLibraryService.fetchAllImageAssets()
                let items = assets.map(PhotoAssetItem.init)

                var grouped: [String: [PhotoAssetItem]] = [:]
                var lookup: [String: PhotoAssetItem] = [:]
                grouped.reserveCapacity(items.count)
                lookup.reserveCapacity(items.count)

                for item in items {
                    let day = calendar.startOfDay(for: item.creationDate)
                    let key = DayKeyFormatter.dayString(from: day)
                    grouped[key, default: []].append(item)
                    lookup[item.id] = item
                }

                return (grouped, lookup)
            }.value

            guard Task.isCancelled == false else { return }

            self.assetsByDay = result.0.mapValues {
                $0.sorted { $0.creationDate < $1.creationDate }
            }
            self.assetLookup = result.1
            self.representativeSelections = sanitizedSelections()
            self.currentStreak = self.selectedPhotoStore.currentStreak
            self.lastSelectedDate = self.selectedPhotoStore.lastSelectedDate
            self.rebuildDerivedCaches()
            self.isLoading = false
            self.lastUpdated = Date()
            self.reloadTask = nil
        }
    }

    func assets(for date: Date) -> [PhotoAssetItem] {
        assetsByDay[DayKeyFormatter.dayString(from: calendar.startOfDay(for: date))] ?? []
    }

    func representativeAsset(for date: Date) -> PhotoAssetItem? {
        let key = DayKeyFormatter.dayString(from: calendar.startOfDay(for: date))
        guard let identifier = representativeSelections[key] else { return nil }
        return assetLookup[identifier]
    }

    func setRepresentativeAsset(_ asset: PhotoAssetItem, for date: Date) {
        let keyDate = calendar.startOfDay(for: date)
        selectedPhotoStore.setRepresentativeIdentifier(asset.id, for: keyDate)
        representativeSelections = sanitizedSelections()
        currentStreak = selectedPhotoStore.currentStreak
        lastSelectedDate = selectedPhotoStore.lastSelectedDate
        rebuildDerivedCaches()
        lastUpdated = Date()
    }

    func hasRepresentativePhoto(on date: Date) -> Bool {
        if isMockDataEnabled {
            let key = DayKeyFormatter.dayString(from: calendar.startOfDay(for: date))
            if mockCalendarEntries(for: date.startOfMonth(using: calendar))[key]?.hasRepresentativePhoto == true {
                return true
            }
        }

        return representativeAsset(for: date) != nil
    }

    func mockPhotoCount(on date: Date) -> Int {
        let key = DayKeyFormatter.dayString(from: calendar.startOfDay(for: date))
        return mockCalendarEntries(for: date.startOfMonth(using: calendar))[key]?.photoCount ?? 0
    }

    func previewMockPhotos(for date: Date) -> [MockCalendarPhoto] {
        guard isMockDataEnabled else { return [] }

        let day = calendar.startOfDay(for: date)
        let dayNumber = calendar.component(.day, from: day)

        if isPreviewMode, calendar.isDateInToday(day) {
            return Self.samplePreviewAssets.prefix(5).enumerated().map { index, sample in
                MockCalendarPhoto(
                    id: "today-preview-\(index)",
                    date: day,
                    kind: sample.kind,
                    fileName: sample.fileName
                )
            }
        }

        let key = DayKeyFormatter.dayString(from: day)
        guard let entry = mockCalendarEntries(for: day.startOfMonth(using: calendar))[key] else { return [] }

        return (0..<max(entry.photoCount, 1)).map { index in
            let sample = sampleAsset(for: dayNumber + index, preferredKind: entry.photo.kind)
            return MockCalendarPhoto(
                id: "\(entry.photo.id)-option-\(index)",
                date: day,
                kind: sample.kind,
                fileName: sample.fileName
            )
        }
    }

    func todayAssets(referenceDate: Date = .now) -> [PhotoAssetItem] {
        assets(for: referenceDate)
    }

    func onThisDayItems(referenceDate: Date = .now, limit: Int = 3) -> [OnThisDayItem] {
        if referenceDate.startOfDay(using: calendar) == Date().startOfDay(using: calendar), limit == 3 {
            return onThisDayPreviewItems
        }

        let currentYear = calendar.component(.year, from: referenceDate)
        let referenceMonthDay = DayKeyFormatter.monthDayString(from: referenceDate)

        return assetsByDay.compactMap { key, items in
            guard
                let date = items.first?.creationDate.startOfDay(using: calendar),
                DayKeyFormatter.monthDayString(from: date) == referenceMonthDay,
                calendar.component(.year, from: date) < currentYear
            else {
                return nil
            }

            let representative = representativeAsset(for: date)
            let asset = representative ?? items.first

            guard let asset else { return nil }
            return OnThisDayItem(date: date, asset: asset, isRepresentative: representative != nil)
        }
        .sorted { $0.date > $1.date }
        .prefix(limit)
        .map { $0 }
    }

    func calendarDays(for month: Date) -> [CalendarDay] {
        let monthKey = DayKeyFormatter.dayString(from: month.startOfMonth(using: calendar))
        if let cached = calendarDaysCache[monthKey] {
            return cached
        }

        let startOfMonth = month.startOfMonth(using: calendar)
        guard
            let monthRange = calendar.range(of: .day, in: .month, for: startOfMonth),
            let firstWeekday = calendar.dateComponents([.weekday], from: startOfMonth).weekday
        else {
            return []
        }

        let leadingDays = (firstWeekday - calendar.firstWeekday + 7) % 7
        let totalVisibleDays = Int(ceil(Double(leadingDays + monthRange.count) / 7.0) * 7.0)
        let gridStart = calendar.date(byAdding: .day, value: -leadingDays, to: startOfMonth) ?? startOfMonth
        let today = calendar.startOfDay(for: .now)
        let mockEntries = mockCalendarEntries(for: startOfMonth)
        let streakDates = activeStreakDateKeys(referenceDate: today)

        return (0..<totalVisibleDays).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: gridStart) else {
                return nil
            }

            let key = DayKeyFormatter.dayString(from: date)
            let realPhotoCount = assetsByDay[key]?.count ?? 0
            let representativeAsset = representativeSelections[key].flatMap { assetLookup[$0] }
            let mockEntry = mockEntries[key]
            let photoCount = max(realPhotoCount, mockEntry?.photoCount ?? 0)
            let thumbnailSource = thumbnailSource(
                representativeAsset: representativeAsset,
                mockEntry: mockEntry
            )

            return CalendarDay(
                date: date,
                isWithinDisplayedMonth: calendar.isDate(date, equalTo: startOfMonth, toGranularity: .month),
                isToday: calendar.isDate(date, inSameDayAs: today),
                photoCount: photoCount,
                hasRepresentativePhoto: representativeAsset != nil || mockEntry?.hasRepresentativePhoto == true,
                isInCurrentStreak: streakDates.contains(key),
                representativeAsset: representativeAsset,
                thumbnailSource: thumbnailSource
            )
        }
        .also { days in
            calendarDaysCache[monthKey] = days
        }
    }

    var streakTitle: String {
        guard currentStreak > 0 else { return "Start your streak today" }
        return currentStreak == 1 ? "🔥 1 Day Streak" : "🔥 \(currentStreak) Day Streak"
    }

    var showsStreakPrompt: Bool {
        currentStreak > 0 && hasSelectedPhotoToday == false
    }

    var streakPrompt: String {
        "Keep your streak alive today"
    }

    var hasSelectedPhotoToday: Bool {
        guard let lastSelectedDate else { return false }
        return calendar.isDateInToday(lastSelectedDate)
    }

    var streakAccentLevel: Int {
        if currentStreak >= 30 {
            return 2
        }

        if currentStreak >= 7 {
            return 1
        }

        return 0
    }

    func previewStripItems(referenceDate: Date = .now, limit: Int = 10) -> [CalendarPreviewItem] {
        if referenceDate.startOfDay(using: calendar) == Date().startOfDay(using: calendar), limit == 10 {
            return previewItems
        }

        let todayAssets = assets(for: referenceDate)
        if todayAssets.isEmpty == false {
            return Array(
                todayAssets
                    .sorted { $0.creationDate > $1.creationDate }
                    .prefix(limit)
                    .map {
                        CalendarPreviewItem(date: $0.creationDate, thumbnailSource: .asset($0))
                    }
            )
        }

        let representativeItems = representativeSelections.values
            .compactMap { assetLookup[$0] }
            .sorted { $0.creationDate > $1.creationDate }

        if representativeItems.isEmpty == false {
            return Array(
                representativeItems.prefix(limit).map {
                    CalendarPreviewItem(date: $0.creationDate, thumbnailSource: .asset($0))
                }
            )
        }

        if isMockDataEnabled {
            let mockItems = mockCalendarEntries(for: referenceDate.startOfMonth(using: calendar))
                .values
                .sorted { $0.date > $1.date }
                .prefix(limit)
                .map {
                    CalendarPreviewItem(date: $0.date, thumbnailSource: .mock($0.photo))
                }

            if mockItems.isEmpty == false {
                return Array(mockItems)
            }
        }

        return Array(
            assetLookup.values
                .sorted { $0.creationDate > $1.creationDate }
                .prefix(limit)
                .map { CalendarPreviewItem(date: $0.creationDate, thumbnailSource: .asset($0)) }
        )
    }

    func previewStripTitle(referenceDate: Date = .now) -> String {
        if isPreviewMode {
            return "Today's Photos"
        }

        if todayAssets(referenceDate: referenceDate).isEmpty == false {
            return "Today's Photos"
        }

        return isMockDataEnabled ? "Preview Photos" : "Recent Photos"
    }

    func previewStripSubtitle(referenceDate: Date = .now) -> String {
        if isPreviewMode {
            return "Real sample moments, ready for today's pick."
        }

        if todayAssets(referenceDate: referenceDate).isEmpty {
            if isMockDataEnabled {
                return "Mock thumbnails to preview the filled calendar UI."
            }

            return "A quick strip of the moments shaping your calendar."
        }

        return "A few fresh shots from today, ready for your daily pick."
    }

    func prepareCalendarThumbnailCache(for month: Date, targetSize: CGSize) {
        let assets = calendarDays(for: month)
            .compactMap { day -> PHAsset? in
                guard case let .asset(item)? = day.thumbnailSource else { return nil }
                return item.asset
            }
        photoLibraryService.startCachingImages(
            for: assets,
            targetSize: targetSize,
            contentMode: .aspectFill
        )
    }

    func memoryTimelineEntries() -> [MemoryTimelineEntry] {
        if memoryTimelinePreviewItems.isEmpty == false || isMockDataEnabled == false {
            return memoryTimelinePreviewItems
        }

        let items = representativeSelections.compactMap { key, identifier -> MemoryTimelineEntry? in
            guard
                let asset = assetLookup[identifier],
                let date = DayKeyFormatter.date(fromDayString: key)
            else {
                return nil
            }

            return MemoryTimelineEntry(date: date, source: .asset(asset))
        }
        .sorted { $0.date > $1.date }

        if items.isEmpty == false || isMockDataEnabled == false {
            return items
        }

        return mockCalendarEntries(for: .now.startOfMonth(using: calendar))
            .values
            .sorted { $0.date > $1.date }
            .map { MemoryTimelineEntry(date: $0.date, source: .mock($0.photo)) }
    }

    func prepareMemoryTimelineCache(targetSize: CGSize) {
        let assets = memoryTimelineEntries().compactMap { entry -> PHAsset? in
            guard case let .asset(item) = entry.source else { return nil }
            return item.asset
        }

        photoLibraryService.startCachingImages(
            for: assets,
            targetSize: targetSize,
            contentMode: .aspectFill
        )
    }

    private func thumbnailSource(
        representativeAsset: PhotoAssetItem?,
        mockEntry: MockCalendarEntry?
    ) -> CalendarThumbnailSource? {
        if let representativeAsset {
            return .asset(representativeAsset)
        }

        if let mockEntry {
            return .mock(mockEntry.photo)
        }

        return nil
    }

    private func activeStreakDateKeys(referenceDate: Date) -> Set<String> {
        if isPreviewMode {
            let lastDay = calendar.startOfDay(for: referenceDate)
            return Set((0..<currentStreak).compactMap { offset in
                guard let date = calendar.date(byAdding: .day, value: -offset, to: lastDay) else { return nil }
                return DayKeyFormatter.dayString(from: date)
            })
        }

        guard currentStreak > 0, let lastSelectedDate else { return [] }

        let lastDay = calendar.startOfDay(for: lastSelectedDate)
        guard calendar.isDate(lastDay, equalTo: referenceDate, toGranularity: .day) ||
                calendar.isDate(lastDay, equalTo: calendar.date(byAdding: .day, value: -1, to: referenceDate) ?? referenceDate, toGranularity: .day)
        else {
            return []
        }

        return Set((0..<currentStreak).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: lastDay) else { return nil }
            return DayKeyFormatter.dayString(from: date)
        })
    }

    private func mockCalendarEntries(for month: Date) -> [String: MockCalendarEntry] {
        guard isMockDataEnabled else { return [:] }

        let startOfMonth = month.startOfMonth(using: calendar)
        var entries: [String: MockCalendarEntry] = [:]

        if isPreviewMode {
            seedPreviewMonthEntries(into: &entries, startOfMonth: startOfMonth)
            return entries
        }

        let today = calendar.startOfDay(for: .now)
        let baseDates = [
            today,
            calendar.date(byAdding: .day, value: -1, to: today),
            calendar.date(byAdding: .day, value: -3, to: today),
            calendar.date(byAdding: .day, value: 2, to: startOfMonth),
            calendar.date(byAdding: .day, value: 7, to: startOfMonth),
            calendar.date(byAdding: .day, value: 12, to: startOfMonth),
            calendar.date(byAdding: .day, value: 18, to: startOfMonth),
            calendar.date(byAdding: .day, value: 24, to: startOfMonth)
        ]
        .compactMap { $0 }

        let kinds = MockCalendarPhoto.Kind.allCases

        for (index, rawDate) in baseDates.enumerated() {
            let date = calendar.startOfDay(for: rawDate)
            let key = DayKeyFormatter.dayString(from: date)
            guard calendar.isDate(date, equalTo: month, toGranularity: .month) else { continue }
            guard entries[key] == nil else { continue }

            let kind = kinds[index % kinds.count]
            let sample = sampleAsset(for: index + 1, preferredKind: kind)
            let mockPhoto = MockCalendarPhoto(
                id: "mock-\(key)",
                date: date,
                kind: sample.kind,
                fileName: sample.fileName
            )
            entries[key] = MockCalendarEntry(
                date: date,
                photoCount: index % 3 == 0 ? 3 : 1,
                hasRepresentativePhoto: index % 2 == 0,
                photo: mockPhoto
            )
        }

        return entries
    }

    private func sanitizedSelections() -> [String: String] {
        selectedPhotoStore.selections.filter { _, identifier in
            assetLookup[identifier] != nil
        }
    }

    private func rebuildDerivedCaches(referenceDate: Date = .now) {
        calendarDaysCache.removeAll(keepingCapacity: true)
        previewItems = buildPreviewStripItems(referenceDate: referenceDate, limit: 10)
        onThisDayPreviewItems = buildOnThisDayItems(referenceDate: referenceDate, limit: 3)
        memoryTimelinePreviewItems = buildMemoryTimelineEntries()
    }

    private func buildPreviewStripItems(referenceDate: Date, limit: Int) -> [CalendarPreviewItem] {
        if isPreviewMode {
            let previewCandidates = previewMockPhotos(for: referenceDate)
                .prefix(limit)
                .map { CalendarPreviewItem(date: $0.date, thumbnailSource: .mock($0)) }

            if previewCandidates.isEmpty == false {
                return Array(previewCandidates)
            }
        }

        let todayAssets = assets(for: referenceDate)
        if todayAssets.isEmpty == false {
            return Array(
                todayAssets
                    .sorted { $0.creationDate > $1.creationDate }
                    .prefix(limit)
                    .map { CalendarPreviewItem(date: $0.creationDate, thumbnailSource: .asset($0)) }
            )
        }

        let representativeItems = representativeSelections.values
            .compactMap { assetLookup[$0] }
            .sorted { $0.creationDate > $1.creationDate }

        if representativeItems.isEmpty == false {
            return Array(
                representativeItems.prefix(limit).map {
                    CalendarPreviewItem(date: $0.creationDate, thumbnailSource: .asset($0))
                }
            )
        }

        if isMockDataEnabled {
            let mockItems = mockCalendarEntries(for: referenceDate.startOfMonth(using: calendar))
                .values
                .filter { $0.hasRepresentativePhoto || isPreviewMode == false }
                .sorted { $0.date > $1.date }
                .prefix(limit)
                .map { CalendarPreviewItem(date: $0.date, thumbnailSource: .mock($0.photo)) }

            if mockItems.isEmpty == false {
                return Array(mockItems)
            }
        }

        return []
    }

    private func buildOnThisDayItems(referenceDate: Date, limit: Int) -> [OnThisDayItem] {
        if isPreviewMode {
            return []
        }

        let currentYear = calendar.component(.year, from: referenceDate)
        let referenceMonthDay = DayKeyFormatter.monthDayString(from: referenceDate)

        return assetsByDay.compactMap { _, items in
            guard
                let date = items.first?.creationDate.startOfDay(using: calendar),
                DayKeyFormatter.monthDayString(from: date) == referenceMonthDay,
                calendar.component(.year, from: date) < currentYear
            else {
                return nil
            }

            let representative = representativeAsset(for: date)
            let asset = representative ?? items.first
            guard let asset else { return nil }
            return OnThisDayItem(date: date, asset: asset, isRepresentative: representative != nil)
        }
        .sorted { $0.date > $1.date }
        .prefix(limit)
        .map { $0 }
    }

    private func buildMemoryTimelineEntries() -> [MemoryTimelineEntry] {
        let items = representativeSelections.compactMap { key, identifier -> MemoryTimelineEntry? in
            guard
                let asset = assetLookup[identifier],
                let date = DayKeyFormatter.date(fromDayString: key)
            else {
                return nil
            }

            return MemoryTimelineEntry(date: date, source: .asset(asset))
        }
        .sorted { $0.date > $1.date }

        if items.isEmpty == false || isMockDataEnabled == false {
            return items
        }

        return mockCalendarEntries(for: .now.startOfMonth(using: calendar))
            .values
            .filter { $0.hasRepresentativePhoto }
            .sorted { $0.date > $1.date }
            .map { MemoryTimelineEntry(date: $0.date, source: .mock($0.photo)) }
    }

    private func seedPreviewMonthEntries(
        into entries: inout [String: MockCalendarEntry],
        startOfMonth: Date
    ) {
        let monthLength = calendar.range(of: .day, in: .month, for: startOfMonth)?.count ?? 30

        for dayOffset in 0..<monthLength {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: startOfMonth) else { continue }
            let dayNumber = calendar.component(.day, from: date)
            let shouldInclude = dayNumber % 6 != 0 && dayNumber != 13 && dayNumber != 18 && dayNumber != 27
            guard shouldInclude else { continue }

            let sample = sampleAsset(for: dayNumber)
            let photo = MockCalendarPhoto(
                id: "preview-\(DayKeyFormatter.dayString(from: date))",
                date: date,
                kind: sample.kind,
                fileName: sample.fileName
            )

            entries[DayKeyFormatter.dayString(from: date)] = MockCalendarEntry(
                date: date,
                photoCount: dayNumber % 5 == 0 ? 3 : (dayNumber % 4 == 0 ? 2 : 1),
                hasRepresentativePhoto: true,
                photo: photo
            )
        }

        let pinnedPreviewDays = [
            (day: 1, count: 3, sampleIndex: 0),
            (day: 8, count: 2, sampleIndex: 4),
            (day: 14, count: 3, sampleIndex: 2),
            (day: 21, count: 2, sampleIndex: 3),
            (day: 28, count: 3, sampleIndex: 1)
        ]

        for pinned in pinnedPreviewDays {
            guard let date = calendar.date(byAdding: .day, value: pinned.day - 1, to: startOfMonth) else { continue }
            let sample = Self.samplePreviewAssets[pinned.sampleIndex]
            let photo = MockCalendarPhoto(
                id: "preview-pinned-\(DayKeyFormatter.dayString(from: date))",
                date: date,
                kind: sample.kind,
                fileName: sample.fileName
            )

            entries[DayKeyFormatter.dayString(from: date)] = MockCalendarEntry(
                date: date,
                photoCount: pinned.count,
                hasRepresentativePhoto: true,
                photo: photo
            )
        }
    }

    private func sampleAsset(for dayNumber: Int, preferredKind: MockCalendarPhoto.Kind? = nil) -> SamplePreviewAsset {
        if let preferredKind {
            let matches = Self.samplePreviewAssets.filter { $0.kind == preferredKind }
            if matches.isEmpty == false {
                return matches[dayNumber % matches.count]
            }
        }

        return Self.samplePreviewAssets[dayNumber % Self.samplePreviewAssets.count]
    }
}

private struct MockCalendarEntry: Hashable {
    let date: Date
    let photoCount: Int
    let hasRepresentativePhoto: Bool
    let photo: MockCalendarPhoto
}

private extension Date {
    func startOfMonth(using calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.year, .month], from: self)
        return calendar.date(from: components) ?? self
    }
}

private extension Array where Element == CalendarDay {
    func also(_ update: ([CalendarDay]) -> Void) -> [CalendarDay] {
        update(self)
        return self
    }
}
