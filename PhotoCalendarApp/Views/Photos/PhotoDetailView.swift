import SwiftUI

struct PhotoDetailView: View {
    let assets: [PhotoAssetItem]
    let date: Date
    let initialAssetID: String
    let currentRepresentativeID: String?
    let selectRepresentative: (PhotoAssetItem) -> Void

    @State private var selectedAssetID: String
    @State private var representativeAssetID: String?

    private static let detailDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEEE, MMM d, yyyy"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    init(
        assets: [PhotoAssetItem],
        date: Date,
        initialAssetID: String,
        currentRepresentativeID: String?,
        selectRepresentative: @escaping (PhotoAssetItem) -> Void
    ) {
        self.assets = assets
        self.date = date
        self.initialAssetID = initialAssetID
        self.currentRepresentativeID = currentRepresentativeID
        self.selectRepresentative = selectRepresentative
        _selectedAssetID = State(initialValue: initialAssetID)
        _representativeAssetID = State(initialValue: currentRepresentativeID)
    }

    var body: some View {
        let screenBounds = UIScreen.main.bounds
        let scale = UIScreen.main.scale
        VStack(spacing: 0) {
            TabView(selection: $selectedAssetID) {
                ForEach(assets) { item in
                    AssetImageView(
                        asset: item.asset,
                        contentMode: .aspectFit,
                        targetSize: CGSize(width: screenBounds.width * scale, height: screenBounds.height * scale),
                        deliveryMode: selectedAssetID == item.id ? .opportunistic : .fastFormat,
                        upgradedDeliveryMode: selectedAssetID == item.id ? .highQualityFormat : nil
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .tag(item.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            if let selectedItem = selectedItem {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(Self.detailDateFormatter.string(from: date))
                            .font(.headline)

                        Text(Self.timeFormatter.string(from: selectedItem.creationDate))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        representativeAssetID = selectedItem.id
                        selectRepresentative(selectedItem)
                    } label: {
                        HStack {
                            Image(systemName: isRepresentative(selectedItem) ? "checkmark.circle.fill" : "star.fill")
                            Text(isRepresentative(selectedItem) ? "Selected for This Day" : "Set for This Day")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                }
                .padding(20)
                .background(Color(.systemBackground))
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var selectedItem: PhotoAssetItem? {
        assets.first(where: { $0.id == selectedAssetID })
    }

    private func isRepresentative(_ item: PhotoAssetItem) -> Bool {
        representativeAssetID == item.id
    }
}
