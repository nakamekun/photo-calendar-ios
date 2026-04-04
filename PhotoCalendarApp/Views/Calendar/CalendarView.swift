import SwiftUI
import UIKit

struct CalendarView: View {
    private enum ScreenshotVariant: String {
        case hero
        case habit
        case pick
        case memories
        case streak

        var headline: String {
            switch self {
            case .hero:
                return "One Photo, Every Day"
            case .habit:
                return "Fill your days with memories"
            case .pick:
                return "Pick one photo for today"
            case .memories:
                return "Revisit your life, one day at a time"
            case .streak:
                return "Keep your streak going"
            }
        }

        var displayMode: DisplayMode {
            switch self {
            case .memories:
                return .memories
            case .hero, .habit, .pick, .streak:
                return .calendar
            }
        }

        var scrollTarget: SectionID? {
            switch self {
            case .hero:
                return .intro
            case .habit:
                return .calendar
            case .pick:
                return .preview
            case .memories:
                return nil
            case .streak:
                return .streak
            }
        }
    }

    private enum SectionID: Hashable {
        case intro
        case calendar
        case today
        case streak
        case preview
    }

    private enum DisplayMode: String, CaseIterable, Identifiable {
        case calendar = "Calendar"
        case memories = "Memories"

        var id: String { rawValue }
    }

    @ObservedObject var photoLibraryViewModel: PhotoLibraryViewModel
    @StateObject private var viewModel = CalendarViewModel()
    @State private var displayMode: DisplayMode
    @State private var shouldShowSecondarySections = false
    private let screenshotVariant: ScreenshotVariant?

    init(photoLibraryViewModel: PhotoLibraryViewModel, screenshotVariant: String? = nil) {
        self.photoLibraryViewModel = photoLibraryViewModel
        let parsedVariant = screenshotVariant.flatMap(ScreenshotVariant.init(rawValue:))
        self.screenshotVariant = parsedVariant
        _displayMode = State(initialValue: parsedVariant?.displayMode ?? .calendar)
    }

    var body: some View {
        NavigationStack {
            Group {
                if photoLibraryViewModel.authorizationState.canReadLibrary || photoLibraryViewModel.isMockDataEnabled {
                    contentView
                } else {
                    PermissionView(
                        authorizationState: photoLibraryViewModel.authorizationState,
                        requestAccess: {
                            Task {
                                await photoLibraryViewModel.requestPhotoAccess()
                            }
                        },
                        openSettings: openSettings
                    )
                }
            }
            .background(Color.black)
            .task {
                photoLibraryViewModel.handleInitialLoad()
                if photoLibraryViewModel.isPreviewMode {
                    shouldShowSecondarySections = true
                    return
                }
                guard shouldShowSecondarySections == false else { return }
                try? await Task.sleep(nanoseconds: 350_000_000)
                shouldShowSecondarySections = true
            }
            .sensoryFeedback(trigger: photoLibraryViewModel.currentStreak) { oldValue, newValue in
                guard newValue > oldValue else { return nil }
                return .impact(flexibility: .soft, intensity: 0.9)
            }
            .overlay(alignment: .topLeading) {
                if let screenshotVariant {
                    screenshotHeadline(screenshotVariant.headline)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var contentView: some View {
        VStack(spacing: 0) {
            modePicker

            TabView(selection: $displayMode) {
                calendarPage
                    .tag(DisplayMode.calendar)

                MemoriesTimelineView(photoLibraryViewModel: photoLibraryViewModel)
                    .tag(DisplayMode.memories)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .overlay {
            if photoLibraryViewModel.isLoading && photoLibraryViewModel.isPreviewMode == false {
                ProgressView("Loading photos...")
                    .padding(20)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
    }

    private var calendarPage: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    calendarIntro
                        .id(SectionID.intro)
                    calendarSection
                        .id(SectionID.calendar)
                    todayActionSection
                        .id(SectionID.today)
                    streakSummarySection
                        .id(SectionID.streak)

                    if shouldShowSecondarySections {
                        previewSection
                            .id(SectionID.preview)

                        OnThisDaySectionView(
                            items: photoLibraryViewModel.onThisDayPreviewItems,
                            photoLibraryViewModel: photoLibraryViewModel
                        )
                    }
                }
                .padding(20)
            }
            .task(id: shouldShowSecondarySections) {
                await scrollForScreenshotIfNeeded(using: proxy)
            }
            .task(id: displayMode) {
                await scrollForScreenshotIfNeeded(using: proxy)
            }
        }
    }

    private var modePicker: some View {
        HStack(spacing: 10) {
            ForEach(DisplayMode.allCases) { mode in
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        displayMode = mode
                    }
                } label: {
                    Text(mode.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(displayMode == mode ? Color.white : Color.white.opacity(0.62))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(displayMode == mode ? Color.white.opacity(0.14) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var calendarIntro: some View {
        VStack(alignment: .leading, spacing: 8) {
            if photoLibraryViewModel.showsPreviewDebugBadge {
                Text("Preview Mode Enabled")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.yellow.opacity(0.96))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.yellow.opacity(0.16), in: Capsule())
            }

            Text("One Photo a Day")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text(heroMessage)
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.68))
        }
    }

    private var todayActionSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Today's Photo")
                .font(.headline)
                .foregroundStyle(.white)

            NavigationLink {
                DayPhotosView(date: .now, photoLibraryViewModel: photoLibraryViewModel)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(photoLibraryViewModel.hasRepresentativePhoto(on: .now) ? "Update Today's Photo" : "Choose Today's Photo")
                            .font(.headline)

                        Text(todayButtonSubtitle)
                            .font(.footnote)
                            .foregroundStyle(Color.white.opacity(0.58))
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.5))
                }
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var streakSummarySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(photoLibraryViewModel.streakTitle)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.72))
                .contentTransition(.numericText())
                .animation(.spring(response: 0.3, dampingFraction: 0.82), value: photoLibraryViewModel.currentStreak)

            if photoLibraryViewModel.showsStreakPrompt {
                Text(photoLibraryViewModel.streakPrompt)
                    .font(.footnote)
                    .foregroundStyle(Color.white.opacity(0.46))
                    .transition(.opacity)
            } else {
                Text("A small ritual that quietly fills the month.")
                    .font(.footnote)
                    .foregroundStyle(Color.white.opacity(0.42))
            }
        }
        .padding(.horizontal, 4)
    }

    private var calendarSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            CalendarHeaderView(viewModel: viewModel)

            Text("Fill the month one chosen day at a time.")
                .font(.footnote)
                .foregroundStyle(Color.white.opacity(0.58))

            CalendarGridView(
                days: photoLibraryViewModel.calendarDays(for: viewModel.displayedMonth),
                photoLibraryViewModel: photoLibraryViewModel
            )
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .task(id: viewModel.displayedMonth) {
            photoLibraryViewModel.prepareCalendarThumbnailCache(
                for: viewModel.displayedMonth,
                targetSize: CGSize(width: 180, height: 180)
            )
        }
    }

    @ViewBuilder
    private var previewSection: some View {
        let items = photoLibraryViewModel.previewItems

        if items.isEmpty == false {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(photoLibraryViewModel.previewStripTitle())
                            .font(.headline)

                        Text(photoLibraryViewModel.previewStripSubtitle())
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text("Quick Pick")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.blue.opacity(0.12), in: Capsule())
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(items) { item in
                            NavigationLink {
                                DayPhotosView(date: item.date, photoLibraryViewModel: photoLibraryViewModel)
                            } label: {
                                CalendarPreviewCard(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(.secondarySystemBackground),
                                Color.blue.opacity(0.04)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
        }
    }

    private var heroMessage: String {
        let todayCount = photoLibraryViewModel.isPreviewMode
            ? photoLibraryViewModel.mockPhotoCount(on: .now)
            : photoLibraryViewModel.todayAssets().count

        if todayCount == 0 {
            return "No photos for today yet. When you take some, choose one to keep the day."
        }

        if photoLibraryViewModel.hasRepresentativePhoto(on: .now) {
            return "Today's Photo is already set. Your calendar is taking shape, one day at a time."
        }

        return "You have \(todayCount) photo\(todayCount == 1 ? "" : "s") today. Choose one worth keeping."
    }

    private var todayButtonSubtitle: String {
        let todayCount = photoLibraryViewModel.isPreviewMode
            ? photoLibraryViewModel.mockPhotoCount(on: .now)
            : photoLibraryViewModel.todayAssets().count
        if todayCount == 0 {
            return "Ready when new photos appear"
        }

        return "Choose from \(todayCount) photo\(todayCount == 1 ? "" : "s")"
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    @ViewBuilder
    private func screenshotHeadline(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(text)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
        }
        .padding(.top, 6)
        .padding(.leading, 22)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private func scrollForScreenshotIfNeeded(using proxy: ScrollViewProxy) async {
        guard let target = screenshotVariant?.scrollTarget, displayMode == .calendar else { return }
        try? await Task.sleep(nanoseconds: 150_000_000)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            proxy.scrollTo(target, anchor: .top)
        }
    }
}

private struct MemoriesTimelineView: View {
    @ObservedObject var photoLibraryViewModel: PhotoLibraryViewModel
    @State private var shouldRenderEntries = false

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM d, yyyy")
        return formatter
    }()

    var body: some View {
        let entries = shouldRenderEntries ? photoLibraryViewModel.memoryTimelinePreviewItems : []

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Memories")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("A quiet timeline of the days you chose to keep.")
                        .font(.subheadline)
                        .foregroundStyle(Color.white.opacity(0.62))
                }
                .padding(.top, 8)

                if entries.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("No memories yet")
                            .font(.headline)
                            .foregroundStyle(.white)

                        Text("Choose a daily photo in the calendar to begin your timeline.")
                            .font(.subheadline)
                            .foregroundStyle(Color.white.opacity(0.62))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)
                    .background(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    )
                } else {
                    LazyVStack(alignment: .leading, spacing: 28) {
                        ForEach(entries) { entry in
                            NavigationLink {
                                DayPhotosView(date: entry.date, photoLibraryViewModel: photoLibraryViewModel)
                            } label: {
                                VStack(alignment: .leading, spacing: 12) {
                                    MemoryTimelinePhoto(source: entry.source)

                                    Text(dateFormatter.string(from: entry.date))
                                        .font(.footnote.weight(.medium))
                                        .foregroundStyle(Color.white.opacity(0.72))
                                        .padding(.horizontal, 4)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 36)
        }
        .background(
            LinearGradient(
                colors: [
                    Color.black,
                    Color(red: 0.03, green: 0.04, blue: 0.08)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .task(id: photoLibraryViewModel.lastUpdated) {
            guard shouldRenderEntries else { return }
            photoLibraryViewModel.prepareMemoryTimelineCache(
                targetSize: CGSize(width: 900, height: 900)
            )
        }
        .task {
            if photoLibraryViewModel.isPreviewMode {
                shouldRenderEntries = true
                return
            }
            guard shouldRenderEntries == false else { return }
            try? await Task.sleep(nanoseconds: 250_000_000)
            shouldRenderEntries = true
        }
    }
}

private struct MemoryTimelinePhoto: View {
    let source: CalendarThumbnailSource

    var body: some View {
        CalendarThumbnailContentView(
            source: source,
            targetSize: CGSize(width: 900, height: 900),
            cornerRadius: 30,
            showsProgress: true
        )
        .aspectRatio(4 / 5, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.32), radius: 24, y: 16)
    }
}

private struct CalendarPreviewCard: View {
    let item: CalendarPreviewItem
    @State private var isPressed = false

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("Hm")
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CalendarThumbnailContentView(
                source: item.thumbnailSource,
                targetSize: CGSize(width: 320, height: 260),
                cornerRadius: 24,
                showsProgress: false
            )
            .frame(width: 136, height: 128)
            .overlay(alignment: .topLeading) {
                Text(badgeText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.96))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.22), in: Capsule())
                    .padding(10)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(Self.dayFormatter.string(from: item.date))
                    .font(.subheadline.weight(.semibold))

                Text(timeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 136, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(.systemBackground).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
        .scaleEffect(isPressed ? 0.98 : 1)
        .shadow(color: Color.black.opacity(0.16), radius: isPressed ? 8 : 14, y: isPressed ? 4 : 10)
        .animation(.spring(response: 0.24, dampingFraction: 0.82), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if isPressed == false {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    isPressed = false
                }
        )
    }

    private var timeText: String {
        switch item.thumbnailSource {
        case .asset:
            return Self.timeFormatter.string(from: item.date)
        case .mock:
            return "Mock"
        }
    }

    private var badgeText: String {
        Calendar.current.isDateInToday(item.date) ? "Today" : "Memory"
    }
}
