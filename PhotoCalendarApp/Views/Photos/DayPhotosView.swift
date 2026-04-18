import SwiftUI

struct DayPhotosView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var photoLibraryViewModel: PhotoLibraryViewModel
    @StateObject private var viewModel: DayPhotosViewModel
    @State private var representativeSwipeOffset: CGFloat = 0
    private let onReturnToCalendar: () -> Void

    private let gridSpacing: CGFloat = 12
    private let gridColumnCount: CGFloat = 3
    private let photoCellCornerRadius: CGFloat = 22
    private let representativeCornerRadius: CGFloat = 24
    private let representativeHeight: CGFloat = 168

    private var previewMockPhotos: [MockCalendarPhoto] {
        photoLibraryViewModel.previewMockPhotos(for: viewModel.date)
    }

    init(
        date: Date,
        photoLibraryViewModel: PhotoLibraryViewModel,
        onReturnToCalendar: @escaping () -> Void = {}
    ) {
        self.photoLibraryViewModel = photoLibraryViewModel
        self.onReturnToCalendar = onReturnToCalendar
        _viewModel = StateObject(wrappedValue: DayPhotosViewModel(date: date, photoLibraryViewModel: photoLibraryViewModel))
    }

    var body: some View {
        GeometryReader { proxy in
            let contentWidth = max(proxy.size.width - 40, 0)
            let tileSide = floor((contentWidth - (gridSpacing * (gridColumnCount - 1))) / gridColumnCount)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerCard

                    contentSection(tileSide: tileSide)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 10) {
                    dayShiftButton(
                        systemImage: "chevron.left",
                        isEnabled: viewModel.previousPhotoDate != nil,
                        action: viewModel.moveToPreviousPhotoDay
                    )

                    Text(viewModel.navigationTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    dayShiftButton(
                        systemImage: "chevron.right",
                        isEnabled: viewModel.nextPhotoDate != nil,
                        action: viewModel.moveToNextPhotoDay
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func contentSection(tileSide: CGFloat) -> some View {
        if viewModel.assets.isEmpty && previewMockPhotos.isEmpty {
            EmptyStateView(
                title: "No photos for this day",
                message: "Photos taken on this date will appear here.",
                systemImageName: "photo"
            )
        } else if viewModel.assets.isEmpty {
            previewMockGrid(tileSide: tileSide)
        } else {
            LazyVGrid(columns: gridColumns(tileSide: tileSide), spacing: gridSpacing) {
                ForEach(viewModel.assets) { asset in
                    NavigationLink {
                        PhotoDetailView(
                            assets: viewModel.assets,
                            date: viewModel.date,
                            initialAssetID: asset.id,
                            currentRepresentativeID: viewModel.representativeAssetID,
                            selectRepresentative: { selected in
                                viewModel.selectRepresentative(selected)
                            }
                        )
                    } label: {
                        PhotoThumbnailView(
                            asset: asset.asset,
                            isRepresentative: viewModel.isRepresentative(asset),
                            selectRepresentative: {
                                viewModel.selectRepresentative(asset)
                            },
                            sideLength: tileSide
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var headerCard: some View {
        let scale = UIScreen.main.scale
        let headerWidth = max(UIScreen.main.bounds.width - 40, 0)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Text(viewModel.helperText)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                if viewModel.representativeAsset != nil {
                    Label("Selected", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.blue)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.12), in: Capsule())
                }
            }

            if let representativeAsset = viewModel.representativeAsset {
                AssetImageView(
                    asset: representativeAsset.asset,
                    contentMode: .aspectFill,
                    targetSize: CGSize(width: headerWidth * scale, height: representativeHeight * scale),
                    deliveryMode: .opportunistic,
                    cornerRadius: representativeCornerRadius,
                    showsProgress: false
                )
                .frame(maxWidth: .infinity)
                .frame(height: representativeHeight)
                .clipShape(RoundedRectangle(cornerRadius: representativeCornerRadius, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    Text(viewModel.isManualRepresentative ? "Saved: \(viewModel.timeText(for: representativeAsset.creationDate))" : "Picked: \(viewModel.timeText(for: representativeAsset.creationDate))")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.black.opacity(0.42), in: Capsule())
                        .padding(14)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: representativeCornerRadius, style: .continuous)
                        .strokeBorder(Color.blue.opacity(0.7), lineWidth: 2)
                }
                .offset(x: representativeSwipeOffset)
                .rotationEffect(.degrees(Double(representativeSwipeOffset / 38)))
                .contentShape(Rectangle())
                .highPriorityGesture(representativeClearGesture, including: .gesture)
                .animation(.spring(response: 0.25, dampingFraction: 0.82), value: representativeSwipeOffset)
                .shadow(color: Color.blue.opacity(0.08), radius: 10, y: 4)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    RoundedRectangle(cornerRadius: representativeCornerRadius, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .frame(maxWidth: .infinity)
                        .frame(height: representativeHeight)
                        .overlay {
                            VStack(spacing: 10) {
                                Image(systemName: "photo.on.rectangle.angled")
                                    .font(.system(size: 28, weight: .semibold))
                                    .foregroundStyle(.secondary)

                                Text("No representative photo selected")
                                    .font(.headline)
                                    .foregroundStyle(.primary)

                                Text("Tap a photo below to choose one manually.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(20)
                        }

                    if viewModel.isAutoPickDisabled {
                        Text("Auto-pick is off for this date until you choose a photo manually.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.blue.opacity(0.12), Color(.secondarySystemBackground)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
    }

    private var representativeClearGesture: some Gesture {
        DragGesture(minimumDistance: 16)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                representativeSwipeOffset = value.translation.width
            }
            .onEnded { value in
                let isHorizontal = abs(value.translation.width) > abs(value.translation.height)
                defer { representativeSwipeOffset = 0 }
                guard isHorizontal, abs(value.translation.width) > 80 else { return }
                viewModel.clearRepresentative()
            }
    }

    private func previewMockGrid(tileSide: CGFloat) -> some View {
        return VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: gridColumns(tileSide: tileSide), spacing: gridSpacing) {
                ForEach(previewMockPhotos) { mock in
                    VStack(alignment: .leading, spacing: 0) {
                        CalendarThumbnailContentView(
                            source: .mock(mock),
                            targetSize: CGSize(
                                width: tileSide * UIScreen.main.scale,
                                height: tileSide * UIScreen.main.scale
                            ),
                            cornerRadius: photoCellCornerRadius,
                            showsProgress: false
                        )
                        .frame(width: tileSide, height: tileSide)
                        .aspectRatio(1, contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: photoCellCornerRadius, style: .continuous))
                    }
                    .frame(width: tileSide, height: tileSide)
                    .background(
                        RoundedRectangle(cornerRadius: photoCellCornerRadius, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )
                    .clipShape(RoundedRectangle(cornerRadius: photoCellCornerRadius, style: .continuous))
                }
            }
        }
    }

    private func dayShiftButton(systemImage: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        return Button(action: action) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isEnabled ? Color.primary : Color.secondary.opacity(0.45))
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(isEnabled ? 0.12 : 0.06), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(isEnabled == false)
    }

    private func gridColumns(tileSide: CGFloat) -> [GridItem] {
        Array(
            repeating: GridItem(.fixed(tileSide), spacing: gridSpacing, alignment: .top),
            count: Int(gridColumnCount)
        )
    }
}
