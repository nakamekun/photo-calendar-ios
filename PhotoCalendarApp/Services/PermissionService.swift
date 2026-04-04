import Foundation
import Photos

enum PhotoAuthorizationState: Equatable {
    case notDetermined
    case authorized
    case limited
    case denied
    case restricted

    var canReadLibrary: Bool {
        self == .authorized || self == .limited
    }
}

protocol PermissionServicing {
    func currentStatus() -> PhotoAuthorizationState
    func requestAuthorization() async -> PhotoAuthorizationState
}

struct PermissionService: PermissionServicing {
    func currentStatus() -> PhotoAuthorizationState {
        mapStatus(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    func requestAuthorization() async -> PhotoAuthorizationState {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return mapStatus(status)
    }

    private func mapStatus(_ status: PHAuthorizationStatus) -> PhotoAuthorizationState {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .authorized:
            return .authorized
        case .limited:
            return .limited
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .denied
        }
    }
}
