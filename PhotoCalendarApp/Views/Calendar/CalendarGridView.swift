import SwiftUI

struct CalendarGridView: View {
    let days: [CalendarDay]
    let photoLibraryViewModel: PhotoLibraryViewModel

    @State private var selectedDay: CalendarDay?
    @State private var pressedDayID: String?

    private let columns = Array(
        repeating: GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 10, alignment: .top),
        count: 7
    )
    private var weekdaySymbols: [String] {
        let calendar = Calendar.current
        let symbols = calendar.shortWeekdaySymbols
        let firstWeekdayIndex = max(calendar.firstWeekday - 1, 0)

        return (0..<symbols.count).map { offset in
            let index = (firstWeekdayIndex + offset) % symbols.count
            let symbol = symbols[index]
            return String(symbol.prefix(1))
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(days) { day in
                    Button {
                        openDay(day)
                    } label: {
                        CalendarDayCellView(day: day, isPressed: pressedDayID == day.id)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationDestination(item: $selectedDay) { day in
            DayPhotosView(date: day.date, photoLibraryViewModel: photoLibraryViewModel)
        }
        .sensoryFeedback(.selection, trigger: pressedDayID)
    }

    private func openDay(_ day: CalendarDay) {
        withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
            pressedDayID = day.id
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            withAnimation(.easeOut(duration: 0.16)) {
                selectedDay = day
                pressedDayID = nil
            }
        }
    }
}
