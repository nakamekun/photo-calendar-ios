import SwiftUI

@main
struct PhotoCalendarApp: App {
    private enum ScreenshotVariant: String {
        case hero
        case habit
        case pick
        case memories
        case streak
    }

    private static let launchArguments = ProcessInfo.processInfo.arguments
    private static let launchEnvironment = ProcessInfo.processInfo.environment
    private static let isPreviewModeEnabled =
        launchArguments.contains("--preview-mode") ||
        launchEnvironment["APP_STORE_PREVIEW_MODE"] == "1"
    private static let isMockCalendarUIEnabled =
        launchArguments.contains("--mock-calendar-ui") ||
        launchEnvironment["MOCK_CALENDAR_UI"] == "1"
    private static let hidesPreviewDebugBadge =
        launchArguments.contains("--hide-preview-debug-badge") ||
        launchEnvironment["HIDE_PREVIEW_DEBUG_BADGE"] == "1"
    private static let screenshotVariant = launchArguments
        .first(where: { $0.hasPrefix("--screenshot-variant=") })
        .flatMap { $0.split(separator: "=").last }
        .flatMap { ScreenshotVariant(rawValue: String($0)) }

    @StateObject private var photoLibraryViewModel = PhotoLibraryViewModel(
        isPreviewMode: Self.isPreviewModeEnabled,
        isMockDataEnabled: Self.isMockCalendarUIEnabled,
        showsPreviewDebugBadge: Self.hidesPreviewDebugBadge == false
    )

    init() {
        if Self.isPreviewModeEnabled {
            print("APP_STORE_PREVIEW_MODE=1 detected at launch. Preview mode enabled.")
        }
    }

    var body: some Scene {
        WindowGroup {
            CalendarView(
                photoLibraryViewModel: photoLibraryViewModel,
                screenshotVariant: Self.screenshotVariant?.rawValue
            )
        }
    }
}
