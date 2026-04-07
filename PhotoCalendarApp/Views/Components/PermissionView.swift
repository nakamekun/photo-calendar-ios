import SwiftUI

struct PermissionView: View {
    let authorizationState: PhotoAuthorizationState
    let requestAccess: () -> Void
    let openSettings: () -> Void

    var body: some View {
        VStack {
            Spacer()

            VStack(spacing: 24) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.blue)

                VStack(spacing: 12) {
                    Text(title)
                        .font(.title2.weight(.semibold))

                    Text(message)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button(action: primaryAction) {
                    Text(primaryButtonTitle)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)

                if let secondaryMessage {
                    Text(secondaryMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: 520)
            .padding(.horizontal, 24)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    private var title: String {
        switch authorizationState {
        case .denied, .restricted:
            return "Photo Access Is Off"
        case .notDetermined, .authorized, .limited:
            return "One Photo a Day"
        }
    }

    private var message: String {
        switch authorizationState {
        case .denied, .restricted:
            return "You can keep using the app without photos, or turn on photo access in Settings to display memories on your calendar."
        case .notDetermined, .authorized, .limited:
            return "We use your photos to display memories on your calendar. Photos are processed on-device and are not uploaded."
        }
    }

    private var primaryButtonTitle: String {
        switch authorizationState {
        case .denied, .restricted:
            return "Open Settings"
        case .notDetermined, .authorized, .limited:
            return "Continue"
        }
    }

    private var secondaryMessage: String? {
        switch authorizationState {
        case .denied, .restricted:
            return "If you want to add photos later, you can update this anytime in Settings."
        case .notDetermined, .authorized, .limited:
            return nil
        }
    }

    private func primaryAction() {
        switch authorizationState {
        case .denied, .restricted:
            openSettings()
        case .notDetermined, .authorized, .limited:
            requestAccess()
        }
    }
}
