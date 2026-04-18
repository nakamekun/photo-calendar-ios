import Foundation
import OSLog
import Photos

@MainActor
final class PhotoLibraryViewModel: ObservableObject {
    @Published private(set) var authorizationState: PhotoAuthorizationState
    @Published private(set) var isLoading = false
    @Published private(set) var lastUpdated = Date()
    @Published private(set) var previewItems: [CalendarPreviewItem] = []
    @Published private(set) var onThisDayPreviewItems: [OnThisDayItem] = []
    @Published private(set) var memoryTimelinePreviewItems: [MemoryTimelineEntry] = []

    let isPreviewMode: Bool
    let isMockDataEnabled: Bool
    let showsPreviewDebugBadge: Bool
    let forceRepresentativeCacheRebuild: Bool

    private let photoLibraryService: PhotoLibraryServicing
    private let permissionService: PermissionServicing
    private let selectedPhotoStore: SelectedPhotoStoring
    private let faceDetectionService: FaceDetectionServicing
    private let calendar: Calendar
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "PhotoCalendarApp", category: "RepresentativePhoto")
    private var hasStartedInitialLoad = false
    private var calendarDaysCache: [String: [CalendarDay]] = [:]
    private var dayLoadTasks: [String: Task<Void, Never>] = [:]
    private var optimizationTasks: [String: Task<Void, Never>] = [:]
    private var libraryLoadTask: Task<Void, Never>?
    private var autoPickTask: Task<Void, Never>?
    private var monthSummaryLoadTasks: [String: Task<Void, Never>] = [:]
    private var loadedMonthKeys: Set<String> = []
    private var backgroundMonthBackfillTask: Task<Void, Never>?
    private var initialBootstrapTask: Task<Void, Never>?

    private struct DayPhotoState {
        let date: Date
        var assets: [PhotoAssetItem]
        var latestAssetID: String?
        var representativeAssetID: String?
        var hasLoadedAllAssets: Bool

        var hasAnyPhotos: Bool {
            assets.isEmpty == false
        }
    }

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

    private var assetLookup: [String: PhotoAssetItem] = [:]
    private var representativeSelections: [String: String]
    private var cachedSelectionsByDay: [String: CachedDaySelection]
    private var excludedIdentifiersByDay: [String: Set<String>]
    private var autoPickDisabledDayKeys: Set<String>
    private var dayStates: [String: DayPhotoState] = [:]
    private var photoDaySummariesByKey: [String: PhotoDaySummary] = [:]

    init(
        photoLibraryService: PhotoLibraryServicing = PhotoLibraryService(),
        permissionService: PermissionServicing = PermissionService(),
        selectedPhotoStore: SelectedPhotoStoring = SelectedPhotoStore(),
        faceDetectionService: FaceDetectionServicing? = nil,
        isPreviewMode: Bool = false,
        isMockDataEnabled: Bool = false,
        showsPreviewDebugBadge: Bool = true,
        forceRepresentativeCacheRebuild: Bool = false,
        calendar: Calendar = .current
    ) {
        self.photoLibraryService = photoLibraryService
        self.permissionService = permissionService
        self.selectedPhotoStore = selectedPhotoStore
        self.faceDetectionService = faceDetectionService ?? FaceDetectionService(photoLibraryService: photoLibraryService)
        self.isPreviewMode = isPreviewMode
        self.isMockDataEnabled = isPreviewMode || isMockDataEnabled
        self.showsPreviewDebugBadge = isPreviewMode && showsPreviewDebugBadge
        self.forceRepresentativeCacheRebuild = forceRepresentativeCacheRebuild
        self.calendar = calendar
        self.authorizationState = permissionService.currentStatus()
        self.cachedSelectionsByDay = selectedPhotoStore.cachedSelections()
        self.excludedIdentifiersByDay = selectedPhotoStore.cachedExcludedIdentifiers()
        self.autoPickDisabledDayKeys = selectedPhotoStore.cachedAutoPickDisabledDates()
        self.representativeSelections = self.cachedSelectionsByDay.mapValues(\.representativeIdentifier)
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
        guard authorizationState.canReadLibrary else { return }

        if forceRepresentativeCacheRebuild {
            logger.notice("Launch flag requested representative cache rebuild. Existing cached selections will be ignored.")
            resetRepresentativeCache()
        }

        scheduleInitialBootstrap()
    }

    func requestPhotoAccess() async {
        authorizationState = await permissionService.requestAuthorization()
        guard authorizationState.canReadLibrary else { return }

        await warmCachedSelections()
        loadLibrary()
    }

    func loadLibrary() {
        guard authorizationState.canReadLibrary else { return }
        libraryLoadTask?.cancel()
        autoPickTask?.cancel()
        isLoading = true

        let currentMonth = Date().startOfMonth(using: calendar)
        libraryLoadTask = Task {
            await self.loadMonthIfNeeded(currentMonth, priority: .userInitiated, showLoading: true)
            await MainActor.run {
                self.libraryLoadTask = nil
            }
        }
    }

    func loadDayIfNeeded(_ date: Date) {
        guard authorizationState.canReadLibrary || isMockDataEnabled else { return }
        guard isPreviewMode == false else { return }

        let day = calendar.startOfDay(for: date)
        let key = DayKeyFormatter.dayString(from: day)
        guard dayLoadTasks[key] == nil else { return }

        if let state = dayStates[key], state.hasLoadedAllAssets, state.assets.isEmpty == false {
            return
        }

        if let summary = photoDaySummariesByKey[key] {
            loadAssets(for: summary, prioritize: .userInitiated, loadsAllAssets: false)
            prefetchAdjacentDays(around: day)
            return
        }

        Task {
            await self.loadMonthIfNeeded(
                day.startOfMonth(using: calendar),
                priority: .userInitiated,
                focusedDay: day,
                loadFocusedDayFully: false,
                showLoading: true
            )
            self.prefetchAdjacentDays(around: day)
        }
    }

    func loadDayFullyIfNeeded(_ date: Date) {
        guard authorizationState.canReadLibrary || isMockDataEnabled else { return }
        guard isPreviewMode == false else { return }

        let day = calendar.startOfDay(for: date)
        let key = DayKeyFormatter.dayString(from: day)

        if dayStates[key]?.hasLoadedAllAssets == true {
            return
        }

        if dayLoadTasks[key] != nil {
            Task {
                try? await Task.sleep(nanoseconds: 200_000_000)
                await MainActor.run {
                    self.loadDayFullyIfNeeded(day)
                }
            }
            return
        }

        if let summary = photoDaySummariesByKey[key] {
            loadAssets(for: summary, prioritize: .utility, loadsAllAssets: true)
            return
        }

        Task {
            await self.loadMonthIfNeeded(
                day.startOfMonth(using: calendar),
                priority: .utility,
                focusedDay: day,
                loadFocusedDayFully: true
            )
        }
    }

    func assets(for date: Date) -> [PhotoAssetItem] {
        let key = DayKeyFormatter.dayString(from: calendar.startOfDay(for: date))
        return dayStates[key]?.assets ?? []
    }

    func representativeAsset(for date: Date) -> PhotoAssetItem? {
        let key = DayKeyFormatter.dayString(from: calendar.startOfDay(for: date))

        if let cached = cachedSelectionsByDay[key],
           cached.source == .manual,
           let asset = assetLookup[cached.representativeIdentifier] {
            return asset
        }

        guard autoPickDisabledDayKeys.contains(key) == false else {
            return nil
        }

        if let cached = cachedSelectionsByDay[key],
           cached.source == .automatic,
           let asset = assetLookup[cached.representativeIdentifier] {
            return asset
        }

        if let representativeID = representativeSelections[key] {
            return assetLookup[representativeID]
        }

        return nil
    }

    func latestAsset(for date: Date) -> PhotoAssetItem? {
        let key = DayKeyFormatter.dayString(from: calendar.startOfDay(for: date))
        guard let latestAssetID = dayStates[key]?.latestAssetID else { return nil }
        return assetLookup[latestAssetID]
    }

    func isManualRepresentative(for date: Date) -> Bool {
        let key = DayKeyFormatter.dayString(from: calendar.startOfDay(for: date))
        return cachedSelectionsByDay[key]?.source == .manual
    }

    func isAutoPickDisabled(for date: Date) -> Bool {
        autoPickDisabledDayKeys.contains(DayKeyFormatter.dayString(from: calendar.startOfDay(for: date)))
    }

    func canExcludeAutoPickedRepresentative(on date: Date) -> Bool {
        let key = DayKeyFormatter.dayString(from: calendar.startOfDay(for: date))
        guard autoPickDisabledDayKeys.contains(key) == false else { return false }
        guard let representativeID = representativeSelections[key] ?? dayStates[key]?.representativeAssetID else {
            return false
        }

        return assetLookup[representativeID] != nil
    }

    func excludeAutoPickedRepresentative(on date: Date) {
        disableAutoPick(for: date, excludingCurrentRepresentative: true)
    }

    func disableAutoPick(for date: Date, excludingCurrentRepresentative: Bool) {
        let day = calendar.startOfDay(for: date)
        let key = DayKeyFormatter.dayString(from: day)
        guard let representativeID = representativeSelections[key] ?? dayStates[key]?.representativeAssetID else { return }

        logger.notice("Disabling auto-pick for day \(key, privacy: .public). representative=\(representativeID, privacy: .public)")

        if excludingCurrentRepresentative {
            selectedPhotoStore.excludeIdentifier(representativeID, for: day)
            excludedIdentifiersByDay[key, default: []].insert(representativeID)
        }

        selectedPhotoStore.setAutoPickDisabled(true, for: day)
        autoPickDisabledDayKeys.insert(key)

        optimizationTasks[key]?.cancel()
        optimizationTasks[key] = nil

        selectedPhotoStore.removeRepresentativeIdentifier(for: day)
        cachedSelectionsByDay.removeValue(forKey: key)
        representativeSelections.removeValue(forKey: key)
        dayStates[key]?.representativeAssetID = nil
        rebuildDerivedCaches()
        lastUpdated = Date()
    }

    func resetRepresentativeCache() {
        logger.notice("Resetting all cached representative selections.")
        selectedPhotoStore.resetAllRepresentativeSelections()
        cachedSelectionsByDay.removeAll(keepingCapacity: true)
        representativeSelections.removeAll(keepingCapacity: true)
        autoPickTask?.cancel()

        for key in dayStates.keys {
            let latestAssetID = dayStates[key]?.latestAssetID
            dayStates[key]?.representativeAssetID = autoPickDisabledDayKeys.contains(key) ? nil : latestAssetID
        }

        rebuildDerivedCaches()
        lastUpdated = Date()
    }

    func setManualRepresentativeAsset(_ asset: PhotoAssetItem, for date: Date) {
        let day = calendar.startOfDay(for: date)
        let key = DayKeyFormatter.dayString(from: day)
        let latestItem = latestAsset(for: day) ?? assets(for: day).first

        persistSelection(
            representativeID: asset.id,
            latestItem: latestItem,
            source: .manual,
            for: day
        )
        selectedPhotoStore.setAutoPickDisabled(false, for: day)
        autoPickDisabledDayKeys.remove(key)
        dayStates[key]?.representativeAssetID = asset.id
        optimizationTasks[key]?.cancel()
        optimizationTasks[key] = nil
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

    func previousPhotoDate(from date: Date) -> Date? {
        let target = calendar.startOfDay(for: date)
        return availablePhotoDates()
            .filter { $0 < target }
            .max()
    }

    func nextPhotoDate(from date: Date) -> Date? {
        let target = calendar.startOfDay(for: date)
        return availablePhotoDates()
            .filter { $0 > target }
            .min()
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

        let days = (0..<totalVisibleDays).compactMap { offset -> CalendarDay? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: gridStart) else {
                return nil
            }

            let key = DayKeyFormatter.dayString(from: date)
            let dayState = dayStates[key]
            let daySummary = photoDaySummariesByKey[key]
            let representativeAsset = representativeSelections[key].flatMap { assetLookup[$0] }
            let latestAsset = dayState?.latestAssetID.flatMap { assetLookup[$0] }
            let mockEntry = mockEntries[key]
            let photoCount = max(daySummary?.photoCount ?? 0, mockEntry?.photoCount ?? 0)

            return CalendarDay(
                date: date,
                isWithinDisplayedMonth: calendar.isDate(date, equalTo: startOfMonth, toGranularity: .month),
                isToday: calendar.isDate(date, inSameDayAs: today),
                photoCount: photoCount,
                hasRepresentativePhoto: representativeAsset != nil || mockEntry?.hasRepresentativePhoto == true,
                isInCurrentStreak: false,
                representativeAsset: representativeAsset,
                thumbnailSource: thumbnailSource(
                    representativeAsset: representativeAsset,
                    latestAsset: latestAsset,
                    mockEntry: mockEntry
                )
            )
        }

        calendarDaysCache[monthKey] = days
        return days
    }

    func previewStripItems(referenceDate: Date = .now, limit: Int = 10) -> [CalendarPreviewItem] {
        if referenceDate.startOfDay(using: calendar) == Date().startOfDay(using: calendar), limit == 10 {
            return previewItems
        }

        return buildPreviewStripItems(referenceDate: referenceDate, limit: limit)
    }

    func previewStripTitle(referenceDate: Date = .now) -> String {
        if isPreviewMode {
            return "Recent Photos"
        }

        if todayAssets(referenceDate: referenceDate).isEmpty == false {
            return "Recent Photos"
        }

        return isMockDataEnabled ? "Preview Photos" : "Recent Memories"
    }

    func previewStripSubtitle(referenceDate: Date = .now) -> String {
        if isPreviewMode {
            return "Real sample moments, already filled in."
        }

        if todayAssets(referenceDate: referenceDate).isEmpty {
            if isMockDataEnabled {
                return "Mock thumbnails to preview the filled calendar UI."
            }

            return "Cached favorites and recent shots appear without setup."
        }

        return "Open a day and swipe through the latest shots."
    }

    func prepareCalendarThumbnailCache(for month: Date, targetSize: CGSize) {
        let monthStart = month.startOfMonth(using: calendar)
        Task {
            await self.loadMonthIfNeeded(monthStart, priority: .userInitiated)
        }

        let assets = calendarDays(for: monthStart).compactMap { day -> PHAsset? in
            switch day.thumbnailSource {
            case .asset(let item):
                return item.asset
            case .mock, .none:
                return nil
            }
        }

        photoLibraryService.startCachingImages(
            for: assets,
            targetSize: targetSize,
            contentMode: .aspectFill
        )
    }

    func prepareDayNavigationCache(around date: Date, targetSize: CGSize) {
        let centerDay = calendar.startOfDay(for: date)
        prefetchAdjacentDays(around: centerDay)

        let assets = (-1...1).compactMap { offset -> PHAsset? in
            guard let targetDay = calendar.date(byAdding: .day, value: offset, to: centerDay) else { return nil }
            return representativeAsset(for: targetDay)?.asset ?? latestAsset(for: targetDay)?.asset
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

        return buildMemoryTimelineEntries()
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

    func prepareMemoryTimelineData(initialDate: Date = .now) {
        let targetMonth = initialDate.startOfMonth(using: calendar)

        Task {
            await self.loadMonthIfNeeded(targetMonth, priority: .userInitiated, showLoading: true)
            self.prefetchMonths(around: targetMonth)
            self.startBackgroundMonthBackfillIfNeeded()
        }
    }

    func prepareHistoryMonth(for date: Date) {
        let targetMonth = date.startOfMonth(using: calendar)

        Task {
            await self.loadMonthIfNeeded(targetMonth, priority: .userInitiated)
        }
    }

    private func loadMonthIfNeeded(
        _ month: Date,
        priority: TaskPriority,
        focusedDay: Date? = nil,
        loadFocusedDayFully: Bool = false,
        showLoading: Bool = false
    ) async {
        let monthStart = month.startOfMonth(using: calendar)
        let monthKey = DayKeyFormatter.dayString(from: monthStart)
        if loadedMonthKeys.contains(monthKey) {
            if let focusedDay {
                loadFocusedDayIfAvailable(focusedDay, fully: loadFocusedDayFully)
            }
            if showLoading {
                isLoading = false
            }
            return
        }

        if monthSummaryLoadTasks[monthKey] != nil {
            return
        }

        if showLoading {
            isLoading = true
        }

        monthSummaryLoadTasks[monthKey] = Task { [photoLibraryService, calendar] in
            let interval = DateInterval(
                start: monthStart,
                end: calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
            )
            let summaries = await Task.detached(priority: priority) {
                photoLibraryService.fetchPhotoDaySummaries(in: interval, limitPerDay: 10)
            }.value

            await self.finishLoadingSummaries(
                summaries,
                loadedMonthKey: monthKey,
                focusedDay: focusedDay,
                loadFocusedDayFully: loadFocusedDayFully,
                clearLoading: showLoading
            )
        }
    }

    private func finishLoadingSummaries(
        _ summaries: [PhotoDaySummary],
        loadedMonthKey: String? = nil,
        focusedDay: Date? = nil,
        loadFocusedDayFully: Bool = false,
        clearLoading: Bool = false,
        triggerAutoPick: Bool = true
    ) async {
        if let loadedMonthKey {
            monthSummaryLoadTasks.removeValue(forKey: loadedMonthKey)
            loadedMonthKeys.insert(loadedMonthKey)
        }

        let keyedSummaries = Dictionary(
            uniqueKeysWithValues: summaries.map { (DayKeyFormatter.dayString(from: $0.date), $0) }
        )
        photoDaySummariesByKey.merge(keyedSummaries) { _, new in new }
        applyAutomaticRepresentatives(from: summaries)
        if clearLoading {
            isLoading = false
        }
        invalidateCalendarCache(for: summaries.map(\.date))
        refreshTimelineDerivedCaches(referenceDate: focusedDay ?? .now, refreshPreviewStrip: true)
        lastUpdated = Date()

        if let focusedDay {
            loadFocusedDayIfAvailable(focusedDay, fully: loadFocusedDayFully)
        } else if let latestSummary = summaries.first, dayStates[DayKeyFormatter.dayString(from: latestSummary.date)] == nil {
            loadAssets(for: latestSummary, prioritize: .userInitiated)
        }

        if summaries.isEmpty == false, triggerAutoPick {
            prefetchRepresentativeAssets(for: summaries, priority: .utility)
        }
    }

    private func applyAutomaticRepresentatives(from summaries: [PhotoDaySummary]) {
        for summary in summaries {
            let day = calendar.startOfDay(for: summary.date)
            let key = DayKeyFormatter.dayString(from: day)

            if autoPickDisabledDayKeys.contains(key) {
                continue
            }

            if let cached = cachedSelectionsByDay[key], cached.source == .manual {
                representativeSelections[key] = cached.representativeIdentifier
                continue
            }

            let representativeID = summary.representativeAssetIdentifier ?? summary.latestAssetIdentifier
            representativeSelections[key] = representativeID
            if let representativeID, dayStates[key] != nil {
                dayStates[key]?.representativeAssetID = representativeID
            }
        }
    }

    private func prefetchRepresentativeAssets(for summaries: [PhotoDaySummary], priority: TaskPriority) {
        let identifiers = Array(
            Set(
                summaries.compactMap {
                    $0.representativeAssetIdentifier ?? $0.latestAssetIdentifier
                }
            )
        )
        guard identifiers.isEmpty == false else { return }

        Task { [photoLibraryService] in
            let assets = await Task.detached(priority: priority) {
                photoLibraryService.fetchAssets(localIdentifiers: identifiers).map(PhotoAssetItem.init)
            }.value

            await MainActor.run {
                assets.forEach { assetLookup[$0.id] = $0 }
                self.invalidateCalendarCache(for: summaries.map(\.date))
                self.refreshTimelineDerivedCaches(refreshPreviewStrip: true)
                lastUpdated = Date()
            }
        }
    }

    private func loadFocusedDayIfAvailable(_ day: Date, fully: Bool) {
        let key = DayKeyFormatter.dayString(from: calendar.startOfDay(for: day))
        guard let summary = photoDaySummariesByKey[key] else { return }
        loadAssets(for: summary, prioritize: .userInitiated, loadsAllAssets: fully)
    }

    private func prefetchMonths(around month: Date) {
        for offset in [-1, 1] {
            guard let adjacentMonth = calendar.date(byAdding: .month, value: offset, to: month) else { continue }
            Task {
                await self.loadMonthIfNeeded(adjacentMonth, priority: .utility)
            }
        }
    }

    private func startBackgroundMonthBackfillIfNeeded() {
        guard backgroundMonthBackfillTask == nil else { return }

        backgroundMonthBackfillTask = Task { [photoLibraryService, calendar] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if Task.isCancelled { return }

            let oldestAssetDate = await Task.detached(priority: .utility) {
                photoLibraryService.fetchOldestImageAsset()?.creationDate
            }.value

            guard let oldestAssetDate else {
                await MainActor.run {
                    self.backgroundMonthBackfillTask = nil
                }
                return
            }

            var monthCursor = Date().startOfMonth(using: calendar)
            let oldestMonth = oldestAssetDate.startOfMonth(using: calendar)

            while monthCursor > oldestMonth {
                if Task.isCancelled { break }
                guard let previousMonth = calendar.date(byAdding: .month, value: -1, to: monthCursor) else { break }
                monthCursor = previousMonth
                await self.loadMonthIfNeeded(monthCursor, priority: .utility)
                try? await Task.sleep(nanoseconds: 120_000_000)
            }

            await MainActor.run {
                self.backgroundMonthBackfillTask = nil
            }
        }
    }

    private func scheduleInitialBootstrap() {
        guard initialBootstrapTask == nil else { return }

        initialBootstrapTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            if Task.isCancelled { return }

            await self.warmCachedSelections()
            if Task.isCancelled { return }

            self.loadLibrary()
            self.initialBootstrapTask = nil
        }
    }

    private func prefetchAdjacentDays(around day: Date) {
        for offset in [-1, 1] {
            guard let adjacentDay = calendar.date(byAdding: .day, value: offset, to: day) else { continue }
            let key = DayKeyFormatter.dayString(from: adjacentDay)
            if let summary = photoDaySummariesByKey[key] {
                loadAssets(for: summary, prioritize: .utility, loadsAllAssets: false)
                continue
            }

            Task {
                await self.loadMonthIfNeeded(
                    adjacentDay.startOfMonth(using: calendar),
                    priority: .utility,
                    focusedDay: adjacentDay,
                    loadFocusedDayFully: false
                )
            }
        }
    }

    private func startSequentialAutoPick(with summaries: [PhotoDaySummary]) {
        autoPickTask?.cancel()

        autoPickTask = Task {
            for summary in summaries {
                if Task.isCancelled { break }
                let key = DayKeyFormatter.dayString(from: summary.date)

                if shouldRecomputeSelection(for: summary.date, latestAssetID: summary.latestAssetIdentifier) == false {
                    if dayStates[key] == nil {
                        loadAssets(for: summary, prioritize: .utility)
                    }
                    continue
                }

                loadAssets(for: summary, prioritize: .utility)

                while dayLoadTasks[key] != nil || optimizationTasks[key] != nil {
                    try? await Task.sleep(nanoseconds: 80_000_000)
                    if Task.isCancelled { break }
                }
            }
        }
    }

    private func loadAssets(for summary: PhotoDaySummary, prioritize priority: TaskPriority, loadsAllAssets: Bool = false) {
        let day = calendar.startOfDay(for: summary.date)
        let key = DayKeyFormatter.dayString(from: day)
        if loadsAllAssets == false, dayStates[key]?.hasLoadedAllAssets == true {
            return
        }
        guard dayLoadTasks[key] == nil else { return }

        let cachedSelection = cachedSelectionsByDay[key]
        dayLoadTasks[key] = Task { [photoLibraryService, calendar] in
            let result = await Task.detached(priority: priority) {
                let primaryItems = if loadsAllAssets {
                    photoLibraryService.fetchAllImageAssets(on: day).map(PhotoAssetItem.init)
                } else {
                    photoLibraryService.fetchAssets(localIdentifiers: summary.candidateAssetIdentifiers).map(PhotoAssetItem.init)
                }

                guard
                    let cachedSelection,
                    primaryItems.contains(where: { $0.id == cachedSelection.representativeIdentifier }) == false,
                    let cachedAsset = photoLibraryService.fetchAsset(localIdentifier: cachedSelection.representativeIdentifier),
                    let creationDate = cachedAsset.creationDate,
                    calendar.isDate(creationDate, inSameDayAs: day)
                else {
                    return primaryItems
                }

                var merged = primaryItems
                merged.append(PhotoAssetItem(asset: cachedAsset))
                return merged
            }.value

            await self.finishLoadingDay(
                result,
                for: day,
                expectedPhotoCount: summary.photoCount,
                hasLoadedAllAssets: loadsAllAssets
            )
        }
    }

    private func finishLoadingDay(
        _ items: [PhotoAssetItem],
        for date: Date,
        expectedPhotoCount: Int? = nil,
        hasLoadedAllAssets: Bool = false
    ) async {
        let day = calendar.startOfDay(for: date)
        let key = DayKeyFormatter.dayString(from: day)

        dayLoadTasks[key] = nil
        isLoading = false

        let sortedItems = Array(Set(items)).sorted { $0.creationDate > $1.creationDate }
        sortedItems.forEach { assetLookup[$0.id] = $0 }

        let latestAssetID = sortedItems.first?.id
        let currentRepresentativeID = representativeSelections[key]
        if let currentRepresentativeID,
           let currentAsset = sortedItems.first(where: { $0.id == currentRepresentativeID }) ?? assetLookup[currentRepresentativeID],
           currentAsset.asset.mediaSubtypes.contains(.photoScreenshot) {
            let source = cachedSelectionsByDay[key]?.source == .manual ? "manual" : "automatic"
            logger.notice("Screenshot representative detected for day \(key, privacy: .public). source=\(source, privacy: .public) identifier=\(currentRepresentativeID, privacy: .public)")
        }

        dayStates[key] = DayPhotoState(
            date: day,
            assets: sortedItems,
            latestAssetID: latestAssetID,
            representativeAssetID: currentRepresentativeID ?? (autoPickDisabledDayKeys.contains(key) ? nil : latestAssetID),
            hasLoadedAllAssets: hasLoadedAllAssets
        )

        if let summary = photoDaySummariesByKey[key], summary.photoCount != (expectedPhotoCount ?? summary.photoCount) {
            photoDaySummariesByKey[key] = PhotoDaySummary(
                date: summary.date,
                photoCount: expectedPhotoCount ?? summary.photoCount,
                candidateAssetIdentifiers: summary.candidateAssetIdentifiers,
                latestAssetIdentifier: summary.latestAssetIdentifier,
                representativeAssetIdentifier: summary.representativeAssetIdentifier
            )
        }

        let automaticCandidates = autoPickCandidates(from: sortedItems, for: day)

        if let cachedSelection = cachedSelectionsByDay[key],
           cachedSelection.source == .manual,
           cachedSelection.latestAssetIdentifier != latestAssetID,
           let representativeID = dayStates[key]?.representativeAssetID {
            persistSelection(
                representativeID: representativeID,
                latestItem: sortedItems.first,
                source: .manual,
                for: day
            )
        } else if currentRepresentativeID == nil,
                  autoPickDisabledDayKeys.contains(key) == false,
                  let autoCandidate = automaticCandidates.first {
            persistSelection(
                representativeID: autoCandidate.id,
                latestItem: sortedItems.first,
                source: .automatic,
                for: day
            )
            dayStates[key]?.representativeAssetID = autoCandidate.id
        }

        invalidateCalendarCache(for: [day])
        refreshTimelineDerivedCaches(referenceDate: day, refreshPreviewStrip: calendar.isDateInToday(day))
        lastUpdated = Date()

        guard
            automaticCandidates.isEmpty == false,
            autoPickDisabledDayKeys.contains(key) == false
        else {
            return
        }
    }

    private func shouldRecomputeSelection(for date: Date, latestAssetID: String?) -> Bool {
        let key = DayKeyFormatter.dayString(from: date)
        guard let latestAssetID else { return false }
        if autoPickDisabledDayKeys.contains(key) { return false }
        guard let cached = cachedSelectionsByDay[key] else { return true }
        if cached.source == .manual { return false }

        if excludedIdentifiersByDay[key]?.contains(cached.representativeIdentifier) == true {
            logger.notice("Forcing reevaluation for day \(key, privacy: .public) because cached representative is excluded. identifier=\(cached.representativeIdentifier, privacy: .public)")
            return true
        }

        if isScreenshotIdentifier(cached.representativeIdentifier) {
            logger.notice("Forcing reevaluation for day \(key, privacy: .public) because cached automatic representative is a screenshot. identifier=\(cached.representativeIdentifier, privacy: .public) source=cache")
            return true
        }

        return cached.latestAssetIdentifier != latestAssetID
    }

    private func startOptimizingSelection(for date: Date, candidates: [PhotoAssetItem], force: Bool = false) {
        let day = calendar.startOfDay(for: date)
        let key = DayKeyFormatter.dayString(from: day)
        if force {
            optimizationTasks[key]?.cancel()
            optimizationTasks[key] = nil
        }
        guard optimizationTasks[key] == nil else { return }

        optimizationTasks[key] = Task { [faceDetectionService] in
            let best = await Task.detached(priority: .utility) {
                var bestItem: PhotoAssetItem?
                var bestScore = -Double.greatestFiniteMagnitude

                for item in candidates {
                    let score = await faceDetectionService.rankingScore(for: item.asset, targetPixelSize: 240)
                    if score > bestScore {
                        bestScore = score
                        bestItem = item
                        continue
                    }

                    if score == bestScore,
                       let currentBest = bestItem,
                       item.creationDate > currentBest.creationDate {
                        bestItem = item
                    }
                }

                return bestItem ?? candidates.first
            }.value

            await self.finishOptimizingSelection(best, for: day)
        }
    }

    private func finishOptimizingSelection(_ bestItem: PhotoAssetItem?, for date: Date) async {
        let day = calendar.startOfDay(for: date)
        let key = DayKeyFormatter.dayString(from: day)
        optimizationTasks[key] = nil

        guard
            let bestItem,
            let state = dayStates[key],
            state.representativeAssetID != bestItem.id
        else {
            return
        }

        persistSelection(
            representativeID: bestItem.id,
            latestItem: state.assets.first,
            source: .automatic,
            for: day
        )
        dayStates[key]?.representativeAssetID = bestItem.id
        rebuildDerivedCaches()
        lastUpdated = Date()
    }

    private func persistSelection(
        representativeID: String,
        latestItem: PhotoAssetItem?,
        source: DaySelectionSource,
        for date: Date
    ) {
        let selection = CachedDaySelection(
            representativeIdentifier: representativeID,
            latestAssetIdentifier: latestItem?.id ?? representativeID,
            latestAssetCreationDate: latestItem?.creationDate,
            source: source,
            updatedAt: .now
        )
        selectedPhotoStore.setCachedSelection(selection, for: date)
        cachedSelectionsByDay[DayKeyFormatter.dayString(from: date)] = selection
        representativeSelections[DayKeyFormatter.dayString(from: date)] = representativeID
        let dayKey = DayKeyFormatter.dayString(from: date)
        let isScreenshot = isScreenshotIdentifier(representativeID)
        let screenshotState = isScreenshot ? "screenshot" : "non_screenshot"
        if source == .automatic && isScreenshot {
            logger.error("Automatic selection persisted a screenshot for day \(dayKey, privacy: .public). identifier=\(representativeID, privacy: .public) source=selection")
        } else {
            logger.notice("Persisted representative for day \(dayKey, privacy: .public). source=\(source.rawValue, privacy: .public) identifier=\(representativeID, privacy: .public) kind=\(screenshotState, privacy: .public)")
        }
    }

    private func warmCachedSelections() async {
        let identifiers = Array(Set(cachedSelectionsByDay.values.map(\.representativeIdentifier)))
        let assets = await Task.detached(priority: .utility) { [photoLibraryService] in
            photoLibraryService.fetchAssets(localIdentifiers: identifiers).map(PhotoAssetItem.init)
        }.value
        assets.forEach { assetLookup[$0.id] = $0 }
        representativeSelections = cachedSelectionsByDay.reduce(into: [String: String]()) { partialResult, entry in
            if assetLookup[entry.value.representativeIdentifier] != nil {
                partialResult[entry.key] = entry.value.representativeIdentifier
            }
        }
        rebuildDerivedCaches()
        lastUpdated = Date()
    }

    private func thumbnailSource(
        representativeAsset: PhotoAssetItem?,
        latestAsset: PhotoAssetItem?,
        mockEntry: MockCalendarEntry?
    ) -> CalendarThumbnailSource? {
        if let representativeAsset {
            return .asset(representativeAsset)
        }

        if let latestAsset {
            return .asset(latestAsset)
        }

        if let mockEntry {
            return .mock(mockEntry.photo)
        }

        return nil
    }

    private func rebuildDerivedCaches(referenceDate: Date = .now) {
        calendarDaysCache.removeAll(keepingCapacity: true)
        previewItems = buildPreviewStripItems(referenceDate: referenceDate, limit: 10)
        onThisDayPreviewItems = buildOnThisDayItems(referenceDate: referenceDate, limit: 3)
        memoryTimelinePreviewItems = buildMemoryTimelineEntries()
    }

    private func invalidateCalendarCache(for dates: [Date]) {
        for month in Set(dates.map({ $0.startOfMonth(using: calendar) })) {
            let monthKey = DayKeyFormatter.dayString(from: month)
            calendarDaysCache.removeValue(forKey: monthKey)
        }
    }

    private func refreshTimelineDerivedCaches(referenceDate: Date = .now, refreshPreviewStrip: Bool = false) {
        if refreshPreviewStrip || previewItems.isEmpty {
            previewItems = buildPreviewStripItems(referenceDate: referenceDate, limit: 10)
        }
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
                    .prefix(limit)
                    .map { CalendarPreviewItem(date: referenceDate, thumbnailSource: .asset($0)) }
            )
        }

        let representativeItems = representativeSelections.compactMap { key, identifier -> CalendarPreviewItem? in
            guard
                let asset = assetLookup[identifier],
                let date = DayKeyFormatter.date(fromDayString: key)
            else {
                return nil
            }

            return CalendarPreviewItem(date: date, thumbnailSource: .asset(asset))
        }
        .sorted { $0.date > $1.date }

        if representativeItems.isEmpty == false {
            return Array(representativeItems.prefix(limit))
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

        return representativeSelections.compactMap { key, identifier -> OnThisDayItem? in
            guard
                let date = DayKeyFormatter.date(fromDayString: key),
                DayKeyFormatter.monthDayString(from: date) == referenceMonthDay,
                calendar.component(.year, from: date) < currentYear,
                let asset = assetLookup[identifier]
            else {
                return nil
            }

            return OnThisDayItem(date: date, asset: asset, isRepresentative: true)
        }
        .sorted { $0.date > $1.date }
        .prefix(limit)
        .map { $0 }
    }

    private func buildMemoryTimelineEntries() -> [MemoryTimelineEntry] {
        let dayKeys = Set(dayStates.keys).union(representativeSelections.keys)

        let items = dayKeys.compactMap { key -> MemoryTimelineEntry? in
            guard autoPickDisabledDayKeys.contains(key) == false || cachedSelectionsByDay[key]?.source == .manual else {
                return nil
            }

            let representativeID = representativeSelections[key]
            guard
                let representativeID,
                let asset = assetLookup[representativeID],
                let date = DayKeyFormatter.date(fromDayString: key)
            else {
                return nil
            }

            return MemoryTimelineEntry(
                date: date,
                source: .asset(asset),
                isManualSelection: cachedSelectionsByDay[key]?.source == .manual
            )
        }
        .sorted { $0.date > $1.date }

        if items.isEmpty == false || isMockDataEnabled == false {
            return items
        }

        return mockCalendarEntries(for: .now.startOfMonth(using: calendar))
            .values
            .filter { $0.hasRepresentativePhoto }
            .sorted { $0.date > $1.date }
            .map { MemoryTimelineEntry(date: $0.date, source: .mock($0.photo), isManualSelection: false) }
    }

    private func availablePhotoDates() -> [Date] {
        if isPreviewMode {
            let today = calendar.startOfDay(for: .now)
            return mockCalendarEntries(for: today.startOfMonth(using: calendar))
                .values
                .filter { $0.photoCount > 0 }
                .map { calendar.startOfDay(for: $0.date) }
        }

        return photoDaySummariesByKey.values
            .filter { $0.photoCount > 0 }
            .map { calendar.startOfDay(for: $0.date) }
    }

    private func autoPickCandidates(from items: [PhotoAssetItem], for date: Date) -> [PhotoAssetItem] {
        let excluded = excludedIdentifiersByDay[DayKeyFormatter.dayString(from: date)] ?? []
        return items.filter { item in
            item.asset.mediaSubtypes.contains(.photoScreenshot) == false &&
            excluded.contains(item.id) == false
        }
    }

    private func isScreenshotIdentifier(_ identifier: String) -> Bool {
        if let cachedAsset = assetLookup[identifier] {
            return cachedAsset.asset.mediaSubtypes.contains(.photoScreenshot)
        }

        guard let asset = photoLibraryService.fetchAsset(localIdentifier: identifier) else {
            return false
        }

        assetLookup[identifier] = PhotoAssetItem(asset: asset)
        return asset.mediaSubtypes.contains(.photoScreenshot)
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
