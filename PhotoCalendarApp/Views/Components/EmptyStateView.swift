import SwiftUI

struct EmptyStateView: View {
    let title: String
    let message: String
    let systemImageName: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImageName)
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }
}
