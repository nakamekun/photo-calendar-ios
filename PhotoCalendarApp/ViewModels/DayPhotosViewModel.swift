import Combine
import Foundation

@MainActor
final class DayPhotosViewModel: ObservableObject {
    @Published private(set) var assets: [PhotoAssetItem] = []
    @Published private(set) var representativeAssetID: String?

    let date: Date

    private let photoLibraryViewModel: PhotoLibraryViewModel
    private var cancellable: AnyCancellable?
    private static let navigationDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
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
        reload()
    }

    var navigationTitle: String {
        Self.navigationDateFormatter.string(from: date)
    }

    var helperText: String {
        if Calendar.current.isDateInToday(date) {
            return "Choose one photo to keep for today."
        } else {
            return "Choose one photo that feels like this day."
        }
    }

    func timeText(for date: Date) -> String {
        Self.timeFormatter.string(from: date)
    }

    func reload() {
        assets = photoLibraryViewModel.assets(for: date)
        representativeAssetID = photoLibraryViewModel.representativeAsset(for: date)?.id
    }

    func isRepresentative(_ asset: PhotoAssetItem) -> Bool {
        representativeAssetID == asset.id
    }

    func selectRepresentative(_ asset: PhotoAssetItem) {
        photoLibraryViewModel.setRepresentativeAsset(asset, for: date)
        reload()
    }

    private func bind() {
        cancellable = photoLibraryViewModel.$lastUpdated.sink { [weak self] _ in
            self?.reload()
        }
    }
}
