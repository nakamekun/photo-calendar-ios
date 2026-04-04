import Foundation

enum CalendarThumbnailSource: Hashable {
    case asset(PhotoAssetItem)
    case mock(MockCalendarPhoto)
}

struct MockCalendarPhoto: Identifiable, Hashable {
    enum Kind: CaseIterable, Hashable {
        case child
        case food
        case dailyLife
    }

    let id: String
    let date: Date
    let kind: Kind
    let fileName: String
}

struct CalendarPreviewItem: Identifiable, Hashable {
    let date: Date
    let thumbnailSource: CalendarThumbnailSource

    var id: String {
        switch thumbnailSource {
        case .asset(let item):
            return item.id
        case .mock(let mock):
            return mock.id
        }
    }
}

struct MemoryTimelineEntry: Identifiable, Hashable {
    let date: Date
    let source: CalendarThumbnailSource

    var id: String {
        DayKeyFormatter.dayString(from: date)
    }
}

struct CalendarDay: Identifiable, Hashable {
    let date: Date
    let isWithinDisplayedMonth: Bool
    let isToday: Bool
    let photoCount: Int
    let hasRepresentativePhoto: Bool
    let isInCurrentStreak: Bool
    let representativeAsset: PhotoAssetItem?
    let thumbnailSource: CalendarThumbnailSource?

    var id: String { DayKeyFormatter.dayString(from: date) }
    var dayNumberText: String { String(Calendar.current.component(.day, from: date)) }
    var hasAnyPhotos: Bool { photoCount > 0 }
}
