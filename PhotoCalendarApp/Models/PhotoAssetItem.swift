import Foundation
import Photos

struct PhotoAssetItem: Identifiable, Hashable {
    let asset: PHAsset

    var id: String { asset.localIdentifier }
    var creationDate: Date { asset.creationDate ?? .distantPast }
}
