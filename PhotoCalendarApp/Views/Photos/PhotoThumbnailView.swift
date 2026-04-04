import Photos
import SwiftUI
import UIKit

struct PhotoThumbnailView: View {
    let asset: PHAsset
    let isRepresentative: Bool
    let selectRepresentative: () -> Void
    let sideLength: CGFloat
    private let cornerRadius: CGFloat = 22
    private let badgePadding: CGFloat = 10

    var body: some View {
        ZStack(alignment: .topTrailing) {
            AssetImageView(
                asset: asset,
                contentMode: .aspectFill,
                targetSize: CGSize(width: sideLength * 2, height: sideLength * 2),
                cornerRadius: cornerRadius
            )
            .frame(width: sideLength, height: sideLength)
            .aspectRatio(1, contentMode: .fill)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

            Button(action: selectRepresentative) {
                Image(systemName: isRepresentative ? "star.fill" : "star")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isRepresentative ? .blue : .white)
                    .padding(badgePadding)
                    .background(.ultraThinMaterial, in: Circle())
                    .padding(badgePadding)
            }
            .buttonStyle(.plain)
        }
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(alignment: .bottomLeading) {
            if isRepresentative {
                Text("Selected")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(12)
                }
        }
        .frame(width: sideLength, height: sideLength)
    }
}

struct AssetImageView: View {
    let asset: PHAsset
    let contentMode: PHImageContentMode
    let targetSize: CGSize
    let deliveryMode: PHImageRequestOptionsDeliveryMode
    let cornerRadius: CGFloat
    let showsProgress: Bool

    @State private var image: UIImage?
    private let photoLibraryService = PhotoLibraryService()

    init(
        asset: PHAsset,
        contentMode: PHImageContentMode,
        targetSize: CGSize,
        deliveryMode: PHImageRequestOptionsDeliveryMode = .highQualityFormat,
        cornerRadius: CGFloat = 22,
        showsProgress: Bool = true
    ) {
        self.asset = asset
        self.contentMode = contentMode
        self.targetSize = targetSize
        self.deliveryMode = deliveryMode
        self.cornerRadius = cornerRadius
        self.showsProgress = showsProgress
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(.secondarySystemBackground))

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: targetSize.width / 2, height: targetSize.height / 2)
                    .clipped()
            } else if showsProgress {
                ProgressView()
                    .tint(.blue)
            }
        }
        .task(id: asset.localIdentifier) {
            loadImage()
        }
    }

    private func loadImage() {
        photoLibraryService.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: contentMode,
            deliveryMode: deliveryMode
        ) { image in
            Task { @MainActor in
                self.image = image
            }
        }
    }
}
