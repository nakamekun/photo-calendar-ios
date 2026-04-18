import SwiftUI
import UIKit

struct CalendarThumbnailContentView: View {
    let source: CalendarThumbnailSource
    let targetSize: CGSize
    let cornerRadius: CGFloat
    let showsProgress: Bool

    init(
        source: CalendarThumbnailSource,
        targetSize: CGSize,
        cornerRadius: CGFloat = 20,
        showsProgress: Bool = false
    ) {
        self.source = source
        self.targetSize = targetSize
        self.cornerRadius = cornerRadius
        self.showsProgress = showsProgress
    }

    var body: some View {
        switch source {
        case .asset(let item):
            AssetImageView(
                asset: item.asset,
                contentMode: .aspectFill,
                targetSize: targetSize,
                deliveryMode: .fastFormat,
                upgradedDeliveryMode: .opportunistic,
                cornerRadius: cornerRadius,
                showsProgress: showsProgress
            )
        case .mock(let mock):
            MockCalendarThumbnailView(mock: mock, cornerRadius: cornerRadius)
        }
    }
}

private struct MockCalendarThumbnailView: View {
    let mock: MockCalendarPhoto
    let cornerRadius: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(.secondarySystemBackground))

            if let image = PreviewSampleImageStore.shared.image(named: mock.fileName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        .clipped()
    }
}

final class PreviewSampleImageStore {
    static let shared = PreviewSampleImageStore()

    private let cache = NSCache<NSString, UIImage>()

    private init() {}

    func image(named fileName: String) -> UIImage? {
        if let cached = cache.object(forKey: fileName as NSString) {
            return cached
        }

        guard
            let url = Bundle.main.url(forResource: fileName, withExtension: nil, subdirectory: "sample"),
            let data = try? Data(contentsOf: url),
            let image = UIImage(data: data)
        else {
            return nil
        }

        cache.setObject(image, forKey: fileName as NSString)
        return image
    }
}

struct CalendarDayCellView: View {
    let day: CalendarDay
    let isPressed: Bool

    private let cellHeight: CGFloat = 88
    private let cellCornerRadius: CGFloat = 18
    private let thumbnailCornerRadius: CGFloat = 16
    private let thumbnailSide: CGFloat = 38
    private let thumbnailHorizontalInset: CGFloat = 5
    private let thumbnailBottomInset: CGFloat = 5
    private let dayBadgeSize: CGFloat = 30

    var body: some View {
        ZStack {
            backgroundShape
                .fill(baseBackground)

            thumbnailPanel

            backgroundShape
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(day.isToday ? 0.06 : 0.02),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .center
                    )
                )

            if day.isInCurrentStreak {
                backgroundShape
                    .fill(Color.blue.opacity(day.isToday ? 0.08 : 0.04))

                backgroundShape
                    .strokeBorder(Color.blue.opacity(day.isToday ? 0.26 : 0.16), lineWidth: 1)
                    .padding(2)
            }

            VStack(spacing: 0) {
                dayBadge
                Spacer(minLength: day.hasRepresentativePhoto ? 22 : 28)
                statusFooter
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, day.hasRepresentativePhoto ? 8 : 10)
        }
        .frame(maxWidth: .infinity)
        .frame(height: cellHeight)
        .clipShape(backgroundShape)
        .overlay(
            backgroundShape
                .strokeBorder(borderColor, lineWidth: day.isToday ? 1.6 : 1)
        )
        .opacity(day.isWithinDisplayedMonth ? 1 : 0.36)
        .scaleEffect(isPressed ? 0.965 : 1)
        .shadow(color: shadowColor, radius: 5, y: 2)
        .animation(.spring(response: 0.22, dampingFraction: 0.8), value: isPressed)
        .animation(.easeInOut(duration: 0.22), value: day.isToday)
        .animation(.easeInOut(duration: 0.24), value: day.hasRepresentativePhoto)
        .animation(.easeInOut(duration: 0.24), value: day.isInCurrentStreak)
    }

    @ViewBuilder
    private var thumbnailPanel: some View {
        if let thumbnailSource = day.thumbnailSource {
            GeometryReader { proxy in
                let side = min(
                    thumbnailSide,
                    max(0, proxy.size.width - (thumbnailHorizontalInset * 2))
                )

                CalendarThumbnailContentView(
                    source: thumbnailSource,
                    targetSize: CGSize(
                        width: side * UIScreen.main.scale,
                        height: side * UIScreen.main.scale
                    ),
                    cornerRadius: thumbnailCornerRadius,
                    showsProgress: false
                )
                .frame(width: side, height: side)
                .overlay(
                    RoundedRectangle(cornerRadius: thumbnailCornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: thumbnailCornerRadius, style: .continuous))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, thumbnailBottomInset)
            }
            .transition(.scale(scale: 0.94).combined(with: .opacity))
        }
    }

    private var dayBadge: some View {
        Text(day.dayNumberText)
            .font(.system(size: 16, weight: day.isToday ? .bold : .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .monospacedDigit()
            .foregroundStyle(foregroundColor)
            .frame(width: dayBadgeSize, height: dayBadgeSize)
            .background(dayBadgeBackground, in: Circle())
            .frame(maxWidth: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var statusFooter: some View {
        if day.hasRepresentativePhoto {
            HStack(spacing: 4) {
                Spacer(minLength: 0)
                Image(systemName: "star.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(7)
                    .background(Color.black.opacity(0.28), in: Circle())
            }
        } else if day.hasAnyPhotos {
            HStack(spacing: 4) {
                Spacer(minLength: 0)
                Circle()
                    .fill(Color.blue.opacity(0.72))
                    .frame(width: 6, height: 6)
            }
        }
    }

    private var backgroundShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cellCornerRadius, style: .continuous)
    }

    private var foregroundColor: Color {
        if day.hasAnyPhotos {
            return .blue
        }

        return day.isWithinDisplayedMonth ? .primary : .secondary
    }

    private var borderColor: Color {
        if day.isToday {
            return Color.blue.opacity(0.95)
        }

        if day.hasRepresentativePhoto {
            return Color.white.opacity(0.1)
        }

        if day.hasAnyPhotos {
            return Color.blue.opacity(0.14)
        }

        return Color.primary.opacity(0.06)
    }

    private var shadowColor: Color {
        day.isWithinDisplayedMonth ? Color.black.opacity(0.045) : .clear
    }

    private var dayBadgeBackground: Color {
        if day.hasAnyPhotos {
            return Color.blue.opacity(day.isToday ? 0.18 : 0.1)
        }

        if day.isToday {
            return Color.blue.opacity(0.18)
        }

        return Color(.systemBackground).opacity(0.82)
    }

    private var baseBackground: some ShapeStyle {
        if day.hasRepresentativePhoto {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color(.secondarySystemBackground),
                        Color(.tertiarySystemBackground)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }

        if day.hasAnyPhotos {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color.blue.opacity(day.isToday ? 0.18 : 0.14),
                        Color(.secondarySystemBackground)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }

        return AnyShapeStyle(Color(.tertiarySystemBackground))
    }
}
