import Combine
import Foundation

@MainActor
final class DayPhotosViewModel: ObservableObject {
    @Published private(set) var assets: [PhotoAssetItem] = []
    @Published private(set) var date: Date
    @Published private(set) var representativeAssetID: String?
    @Published private(set) var isManualRepresentative = false
    @Published private(set) var isAutoPickDisabled = false
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

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeStyle = .short
        formatter.dateStyle = .none
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
        if isManualRepresentative {
            return "Chosen for this day"
        }

        if isAutoPickDisabled {
            return "No representative photo selected"
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

    var previousPhotoDate: Date? {
        photoLibraryViewModel.previousPhotoDate(from: date)
    }

    var nextPhotoDate: Date? {
        photoLibraryViewModel.nextPhotoDate(from: date)
    }

    func timeText(for date: Date) -> String {
        Self.timeFormatter.string(from: date)
    }

    func reload() {
        assets = photoLibraryViewModel.assets(for: date)
        representativeAssetID = photoLibraryViewModel.representativeAsset(for: date)?.id
        isManualRepresentative = photoLibraryViewModel.isManualRepresentative(for: date)
        isAutoPickDisabled = photoLibraryViewModel.isAutoPickDisabled(for: date)

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
        isManualRepresentative = true
        isAutoPickDisabled = false
    }

    func isRepresentative(_ asset: PhotoAssetItem) -> Bool {
        representativeAssetID == asset.id
    }

    func selectRepresentative(_ asset: PhotoAssetItem) {
        photoLibraryViewModel.setManualRepresentativeAsset(asset, for: date)
        representativeAssetID = asset.id
        displayedAssetID = asset.id
        isManualRepresentative = true
        isAutoPickDisabled = false
    }

    func clearRepresentative() {
        guard representativeAssetID != nil else { return }
        photoLibraryViewModel.disableAutoPick(for: date, excludingCurrentRepresentative: true)
        representativeAssetID = nil
        isManualRepresentative = false
        isAutoPickDisabled = true
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
