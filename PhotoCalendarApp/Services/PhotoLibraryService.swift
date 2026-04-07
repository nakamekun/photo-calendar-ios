import CoreGraphics
import Foundation
import Photos
import UIKit

struct PhotoDaySummary: Hashable {
    let date: Date
    let photoCount: Int
    let candidateAssetIdentifiers: [String]
    let latestAssetIdentifier: String?
    let representativeAssetIdentifier: String?
}

protocol PhotoLibraryServicing {
    func fetchLatestImageAsset() -> PHAsset?
    func fetchOldestImageAsset() -> PHAsset?
    func fetchImageAssets(on date: Date, limit: Int) -> [PHAsset]
    func fetchAllImageAssets(on date: Date) -> [PHAsset]
    func fetchPhotoDaySummaries(limitPerDay: Int) -> [PhotoDaySummary]
    func fetchPhotoDaySummaries(in interval: DateInterval, limitPerDay: Int) -> [PhotoDaySummary]
    func fetchAsset(localIdentifier: String) -> PHAsset?
    func fetchAssets(localIdentifiers: [String]) -> [PHAsset]
    func requestImage(
        for asset: PHAsset,
        targetSize: CGSize,
        contentMode: PHImageContentMode,
        deliveryMode: PHImageRequestOptionsDeliveryMode,
        completion: @escaping (UIImage?) -> Void
    )
    func startCachingImages(
        for assets: [PHAsset],
        targetSize: CGSize,
        contentMode: PHImageContentMode
    )
    func stopCachingImages(
        for assets: [PHAsset],
        targetSize: CGSize,
        contentMode: PHImageContentMode
    )
}

final class PhotoLibraryService: PhotoLibraryServicing {
    private struct DayAssetCacheEntry {
        let identifiers: [String]
        let latestIdentifier: String?
        let photoCount: Int
    }

    private static let sharedImageManager = PHCachingImageManager()
    private static let cacheLock = NSLock()
    private static let imageCache = NSCache<NSString, UIImage>()
    private static var inFlightImageCallbacks: [String: [(UIImage?) -> Void]] = [:]
    private static var dayAssetIdentifiersByKey: [String: DayAssetCacheEntry] = [:]
    private static var daySummariesByKey: [String: PhotoDaySummary] = [:]
    private let screenshotSubtypeMask = Int(PHAssetMediaSubtype.photoScreenshot.rawValue)
    private let imageManager = PhotoLibraryService.sharedImageManager
    private let calendar = Calendar.current

    init() {
        PhotoLibraryService.imageCache.countLimit = 600
        PhotoLibraryService.imageCache.totalCostLimit = 256 * 1024 * 1024
    }

    func fetchLatestImageAsset() -> PHAsset? {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = nonScreenshotImagePredicate()
        options.fetchLimit = 1

        let fetchResult = PHAsset.fetchAssets(with: options)
        return fetchResult.firstObject
    }

    func fetchOldestImageAsset() -> PHAsset? {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        options.predicate = nonScreenshotImagePredicate()
        options.fetchLimit = 1

        let fetchResult = PHAsset.fetchAssets(with: options)
        return fetchResult.firstObject
    }

    func fetchImageAssets(on date: Date, limit: Int) -> [PHAsset] {
        fetchImageAssets(on: date, limit: limit > 0 ? limit : nil)
    }

    func fetchAllImageAssets(on date: Date) -> [PHAsset] {
        fetchImageAssets(on: date, limit: nil)
    }

    private func fetchImageAssets(on date: Date, limit: Int?) -> [PHAsset] {
        let identifiers = fetchImageIdentifiers(on: date)
        if let limit {
            return fetchAssets(localIdentifiers: Array(identifiers.prefix(limit)))
        }
        return fetchAssets(localIdentifiers: identifiers)
    }

    func fetchPhotoDaySummaries(limitPerDay: Int = 10) -> [PhotoDaySummary] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = nonScreenshotImagePredicate()

        let fetchResult = PHAsset.fetchAssets(with: options)
        var grouped: [String: (date: Date, count: Int, ids: [String], latest: String?, representative: String?)] = [:]

        fetchResult.enumerateObjects { asset, _, _ in
            guard let creationDate = asset.creationDate else { return }

            let day = self.calendar.startOfDay(for: creationDate)
            let key = DayKeyFormatter.dayString(from: day)
            var entry = grouped[key] ?? (date: day, count: 0, ids: [], latest: nil, representative: nil)
            entry.count += 1

            if entry.latest == nil {
                entry.latest = asset.localIdentifier
            }

            if entry.representative == nil {
                entry.representative = asset.localIdentifier
            }

            if entry.ids.count < limitPerDay {
                entry.ids.append(asset.localIdentifier)
            }

            grouped[key] = entry
        }

        return grouped.values
            .map {
                let summary = PhotoDaySummary(
                    date: $0.date,
                    photoCount: $0.count,
                    candidateAssetIdentifiers: $0.ids,
                    latestAssetIdentifier: $0.latest,
                    representativeAssetIdentifier: $0.representative
                )
                storeCachedSummary(summary, identifiers: $0.ids, allIdentifiers: nil)
                return summary
            }
            .sorted { $0.date > $1.date }
    }

    func fetchPhotoDaySummaries(in interval: DateInterval, limitPerDay: Int = 10) -> [PhotoDaySummary] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = nonScreenshotImagePredicate(
            additionalFormat: "creationDate >= %@ AND creationDate < %@",
            interval.start as NSDate,
            interval.end as NSDate
        )

        let fetchResult = PHAsset.fetchAssets(with: options)
        var grouped: [String: (date: Date, count: Int, previewIDs: [String], allIDs: [String], latest: String?, representative: String?)] = [:]

        fetchResult.enumerateObjects { asset, _, _ in
            guard let creationDate = asset.creationDate else { return }

            let day = self.calendar.startOfDay(for: creationDate)
            let key = DayKeyFormatter.dayString(from: day)
            var entry = grouped[key] ?? (date: day, count: 0, previewIDs: [], allIDs: [], latest: nil, representative: nil)
            entry.count += 1

            if entry.latest == nil {
                entry.latest = asset.localIdentifier
            }

            if entry.representative == nil {
                entry.representative = asset.localIdentifier
            }

            entry.allIDs.append(asset.localIdentifier)
            if entry.previewIDs.count < limitPerDay {
                entry.previewIDs.append(asset.localIdentifier)
            }
            grouped[key] = entry
        }

        return grouped.values.map { value in
            let summary = PhotoDaySummary(
                date: value.date,
                photoCount: value.count,
                candidateAssetIdentifiers: value.previewIDs,
                latestAssetIdentifier: value.latest,
                representativeAssetIdentifier: value.representative
            )
            storeCachedSummary(summary, identifiers: value.previewIDs, allIdentifiers: value.allIDs)
            return summary
        }
        .sorted { $0.date > $1.date }
    }

    func fetchAsset(localIdentifier: String) -> PHAsset? {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        return result.firstObject
    }

    func fetchAssets(localIdentifiers: [String]) -> [PHAsset] {
        guard localIdentifiers.isEmpty == false else { return [] }

        let result = PHAsset.fetchAssets(withLocalIdentifiers: localIdentifiers, options: nil)
        var lookup: [String: PHAsset] = [:]
        lookup.reserveCapacity(result.count)

        result.enumerateObjects { asset, _, _ in
            lookup[asset.localIdentifier] = asset
        }

        return localIdentifiers.compactMap { lookup[$0] }
    }

    func requestImage(
        for asset: PHAsset,
        targetSize: CGSize,
        contentMode: PHImageContentMode = .aspectFill,
        deliveryMode: PHImageRequestOptionsDeliveryMode = .opportunistic,
        completion: @escaping (UIImage?) -> Void
    ) {
        let resolvedSize = normalizedTargetSize(targetSize)
        let cacheKey = imageCacheKey(
            assetID: asset.localIdentifier,
            targetSize: resolvedSize,
            contentMode: contentMode,
            deliveryMode: deliveryMode
        )

        if let cached = PhotoLibraryService.imageCache.object(forKey: cacheKey as NSString) {
            completion(cached)
            return
        }

        let shouldStartRequest: Bool
        PhotoLibraryService.cacheLock.lock()
        if PhotoLibraryService.inFlightImageCallbacks[cacheKey] != nil {
            PhotoLibraryService.inFlightImageCallbacks[cacheKey, default: []].append(completion)
            shouldStartRequest = false
        } else {
            PhotoLibraryService.inFlightImageCallbacks[cacheKey] = [completion]
            shouldStartRequest = true
        }
        PhotoLibraryService.cacheLock.unlock()

        guard shouldStartRequest else { return }

        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = deliveryMode
        options.resizeMode = .fast
        options.isSynchronous = false

        imageManager.requestImage(
            for: asset,
            targetSize: resolvedSize,
            contentMode: contentMode,
            options: options
        ) { image, info in
            let isDegraded = (info?[PHImageResultIsDegradedKey] as? NSNumber)?.boolValue ?? false
            if let image, isDegraded == false {
                let cost = Int(resolvedSize.width * resolvedSize.height * 4)
                PhotoLibraryService.imageCache.setObject(image, forKey: cacheKey as NSString, cost: cost)
            }

            let callbacks = self.takeInFlightCallbacks(for: cacheKey, keepRegistered: isDegraded)
            callbacks.forEach { $0(image) }
        }
    }

    func startCachingImages(
        for assets: [PHAsset],
        targetSize: CGSize,
        contentMode: PHImageContentMode = .aspectFill
    ) {
        guard assets.isEmpty == false else { return }

        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        imageManager.startCachingImages(
            for: assets,
            targetSize: targetSize,
            contentMode: contentMode,
            options: options
        )
    }

    func stopCachingImages(
        for assets: [PHAsset],
        targetSize: CGSize,
        contentMode: PHImageContentMode = .aspectFill
    ) {
        guard assets.isEmpty == false else { return }

        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        imageManager.stopCachingImages(
            for: assets,
            targetSize: targetSize,
            contentMode: contentMode,
            options: options
        )
    }

    private func fetchImageIdentifiers(on date: Date) -> [String] {
        let day = calendar.startOfDay(for: date)
        let key = DayKeyFormatter.dayString(from: day)

        PhotoLibraryService.cacheLock.lock()
        if let cached = PhotoLibraryService.dayAssetIdentifiersByKey[key]?.identifiers {
            PhotoLibraryService.cacheLock.unlock()
            return cached
        }
        PhotoLibraryService.cacheLock.unlock()

        let endOfDay = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = nonScreenshotImagePredicate(
            additionalFormat: "creationDate >= %@ AND creationDate < %@",
            day as NSDate,
            endOfDay as NSDate
        )

        let fetchResult = PHAsset.fetchAssets(with: options)
        var identifiers: [String] = []
        identifiers.reserveCapacity(fetchResult.count)

        fetchResult.enumerateObjects { asset, _, _ in
            guard asset.creationDate != nil else { return }
            identifiers.append(asset.localIdentifier)
        }

        let latestIdentifier = identifiers.first
        let summary = PhotoDaySummary(
            date: day,
            photoCount: identifiers.count,
            candidateAssetIdentifiers: Array(identifiers.prefix(10)),
            latestAssetIdentifier: latestIdentifier,
            representativeAssetIdentifier: latestIdentifier
        )
        storeCachedSummary(summary, identifiers: Array(identifiers.prefix(10)), allIdentifiers: identifiers)
        return identifiers
    }

    private func nonScreenshotImagePredicate(
        additionalFormat: String? = nil,
        _ arguments: CVarArg...
    ) -> NSPredicate {
        let baseFormat = "mediaType == %d AND ((mediaSubtypes & %d) == 0)"
        let baseArguments: [CVarArg] = [PHAssetMediaType.image.rawValue, screenshotSubtypeMask]

        guard let additionalFormat else {
            return NSPredicate(format: baseFormat, argumentArray: baseArguments)
        }

        return NSPredicate(
            format: "\(baseFormat) AND \(additionalFormat)",
            argumentArray: baseArguments + arguments
        )
    }

    private func storeCachedSummary(_ summary: PhotoDaySummary, identifiers: [String], allIdentifiers: [String]?) {
        let key = DayKeyFormatter.dayString(from: summary.date)

        PhotoLibraryService.cacheLock.lock()
        let fullIdentifiers = allIdentifiers ?? PhotoLibraryService.dayAssetIdentifiersByKey[key]?.identifiers ?? identifiers
        PhotoLibraryService.daySummariesByKey[key] = summary
        PhotoLibraryService.dayAssetIdentifiersByKey[key] = DayAssetCacheEntry(
            identifiers: fullIdentifiers,
            latestIdentifier: summary.latestAssetIdentifier,
            photoCount: summary.photoCount
        )
        PhotoLibraryService.cacheLock.unlock()
    }

    private func takeInFlightCallbacks(for key: String, keepRegistered: Bool) -> [(UIImage?) -> Void] {
        PhotoLibraryService.cacheLock.lock()
        defer { PhotoLibraryService.cacheLock.unlock() }

        let callbacks = PhotoLibraryService.inFlightImageCallbacks[key] ?? []
        if keepRegistered == false {
            PhotoLibraryService.inFlightImageCallbacks.removeValue(forKey: key)
        }
        return callbacks
    }

    private func normalizedTargetSize(_ size: CGSize) -> CGSize {
        CGSize(width: max(1, ceil(size.width)), height: max(1, ceil(size.height)))
    }

    private func imageCacheKey(
        assetID: String,
        targetSize: CGSize,
        contentMode: PHImageContentMode,
        deliveryMode: PHImageRequestOptionsDeliveryMode
    ) -> String {
        "\(assetID)-\(Int(targetSize.width))x\(Int(targetSize.height))-\(contentMode.rawValue)-\(deliveryMode.rawValue)"
    }
}
