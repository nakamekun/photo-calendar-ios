import Combine
import Foundation
import Photos

@MainActor
final class DayPhotosViewModel: ObservableObject {
    @Published private(set) var assets: [PhotoAssetItem] = []
    @Published private(set) var date: Date
    @Published private(set) var representativeAssetID: String?
    @Published private(set) var selectionSource: DaySelectionSource?
    @Published private(set) var isAutoPickResolved = false
    @Published var displayedAssetID: String?

    private let photoLibraryViewModel: PhotoLibraryViewModel
    private var cancellable: AnyCancellable?
    private var hasUserSwiped = false
    private var fullDayLoadTask: Task<Void, Never>?

    private static let navigationMonthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    init(date: Date, photoLibraryViewModel: PhotoLibraryViewModel) {
        self.date = date.startOfDay()
        self.photoLibraryViewModel = photoLibraryViewModel
        bind()
        photoLibraryViewModel.loadDayIfNeeded(self.date)
        photoLibraryViewModel.prepareDayNavigationCache(around: self.date, targetSize: CGSize(width: 240, height: 240))
        scheduleFullDayLoad()
        reload()
    }

    var navigationTitle: String {
        "\(Self.navigationMonthDayFormatter.string(from: date)), \(Calendar.current.component(.year, from: date))"
    }

    var helperText: String {
        if selectionSource == .manual {
            return "Chosen for this day"
        }

        if selectionSource == .automatic {
            return "Picked automatically"
        }

        return "Representative photo"
    }

    var selectedAsset: PhotoAssetItem? {
        guard let displayedAssetID else { return nil }
        return assets.first(where: { $0.id == displayedAssetID })
    }

    var representativeAsset: PhotoAssetItem? {
        guard let representativeAssetID else { return nil }
        return assets.first(where: { $0.id == representativeAssetID })
    }

    var canClearRepresentative: Bool {
        representativeAssetID != nil
    }

    var canRandomPick: Bool {
        assets.contains { $0.asset.mediaSubtypes.contains(.photoScreenshot) == false }
    }

    var selectionStatusText: String? {
        switch selectionSource {
        case .manual:
            return "Picked manually"
        case .automatic:
            return "Auto-picked"
        case .none:
            return nil
        }
    }

    var shouldShowAutoPickResolvedHint: Bool {
        representativeAssetID == nil && isAutoPickResolved
    }

    var previousPhotoDate: Date? {
        photoLibraryViewModel.previousPhotoDate(from: date)
    }

    var nextPhotoDate: Date? {
        photoLibraryViewModel.nextPhotoDate(from: date)
    }

    func reload() {
        assets = photoLibraryViewModel.assets(for: date)
        representativeAssetID = photoLibraryViewModel.representativeAsset(for: date)?.id
        selectionSource = photoLibraryViewModel.selectionSource(for: date)
        isAutoPickResolved = photoLibraryViewModel.isAutoPickResolved(for: date)

        guard assets.isEmpty == false else {
            displayedAssetID = nil
            return
        }

        if hasUserSwiped == false {
            displayedAssetID = representativeAssetID ?? photoLibraryViewModel.latestAsset(for: date)?.id ?? assets.first?.id
            return
        }

        if let displayedAssetID, assets.contains(where: { $0.id == displayedAssetID }) {
            return
        }

        displayedAssetID = representativeAssetID ?? photoLibraryViewModel.latestAsset(for: date)?.id ?? assets.first?.id
    }

    func updateDisplayedAsset(id: String) {
        hasUserSwiped = true
        displayedAssetID = id
    }

    func saveDisplayedAssetAsRepresentative() {
        guard let selectedAsset else { return }
        photoLibraryViewModel.setManualRepresentativeAsset(selectedAsset, for: date)
        representativeAssetID = selectedAsset.id
        selectionSource = .manual
    }

    func isRepresentative(_ asset: PhotoAssetItem) -> Bool {
        representativeAssetID == asset.id
    }

    func selectRepresentative(_ asset: PhotoAssetItem) {
        photoLibraryViewModel.setManualRepresentativeAsset(asset, for: date)
        representativeAssetID = asset.id
        displayedAssetID = asset.id
        selectionSource = .manual
    }

    func clearRepresentative() {
        guard representativeAssetID != nil else { return }
        photoLibraryViewModel.clearRepresentativeSelection(for: date)
        representativeAssetID = nil
        selectionSource = nil
        isAutoPickResolved = true
    }

    func randomPickRepresentative() {
        guard let selected = photoLibraryViewModel.setRandomRepresentativeAsset(for: date) else { return }
        representativeAssetID = selected.id
        displayedAssetID = selected.id
        selectionSource = .manual
        isAutoPickResolved = true
    }

    func moveDay(by offset: Int) {
        guard let nextDate = Calendar.current.date(byAdding: .day, value: offset, to: date) else { return }
        setDate(nextDate)
    }

    func moveToPreviousPhotoDay() {
        guard let previousPhotoDate else { return }
        setDate(previousPhotoDate)
    }

    func moveToNextPhotoDay() {
        guard let nextPhotoDate else { return }
        setDate(nextPhotoDate)
    }

    func setDateComponent(year: Int? = nil, month: Int? = nil, day: Int? = nil) {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: date)

        if let year {
            components.year = year
        }
        if let month {
            components.month = month
        }

        let resolvedYear = components.year ?? calendar.component(.year, from: date)
        let resolvedMonth = components.month ?? calendar.component(.month, from: date)
        let maxDay = calendar.range(of: .day, in: .month, for: calendar.date(from: DateComponents(year: resolvedYear, month: resolvedMonth, day: 1)) ?? date)?.count ?? 31

        if let day {
            components.day = min(day, maxDay)
        } else {
            components.day = min(components.day ?? 1, maxDay)
        }

        guard let updatedDate = calendar.date(from: components) else { return }
        setDate(updatedDate)
    }

    func setDate(_ newDate: Date) {
        date = newDate.startOfDay()
        hasUserSwiped = false
        fullDayLoadTask?.cancel()
        photoLibraryViewModel.loadDayIfNeeded(date)
        photoLibraryViewModel.prepareDayNavigationCache(around: date, targetSize: CGSize(width: 240, height: 240))
        scheduleFullDayLoad()
        reload()
    }

    private func bind() {
        cancellable = photoLibraryViewModel.$lastUpdated.sink { [weak self] _ in
            self?.reload()
        }
    }

    private func scheduleFullDayLoad() {
        let targetDate = date
        fullDayLoadTask?.cancel()
        fullDayLoadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard Task.isCancelled == false else { return }
            await MainActor.run {
                self?.photoLibraryViewModel.loadDayFullyIfNeeded(targetDate)
            }
        }
    }

    deinit {
        fullDayLoadTask?.cancel()
    }
}
