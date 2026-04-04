import SwiftUI

struct CalendarHeaderView: View {
    @ObservedObject var viewModel: CalendarViewModel

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Calendar")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                Text(viewModel.monthTitle)
                    .font(.title2.weight(.semibold))
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
            }
        }
    }
}
