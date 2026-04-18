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
    private var pixelSideLength: CGFloat { sideLength * UIScreen.main.scale }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            AssetImageView(
                asset: asset,
                contentMode: .aspectFill,
                targetSize: CGSize(width: pixelSideLength, height: pixelSideLength),
                deliveryMode: .fastFormat,
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
    let upgradedDeliveryMode: PHImageRequestOptionsDeliveryMode?
    let cornerRadius: CGFloat
    let showsProgress: Bool

    @State private var image: UIImage?
    @State private var lastLoadedKey = ""
    @State private var currentRequestID: PHImageRequestID = PHInvalidImageRequestID
    @State private var upgradeRequestID: PHImageRequestID = PHInvalidImageRequestID
    private let photoLibraryService = PhotoLibraryService()

    init(
        asset: PHAsset,
        contentMode: PHImageContentMode,
        targetSize: CGSize,
        deliveryMode: PHImageRequestOptionsDeliveryMode = .highQualityFormat,
        upgradedDeliveryMode: PHImageRequestOptionsDeliveryMode? = nil,
        cornerRadius: CGFloat = 22,
        showsProgress: Bool = true
    ) {
        self.asset = asset
        self.contentMode = contentMode
        self.targetSize = targetSize
        self.deliveryMode = deliveryMode
        self.upgradedDeliveryMode = upgradedDeliveryMode
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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else if showsProgress {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
                    .overlay {
                        ProgressView()
                            .tint(.blue)
                    }
            }
        }
        .task(id: loadKey) {
            loadImage()
        }
        .onDisappear {
            cancelImageRequest()
        }
    }

    private var loadKey: String {
        "\(asset.localIdentifier)-\(Int(targetSize.width))x\(Int(targetSize.height))-\(contentMode.rawValue)-\(deliveryMode.rawValue)"
    }

    private func loadImage() {
        guard lastLoadedKey != loadKey else { return }
        lastLoadedKey = loadKey
        image = nil
        cancelImageRequest()
        let requestedKey = loadKey

        currentRequestID = photoLibraryService.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: contentMode,
            deliveryMode: deliveryMode
        ) { image in
            Task { @MainActor in
                guard self.lastLoadedKey == requestedKey else { return }
                self.image = image
                self.requestUpgradeIfNeeded(for: requestedKey)
            }
        }
    }

    private func cancelImageRequest() {
        photoLibraryService.cancelImageRequest(currentRequestID)
        photoLibraryService.cancelImageRequest(upgradeRequestID)
        currentRequestID = PHInvalidImageRequestID
        upgradeRequestID = PHInvalidImageRequestID
    }

    private func requestUpgradeIfNeeded(for requestedKey: String) {
        guard let upgradedDeliveryMode, upgradedDeliveryMode != deliveryMode else { return }
        guard upgradeRequestID == PHInvalidImageRequestID else { return }

        upgradeRequestID = photoLibraryService.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: contentMode,
            deliveryMode: upgradedDeliveryMode
        ) { image in
            Task { @MainActor in
                guard self.lastLoadedKey == requestedKey else { return }
                self.image = image
            }
        }
    }
}
