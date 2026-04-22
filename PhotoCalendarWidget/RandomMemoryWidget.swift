import Photos
import SwiftUI
import WidgetKit

struct RandomMemoryEntry: TimelineEntry {
    let date: Date
    let memoryDayKey: String?
    let memoryDateText: String?
    let image: UIImage?
}

private struct RandomMemoryCandidate {
    let dayKey: String
    let dateText: String
    let assetIdentifier: String
}

private struct WidgetMemorySelection: Codable {
    let dayKey: String
    let assetIdentifier: String
    let bucketStart: Date
}

struct RandomMemoryProvider: TimelineProvider {
    private static let timelineIntervalHours = 3

    func placeholder(in context: Context) -> RandomMemoryEntry {
        RandomMemoryEntry(
            date: .now,
            memoryDayKey: DayKeyFormatter.dayString(from: .now),
            memoryDateText: "Apr 12, 2024",
            image: nil
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (RandomMemoryEntry) -> Void) {
        completion(loadEntry(for: .now, family: context.family))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RandomMemoryEntry>) -> Void) {
        let calendar = Calendar.current
        let nextRefresh = calendar.date(
            byAdding: .hour,
            value: Self.timelineIntervalHours,
            to: .now
        ) ?? .now
        completion(Timeline(entries: [loadEntry(for: .now, family: context.family)], policy: .after(nextRefresh)))
    }

    private func loadEntry(for entryDate: Date, family: WidgetFamily) -> RandomMemoryEntry {
        let targetSize = Self.imageTargetSize(for: family)
        let bucketStart = Self.bucketStart(for: entryDate)
        let selectionStore = WidgetMemorySelectionStore()
        let candidates = pickedCandidates()

        // Widget memories are intentionally picked-only. Randomness happens only
        // while building timeline entries. Each widget family owns an independent
        // selection so a reload caused by another size does not reshuffle this one.
        if let storedSelection = selectionStore.selection(for: family),
           storedSelection.bucketStart == bucketStart {
            if let candidate = candidates.first(where: {
                $0.dayKey == storedSelection.dayKey &&
                $0.assetIdentifier == storedSelection.assetIdentifier
            }),
               let image = WidgetPhotoLoader.image(for: candidate.assetIdentifier, targetSize: targetSize) {
                return RandomMemoryEntry(
                    date: entryDate,
                    memoryDayKey: candidate.dayKey,
                    memoryDateText: candidate.dateText,
                    image: image
                )
            }

            // If the app changes the pick for the same day, keep the widget on
            // that day and update only the selected asset. The day changes only
            // after that day is no longer picked.
            if let sameDayCandidate = candidates.first(where: { $0.dayKey == storedSelection.dayKey }),
               let image = WidgetPhotoLoader.image(for: sameDayCandidate.assetIdentifier, targetSize: targetSize) {
                selectionStore.setSelection(
                    WidgetMemorySelection(
                        dayKey: sameDayCandidate.dayKey,
                        assetIdentifier: sameDayCandidate.assetIdentifier,
                        bucketStart: bucketStart
                    ),
                    for: family
                )

                return RandomMemoryEntry(
                    date: entryDate,
                    memoryDayKey: sameDayCandidate.dayKey,
                    memoryDateText: sameDayCandidate.dateText,
                    image: image
                )
            }
        }

        for candidate in candidates.shuffled() {
            guard let image = WidgetPhotoLoader.image(
                for: candidate.assetIdentifier,
                targetSize: targetSize
            ) else {
                continue
            }

            selectionStore.setSelection(
                WidgetMemorySelection(
                    dayKey: candidate.dayKey,
                    assetIdentifier: candidate.assetIdentifier,
                    bucketStart: bucketStart
                ),
                for: family
            )

            return RandomMemoryEntry(
                date: entryDate,
                memoryDayKey: candidate.dayKey,
                memoryDateText: candidate.dateText,
                image: image
            )
        }

        return RandomMemoryEntry(
            date: entryDate,
            memoryDayKey: nil,
            memoryDateText: nil,
            image: nil
        )
    }

    private static func bucketStart(for date: Date) -> Date {
        let interval = TimeInterval(timelineIntervalHours * 60 * 60)
        return Date(timeIntervalSince1970: floor(date.timeIntervalSince1970 / interval) * interval)
    }

    private func pickedCandidates() -> [RandomMemoryCandidate] {
        SelectedPhotoStore().cachedSelections().compactMap { dayKey, selection in
            guard selection.representativeIdentifier.isEmpty == false,
                  let memoryDate = DayKeyFormatter.date(fromDayString: dayKey)
            else {
                return nil
            }

            return RandomMemoryCandidate(
                dayKey: dayKey,
                dateText: Self.memoryDateFormatter.string(from: memoryDate),
                assetIdentifier: selection.representativeIdentifier
            )
        }
    }

    private static func imageTargetSize(for family: WidgetFamily) -> CGSize {
        switch family {
        case .systemLarge:
            return CGSize(width: 900, height: 900)
        case .systemMedium:
            return CGSize(width: 720, height: 360)
        default:
            return CGSize(width: 520, height: 520)
        }
    }

    private static let memoryDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()
}

private final class WidgetMemorySelectionStore {
    private let userDefaults: UserDefaults?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        userDefaults = UserDefaults(suiteName: AppSharedConfiguration.appGroupIdentifier)
    }

    func selection(for family: WidgetFamily) -> WidgetMemorySelection? {
        guard let data = userDefaults?.data(forKey: key(for: family)) else { return nil }
        return try? decoder.decode(WidgetMemorySelection.self, from: data)
    }

    func setSelection(_ selection: WidgetMemorySelection, for family: WidgetFamily) {
        guard let data = try? encoder.encode(selection) else { return }
        userDefaults?.set(data, forKey: key(for: family))
    }

    private func key(for family: WidgetFamily) -> String {
        switch family {
        case .systemSmall:
            return "random-memory-widget-selection-small-v1"
        case .systemMedium:
            return "random-memory-widget-selection-medium-v1"
        case .systemLarge:
            return "random-memory-widget-selection-large-v1"
        default:
            return "random-memory-widget-selection-default-v1"
        }
    }
}

private enum WidgetPhotoLoader {
    static func image(for localIdentifier: String, targetSize: CGSize) -> UIImage? {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = fetchResult.firstObject else { return nil }

        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false
        options.isSynchronous = true

        var image: UIImage?
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { resolvedImage, _ in
            image = resolvedImage
        }

        return image
    }
}

struct RandomMemoryWidgetView: View {
    let entry: RandomMemoryEntry
    @Environment(\.widgetFamily) private var widgetFamily

    var body: some View {
        ZStack {
            if let image = entry.image {
                fullBleedImage(image)
            } else {
                placeholder
            }
        }
        .containerBackground(Color.black, for: .widget)
        .widgetURL(deepLinkURL)
    }

    private var deepLinkURL: URL? {
        guard let memoryDayKey = entry.memoryDayKey else { return nil }
        var components = URLComponents()
        components.scheme = AppSharedConfiguration.deepLinkScheme
        components.host = "day"
        components.queryItems = [
            URLQueryItem(name: "date", value: memoryDayKey)
        ]
        return components.url
    }

    private func fullBleedImage(_ image: UIImage) -> some View {
        GeometryReader { proxy in
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
                .overlay(alignment: .bottomLeading) {
                    if let memoryDateText = entry.memoryDateText {
                        Text(memoryDateText)
                            .font(dateLabelFont)
                            .foregroundStyle(.white)
                            .padding(.horizontal, widgetFamily == .systemLarge ? 11 : 8)
                            .padding(.vertical, widgetFamily == .systemLarge ? 7 : 5)
                            .background(Color.black.opacity(0.42), in: Capsule())
                            .padding(widgetFamily == .systemLarge ? 14 : 10)
                    }
                }
        }
        .clipped()
        .ignoresSafeArea()
    }

    private var placeholder: some View {
        VStack(spacing: widgetFamily == .systemSmall ? 8 : 10) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: placeholderIconSize, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))

            Text("No memories yet")
                .font(placeholderTextFont.weight(.semibold))
                .foregroundStyle(.white.opacity(0.78))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [Color.black, Color(red: 0.08, green: 0.09, blue: 0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var dateLabelFont: Font {
        widgetFamily == .systemLarge ? .caption.weight(.semibold) : .caption2.weight(.semibold)
    }

    private var placeholderIconSize: CGFloat {
        switch widgetFamily {
        case .systemLarge:
            return 36
        case .systemSmall:
            return 24
        default:
            return 30
        }
    }

    private var placeholderTextFont: Font {
        switch widgetFamily {
        case .systemLarge:
            return .headline
        case .systemSmall:
            return .caption
        default:
            return .callout
        }
    }
}

struct RandomMemoryWidget: Widget {
    let kind = AppSharedConfiguration.randomMemoryWidgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RandomMemoryProvider()) { entry in
            RandomMemoryWidgetView(entry: entry)
        }
        .configurationDisplayName("Random Memory")
        .description("Shows a picked memory from your photo calendar.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

@main
struct PhotoCalendarWidgetBundle: WidgetBundle {
    var body: some Widget {
        RandomMemoryWidget()
    }
}
