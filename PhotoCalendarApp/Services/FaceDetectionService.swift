import Foundation
import Photos
import UIKit
import Vision

protocol FaceDetectionServicing {
    func faceCount(for asset: PHAsset, targetPixelSize: CGFloat) async -> Int
    func rankingScore(for asset: PHAsset, targetPixelSize: CGFloat) async -> Double
}

final class FaceDetectionService: FaceDetectionServicing {
    private let photoLibraryService: PhotoLibraryServicing

    init(photoLibraryService: PhotoLibraryServicing = PhotoLibraryService()) {
        self.photoLibraryService = photoLibraryService
    }

    func faceCount(for asset: PHAsset, targetPixelSize: CGFloat = 240) async -> Int {
        guard let cgImage = await lowResolutionCGImage(for: asset, targetPixelSize: targetPixelSize) else {
            return 0
        }

        return await Task.detached(priority: .utility) {
            let request = VNDetectFaceRectanglesRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            do {
                try handler.perform([request])
                return request.results?.count ?? 0
            } catch {
                return 0
            }
        }.value
    }

    func rankingScore(for asset: PHAsset, targetPixelSize: CGFloat = 240) async -> Double {
        if asset.mediaSubtypes.contains(.photoScreenshot) {
            return -10_000
        }

        guard let cgImage = await lowResolutionCGImage(for: asset, targetPixelSize: targetPixelSize) else {
            return Double(asset.creationDate?.timeIntervalSince1970 ?? 0)
        }

        async let faces = faceCount(in: cgImage)
        async let stats = imageStats(for: cgImage)

        let faceCount = await faces
        let imageStats = await stats

        var score = Double(asset.creationDate?.timeIntervalSince1970 ?? 0) / 1_000_000_000
        score += Double(faceCount) * 100

        if imageStats.whiteRatio > 0.72 && imageStats.averageSaturation < 0.18 {
            score -= 150
        }

        if imageStats.averageBrightness > 0.82 && imageStats.averageSaturation < 0.16 {
            score -= 100
        }

        if imageStats.averageSaturation < 0.08 {
            score -= 50
        }

        if imageStats.whiteRatio > 0.88 {
            score -= 60
        }

        return score
    }

    private func lowResolutionCGImage(for asset: PHAsset, targetPixelSize: CGFloat) async -> CGImage? {
        await withCheckedContinuation { continuation in
            photoLibraryService.requestImage(
                for: asset,
                targetSize: CGSize(width: targetPixelSize, height: targetPixelSize),
                contentMode: .aspectFill,
                deliveryMode: .fastFormat
            ) { image in
                continuation.resume(returning: image?.cgImage)
            }
        }
    }

    private func faceCount(in cgImage: CGImage) async -> Int {
        await Task.detached(priority: .utility) {
            let request = VNDetectFaceRectanglesRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            do {
                try handler.perform([request])
                return request.results?.count ?? 0
            } catch {
                return 0
            }
        }.value
    }

    private func imageStats(for cgImage: CGImage) async -> ImageStats {
        await Task.detached(priority: .utility) {
            Self.computeImageStats(from: cgImage)
        }.value
    }

    private static func computeImageStats(from cgImage: CGImage) -> ImageStats {
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return .zero }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let bitsPerComponent = 8
        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return .zero
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var brightnessTotal: Double = 0
        var saturationTotal: Double = 0
        var whiteCount = 0
        let pixelCount = width * height

        for index in stride(from: 0, to: pixels.count, by: bytesPerPixel) {
            let red = Double(pixels[index]) / 255
            let green = Double(pixels[index + 1]) / 255
            let blue = Double(pixels[index + 2]) / 255

            let maxValue = max(red, green, blue)
            let minValue = min(red, green, blue)
            let brightness = maxValue
            let saturation = maxValue == 0 ? 0 : (maxValue - minValue) / maxValue

            brightnessTotal += brightness
            saturationTotal += saturation

            if brightness > 0.9 && saturation < 0.1 {
                whiteCount += 1
            }
        }

        return ImageStats(
            averageBrightness: brightnessTotal / Double(pixelCount),
            averageSaturation: saturationTotal / Double(pixelCount),
            whiteRatio: Double(whiteCount) / Double(pixelCount)
        )
    }
}

private struct ImageStats {
    let averageBrightness: Double
    let averageSaturation: Double
    let whiteRatio: Double

    static let zero = ImageStats(averageBrightness: 0, averageSaturation: 0, whiteRatio: 0)
}
