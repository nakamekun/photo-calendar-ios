import SwiftUI

struct CalendarHeaderView: View {
    @ObservedObject var viewModel: CalendarViewModel
    @State private var isShowingMonthPicker = false

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Calendar")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                Button {
                    isShowingMonthPicker = true
                } label: {
                    HStack(spacing: 6) {
                        Text(viewModel.monthTitle)
                            .font(.title2.weight(.semibold))
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }

            Spacer()

            HStack(spacing: 10) {
                Button {
                    viewModel.showPreviousMonth()
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .background(.thinMaterial, in: Circle())

                Button {
                    viewModel.showNextMonth()
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .background(.thinMaterial, in: Circle())
                .disabled(viewModel.canShowNextMonth == false)
                .opacity(viewModel.canShowNextMonth ? 1 : 0.35)
            }
        }
        .sheet(isPresented: $isShowingMonthPicker) {
            CalendarMonthPickerSheet(
                viewModel: viewModel,
                isPresented: $isShowingMonthPicker
            )
            .presentationDetents([.height(280)])
            .presentationDragIndicator(.visible)
        }
    }
}

private struct CalendarMonthPickerSheet: View {
    @ObservedObject var viewModel: CalendarViewModel
    @Binding var isPresented: Bool
    @State private var selectedYear: Int
    @State private var selectedMonth: Int

    init(viewModel: CalendarViewModel, isPresented: Binding<Bool>) {
        self.viewModel = viewModel
        self._isPresented = isPresented
        _selectedYear = State(initialValue: viewModel.displayedYear)
        _selectedMonth = State(initialValue: viewModel.displayedMonthNumber)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                HStack(spacing: 12) {
                    Picker("Year", selection: $selectedYear) {
                        ForEach(viewModel.selectableYears, id: \.self) { year in
                            Text(String(year)).tag(year)
                        }
                    }
                    .pickerStyle(.wheel)

                    Picker("Month", selection: $selectedMonth) {
                        ForEach(availableMonths, id: \.self) { month in
                            Text(monthTitle(for: month)).tag(month)
                        }
                    }
                    .pickerStyle(.wheel)
                }
                .frame(height: 160)

                Button {
                    viewModel.setDisplayedMonth(year: selectedYear, month: selectedMonth)
                    isPresented = false
                } label: {
                    Text("Go to Month")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.canSelect(year: selectedYear, month: selectedMonth) == false)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .navigationTitle("Jump to Month")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
        }
        .onChange(of: selectedYear) { _, newYear in
            if availableMonths.contains(selectedMonth) == false {
                selectedMonth = min(selectedMonth, viewModel.currentMonthNumber)
            }
        }
    }

    private var availableMonths: [Int] {
        if selectedYear == viewModel.currentYear {
            return Array(1...viewModel.currentMonthNumber)
        }
        return Array(1...12)
    }

    private func monthTitle(for month: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.monthSymbols[month - 1]
    }
}
