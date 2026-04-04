import SwiftUI

struct OnThisDaySectionView: View {
    let items: [OnThisDayItem]
    let photoLibraryViewModel: PhotoLibraryViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("On This Day")
                    .font(.title3.weight(.semibold))

                Spacer()

                Text("Photos from this date")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if items.isEmpty {
                EmptyStateView(
                    title: "Nothing here yet",
                    message: "Keep saving one photo each day and memories from this date will appear over time.",
                    systemImageName: "clock.arrow.trianglehead.counterclockwise.rotate.90"
                )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(items) { item in
                            NavigationLink {
                                DayPhotosView(date: item.date, photoLibraryViewModel: photoLibraryViewModel)
                            } label: {
                                VStack(alignment: .leading, spacing: 10) {
                                    AssetImageView(
                                        asset: item.asset.asset,
                                        contentMode: .aspectFill,
                                        targetSize: CGSize(width: 240, height: 160)
                                    )
                                    .frame(width: 220, height: 132)
                                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.yearText)
                                            .font(.headline)
                                            .foregroundStyle(.primary)

                                        Text(item.englishDateText)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(14)
                                .background(
                                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                                        .fill(Color(.secondarySystemBackground))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}
