import SwiftUI

struct PermissionView: View {
    let authorizationState: PhotoAuthorizationState
    let requestAccess: () -> Void
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

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
                    .padding(.horizontal, 24)
            }

            Button(action: primaryAction) {
                Text(primaryButtonTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .padding(.horizontal, 24)

            if authorizationState == .denied || authorizationState == .restricted {
                Text("Turn on photo access in Settings to fill your calendar with daily photos.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    private var title: String {
        switch authorizationState {
        case .denied, .restricted:
            return "Photo Access Needed"
        case .notDetermined, .authorized, .limited:
            return "One Photo a Day"
        }
    }

    private var message: String {
        switch authorizationState {
        case .denied, .restricted:
            return "Please allow photo access to show your memories on the calendar."
        case .notDetermined, .authorized, .limited:
            return "This app groups your photos by day and lets you save one photo for each date."
        }
    }

    private var primaryButtonTitle: String {
        switch authorizationState {
        case .denied, .restricted:
            return "Open Settings"
        case .notDetermined, .authorized, .limited:
            return "Allow Photo Access"
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
