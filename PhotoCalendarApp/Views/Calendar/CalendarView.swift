import SwiftUI
import UIKit

struct CalendarView: View {
    private enum ScreenshotVariant: String {
        case hero
        case habit
        case pick
        case memories

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
            }
        }

        var displayMode: DisplayMode {
            switch self {
            case .memories:
                return .memories
            case .hero, .habit, .pick:
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
                return .calendar
            case .memories:
                return nil
            }
        }
    }

    private enum SectionID: Hashable {
        case intro
        case calendar
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
                    return
                }
                guard shouldShowSecondarySections == false else { return }
                try? await Task.sleep(nanoseconds: 350_000_000)
                shouldShowSecondarySections = true
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

            ZStack {
                switch displayMode {
                case .calendar:
                    calendarPage
                        .transition(.opacity)
                case .memories:
                    MemoriesTimelineView(
                        photoLibraryViewModel: photoLibraryViewModel,
                        showCalendar: { displayMode = .calendar }
                    )
                        .transition(.opacity)
                }
            }
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

                    if shouldShowSecondarySections {
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

    private var calendarSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            CalendarHeaderView(viewModel: viewModel)

            Text("Days with photos stay blue. Open a date to revisit its memory.")
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
                targetSize: CGSize(width: 96, height: 96)
            )
        }
    }

    private var heroMessage: String {
        let todayCount = photoLibraryViewModel.isPreviewMode
            ? photoLibraryViewModel.mockPhotoCount(on: .now)
            : photoLibraryViewModel.todayAssets().count

        if todayCount == 0 {
            return "Photos are organized by day, with a representative memory chosen automatically."
        }

        if photoLibraryViewModel.hasRepresentativePhoto(on: .now) {
            return "The calendar stays at the center while each day quietly keeps one representative photo."
        }

        return "You have \(todayCount) photo\(todayCount == 1 ? "" : "s") today. Each day keeps a representative photo automatically."
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
    let showCalendar: () -> Void
    @State private var shouldRenderEntries = false
    @State private var selectedDate = Date().startOfDay()
    @State private var memoryTimelineCacheTask: Task<Void, Never>?
    @State private var isScrubbingTimeline = false

    private let calendar = Calendar.current

    var body: some View {
        let entries = shouldRenderEntries ? photoLibraryViewModel.memoryTimelinePreviewItems : []

        VStack(spacing: 0) {
            fixedDateHeader(entries: entries)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)

            ScrollViewReader { proxy in
                GeometryReader { geometry in
                    ZStack(alignment: .trailing) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 24) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Memories")
                                        .font(.system(size: 32, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white)

                                    Text("A simple timeline of representative photos by day.")
                                        .font(.subheadline)
                                        .foregroundStyle(Color.white.opacity(0.62))
                                }
                                .padding(.top, 8)

                                if entries.isEmpty {
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text("No memories yet")
                                            .font(.headline)
                                            .foregroundStyle(.white)

                                        Text("Representative photos will appear here after the library is read.")
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
                                                DayPhotosView(
                                                    date: entry.date,
                                                    photoLibraryViewModel: photoLibraryViewModel,
                                                    onReturnToCalendar: showCalendar
                                                )
                                            } label: {
                                                VStack(alignment: .leading, spacing: 12) {
                                                    MemoryTimelinePhoto(
                                                        source: entry.source,
                                                        isSwipeToClearEnabled: photoLibraryViewModel.isMockDataEnabled == false,
                                                        onSwipeToClear: {
                                                            photoLibraryViewModel.disableAutoPick(
                                                                for: entry.date,
                                                                excludingCurrentRepresentative: true
                                                            )
                                                        }
                                                    )

                                                    Text(memoryDateText(for: entry.date))
                                                        .font(.footnote.weight(.medium))
                                                        .foregroundStyle(Color.white.opacity(0.72))
                                                        .padding(.horizontal, 4)
                                                }
                                            }
                                            .buttonStyle(.plain)
                                            .id(entry.id)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 36)
                        }
                        .scrollIndicators(.hidden)

                        if entries.isEmpty == false {
                            timelineScrubber(entries: entries, proxy: proxy, height: geometry.size.height)
                                .padding(.trailing, 8)
                        }
                    }
                }
                .onChange(of: selectedDate) { _, newValue in
                    guard isScrubbingTimeline == false else { return }
                    guard let target = closestEntry(to: newValue, in: entries) else { return }
                    if target.date.startOfDay() != newValue.startOfDay() {
                        selectedDate = target.date.startOfDay()
                        return
                    }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(target.id, anchor: .top)
                    }
                }
            }
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
            memoryTimelineCacheTask?.cancel()
            memoryTimelineCacheTask = Task {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard Task.isCancelled == false else { return }
                photoLibraryViewModel.prepareMemoryTimelineCache(
                    targetSize: CGSize(width: 480, height: 600)
                )
                memoryTimelineCacheTask = nil
            }
        }
        .task {
            if photoLibraryViewModel.isPreviewMode {
                shouldRenderEntries = true
                return
            }
            guard shouldRenderEntries == false else { return }
            try? await Task.sleep(nanoseconds: 250_000_000)
            shouldRenderEntries = true
            photoLibraryViewModel.prepareMemoryTimelineData(initialDate: selectedDate)
        }
        .onChange(of: selectedDate) { _, newValue in
            guard shouldRenderEntries, photoLibraryViewModel.isPreviewMode == false else { return }
            photoLibraryViewModel.prepareHistoryMonth(for: newValue)
        }
        .onChange(of: shouldRenderEntries) { _, ready in
            guard ready, let firstEntry = entries.first else { return }
            selectedDate = firstEntry.date.startOfDay()
        }
        .onDisappear {
            memoryTimelineCacheTask?.cancel()
            memoryTimelineCacheTask = nil
        }
    }

    private func fixedDateHeader(entries: [MemoryTimelineEntry]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                componentMenu(
                    title: "Year",
                    value: plainYearText(for: selectedDate)
                ) {
                    ForEach(availableYears(from: entries), id: \.self) { year in
                        Button(String(year)) {
                            setSelectedDateComponent(year: year)
                        }
                    }
                }

                componentMenu(
                    title: "Month",
                    value: plainMonthText(for: selectedDate)
                ) {
                    ForEach(1...12, id: \.self) { month in
                        Button(String(month)) {
                            setSelectedDateComponent(month: month)
                        }
                    }
                }

                componentMenu(
                    title: "Day",
                    value: "\(calendar.component(.day, from: selectedDate))"
                ) {
                    let year = calendar.component(.year, from: selectedDate)
                    let month = calendar.component(.month, from: selectedDate)
                    let daysInMonth = calendar.range(
                        of: .day,
                        in: .month,
                        for: calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? selectedDate
                    )?.count ?? 31

                    ForEach(1...daysInMonth, id: \.self) { day in
                        Button("\(day)") {
                            setSelectedDateComponent(day: day)
                        }
                    }
                }
            }

            Text(memoryDateText(for: selectedDate))
                .font(.caption.weight(.medium))
                .foregroundStyle(
                    entries.contains(where: { $0.id == DayKeyFormatter.dayString(from: selectedDate.startOfDay()) })
                    ? Color.white.opacity(0.78)
                    : Color.white.opacity(0.5)
                )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func setSelectedDateComponent(year: Int? = nil, month: Int? = nil, day: Int? = nil) {
        var components = calendar.dateComponents([.year, .month, .day], from: selectedDate)

        if let year {
            components.year = year
        }
        if let month {
            components.month = month
        }

        let resolvedYear = components.year ?? calendar.component(.year, from: selectedDate)
        let resolvedMonth = components.month ?? calendar.component(.month, from: selectedDate)
        let monthDate = calendar.date(from: DateComponents(year: resolvedYear, month: resolvedMonth, day: 1)) ?? selectedDate
        let maxDay = calendar.range(of: .day, in: .month, for: monthDate)?.count ?? 31

        if let day {
            components.day = min(day, maxDay)
        } else {
            components.day = min(components.day ?? 1, maxDay)
        }

        if let updatedDate = calendar.date(from: components) {
            selectedDate = updatedDate.startOfDay()
        }
    }

    private func plainYearText(for date: Date) -> String {
        String(calendar.component(.year, from: date))
    }

    private func plainMonthText(for date: Date) -> String {
        String(calendar.component(.month, from: date))
    }

    private func memoryDateText(for date: Date) -> String {
        "\(plainMonthText(for: date))/\(calendar.component(.day, from: date)), \(plainYearText(for: date))"
    }

    private func availableYears(from entries: [MemoryTimelineEntry]) -> [Int] {
        let currentYear = calendar.component(.year, from: .now)
        let oldestYear = entries
            .map { calendar.component(.year, from: $0.date) }
            .min() ?? (currentYear - 10)
        let lowerBound = min(oldestYear, currentYear)
        return Array(stride(from: currentYear, through: lowerBound, by: -1))
    }

    private func closestEntry(to date: Date, in entries: [MemoryTimelineEntry]) -> MemoryTimelineEntry? {
        let target = date.startOfDay()
        return entries.min { lhs, rhs in
            abs(lhs.date.startOfDay().timeIntervalSince(target)) < abs(rhs.date.startOfDay().timeIntervalSince(target))
        }
    }

    private func timelineScrubber(entries: [MemoryTimelineEntry], proxy: ScrollViewProxy, height: CGFloat) -> some View {
        let thumbOffset = scrubberThumbOffset(entries: entries, height: height)

        return ZStack(alignment: .top) {
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.1))
                .frame(width: 6)

            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.white.opacity(0.52))
                .frame(width: 10, height: 68)
                .offset(y: thumbOffset)
                .shadow(color: Color.black.opacity(0.18), radius: 6, y: 3)
        }
        .frame(width: 32, height: height)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    isScrubbingTimeline = true
                    scrubTimeline(
                        at: value.location.y,
                        height: height,
                        entries: entries,
                        proxy: proxy
                    )
                }
                .onEnded { _ in
                    isScrubbingTimeline = false
                }
        )
    }

    private func scrubTimeline(at locationY: CGFloat, height: CGFloat, entries: [MemoryTimelineEntry], proxy: ScrollViewProxy) {
        guard let target = entryForScrubPosition(locationY, height: height, entries: entries) else { return }
        let day = target.date.startOfDay()
        if selectedDate != day {
            selectedDate = day
        }
        proxy.scrollTo(target.id, anchor: .top)
    }

    private func entryForScrubPosition(_ locationY: CGFloat, height: CGFloat, entries: [MemoryTimelineEntry]) -> MemoryTimelineEntry? {
        guard entries.isEmpty == false, height > 0 else { return nil }
        let clampedProgress = min(max(locationY / height, 0), 1)
        let index = min(Int(round(clampedProgress * CGFloat(entries.count - 1))), entries.count - 1)
        return entries[index]
    }

    private func scrubberThumbOffset(entries: [MemoryTimelineEntry], height: CGFloat) -> CGFloat {
        guard
            let current = closestEntry(to: selectedDate, in: entries),
            let index = entries.firstIndex(where: { $0.id == current.id }),
            entries.count > 1
        else {
            return 0
        }

        let availableHeight = max(height - 68, 0)
        let progress = CGFloat(index) / CGFloat(entries.count - 1)
        return availableHeight * progress
    }

    private func componentMenu<Content: View>(title: String, value: String, @ViewBuilder content: () -> Content) -> some View {
        Menu {
            content()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.6))
                HStack(spacing: 6) {
                    Text(value)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.72))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}

private struct MemoryTimelinePhoto: View {
    let source: CalendarThumbnailSource
    let isSwipeToClearEnabled: Bool
    let onSwipeToClear: () -> Void

    @State private var swipeOffset: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            photoContent(in: proxy.size)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(4 / 5, contentMode: .fit)
        .clipped()
    }

    @ViewBuilder
    private func photoContent(in size: CGSize) -> some View {
        let content = CalendarThumbnailContentView(
            source: source,
            targetSize: CGSize(width: 480, height: 600),
            cornerRadius: 30,
            showsProgress: true
        )
        .frame(width: size.width, height: size.height)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .offset(x: swipeOffset)
        .rotationEffect(.degrees(Double(swipeOffset / 35)))
        .contentShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .animation(.spring(response: 0.24, dampingFraction: 0.82), value: swipeOffset)
        .shadow(color: Color.black.opacity(0.22), radius: 12, y: 8)

        if isSwipeToClearEnabled {
            content.highPriorityGesture(representativeClearGesture, including: .gesture)
        } else {
            content
        }
    }

    private var representativeClearGesture: some Gesture {
        DragGesture(minimumDistance: 16)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                swipeOffset = value.translation.width
            }
            .onEnded { value in
                let isHorizontal = abs(value.translation.width) > abs(value.translation.height)
                defer { swipeOffset = 0 }
                guard isHorizontal, abs(value.translation.width) > 80 else { return }
                onSwipeToClear()
            }
    }
}
