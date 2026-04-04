import SwiftUI

struct DayPhotosView: View {
    @ObservedObject private var photoLibraryViewModel: PhotoLibraryViewModel
    @StateObject private var viewModel: DayPhotosViewModel

    private let gridSpacing: CGFloat = 12
    private let gridColumnCount: CGFloat = 3
    private let photoCellCornerRadius: CGFloat = 22
    private var previewMockPhotos: [MockCalendarPhoto] {
        photoLibraryViewModel.previewMockPhotos(for: viewModel.date)
    }

    init(date: Date, photoLibraryViewModel: PhotoLibraryViewModel) {
        self.photoLibraryViewModel = photoLibraryViewModel
        _viewModel = StateObject(wrappedValue: DayPhotosViewModel(date: date, photoLibraryViewModel: photoLibraryViewModel))
    }

    var body: some View {
        GeometryReader { proxy in
            let contentWidth = max(proxy.size.width - 40, 0)
            let tileSide = floor((contentWidth - (gridSpacing * (gridColumnCount - 1))) / gridColumnCount)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerCard

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
                .padding(20)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(viewModel.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: viewModel.representativeAssetID)
        .sensoryFeedback(trigger: photoLibraryViewModel.currentStreak) { oldValue, newValue in
            guard newValue > oldValue else { return nil }
            return .impact(flexibility: .soft, intensity: 0.85)
        }
        .onAppear {
            viewModel.reload()
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Photos")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            Text(viewModel.helperText)
                .font(.headline)
                .foregroundStyle(.primary)

            if let representativeID = viewModel.representativeAssetID,
               let selected = viewModel.assets.first(where: { $0.id == representativeID }) {
                Text("Selected: \(viewModel.timeText(for: selected.creationDate))")
                    .font(.footnote)
                    .foregroundStyle(.blue)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
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
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.22), value: viewModel.representativeAssetID)
    }

    private func previewMockGrid(tileSide: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if photoLibraryViewModel.isPreviewMode {
                Text("Preview photos")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)
            }

            LazyVGrid(columns: gridColumns(tileSide: tileSide), spacing: gridSpacing) {
                ForEach(previewMockPhotos) { mock in
                    VStack(alignment: .leading, spacing: 0) {
                        CalendarThumbnailContentView(
                            source: .mock(mock),
                            targetSize: CGSize(width: tileSide * 2, height: tileSide * 2),
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
                    .overlay(
                        RoundedRectangle(cornerRadius: photoCellCornerRadius, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    )
                    .overlay(alignment: .bottomLeading) {
                        if mock.id == previewMockPhotos.first?.id {
                            Text("Selected")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.ultraThinMaterial, in: Capsule())
                                .padding(12)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: mock.id == previewMockPhotos.first?.id ? "star.fill" : "star")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(mock.id == previewMockPhotos.first?.id ? .blue : .white)
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                            .padding(10)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: photoCellCornerRadius, style: .continuous))
                }
            }
        }
    }

    private func gridColumns(tileSide: CGFloat) -> [GridItem] {
        Array(
            repeating: GridItem(.fixed(tileSide), spacing: gridSpacing, alignment: .top),
            count: Int(gridColumnCount)
        )
    }
}
