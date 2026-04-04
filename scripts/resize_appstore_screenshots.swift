import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct Config {
    let inputDir: URL
    let outputDir: URL
    let prefix: String
    let targetWidth: Int
    let targetHeight: Int
}

enum ResizeError: Error, CustomStringConvertible {
    case invalidArguments
    case loadFailed(String)
    case cgImageMissing(String)
    case destinationCreateFailed(String)
    case writeFailed(String)

    var description: String {
        switch self {
        case .invalidArguments:
            return "usage: resize_appstore_screenshots.swift <inputDir> <outputDir> <prefix> <targetWidth> <targetHeight>"
        case .loadFailed(let path):
            return "failed to load image: \(path)"
        case .cgImageMissing(let path):
            return "failed to create CGImage for: \(path)"
        case .destinationCreateFailed(let path):
            return "failed to create destination: \(path)"
        case .writeFailed(let path):
            return "failed to write PNG: \(path)"
        }
    }
}

func parseConfig() throws -> Config {
    let args = CommandLine.arguments
    guard args.count == 6,
          let targetWidth = Int(args[4]),
          let targetHeight = Int(args[5]) else {
        throw ResizeError.invalidArguments
    }

    return Config(
        inputDir: URL(fileURLWithPath: args[1], isDirectory: true),
        outputDir: URL(fileURLWithPath: args[2], isDirectory: true),
        prefix: args[3],
        targetWidth: targetWidth,
        targetHeight: targetHeight
    )
}

func sourceFiles(in directory: URL) throws -> [URL] {
    let files = try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
    )

    return files
        .filter { $0.pathExtension.lowercased() == "png" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
}

func cgImage(for url: URL) throws -> CGImage {
    guard let nsImage = NSImage(contentsOf: url) else {
        throw ResizeError.loadFailed(url.path)
    }

    var proposedRect = CGRect(origin: .zero, size: nsImage.size)
    guard let image = nsImage.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
        throw ResizeError.cgImageMissing(url.path)
    }

    return image
}

func drawResizedImage(_ image: CGImage, width: Int, height: Int) -> CGImage? {
    let targetSize = CGSize(width: width, height: height)
    let sourceSize = CGSize(width: image.width, height: image.height)
    let scale = max(targetSize.width / sourceSize.width, targetSize.height / sourceSize.height)

    let scaledSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
    let drawRect = CGRect(
        x: (targetSize.width - scaledSize.width) / 2.0,
        y: (targetSize.height - scaledSize.height) / 2.0,
        width: scaledSize.width,
        height: scaledSize.height
    )

    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
        return nil
    }

    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else {
        return nil
    }

    context.interpolationQuality = .high
    context.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
    context.fill(CGRect(origin: .zero, size: targetSize))
    context.draw(image, in: drawRect)

    return context.makeImage()
}

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        throw ResizeError.destinationCreateFailed(url.path)
    }

    let properties: [CFString: Any] = [
        kCGImagePropertyPNGDictionary: [:]
    ]
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)

    guard CGImageDestinationFinalize(destination) else {
        throw ResizeError.writeFailed(url.path)
    }
}

do {
    let config = try parseConfig()
    let fileManager = FileManager.default
    try fileManager.createDirectory(at: config.outputDir, withIntermediateDirectories: true)

    let files = try sourceFiles(in: config.inputDir)
    for (index, fileURL) in files.enumerated() {
        let image = try cgImage(for: fileURL)
        guard let resized = drawResizedImage(image, width: config.targetWidth, height: config.targetHeight) else {
            throw ResizeError.cgImageMissing(fileURL.path)
        }

        let name = String(format: "%@_%02d.png", config.prefix, index + 1)
        let outputURL = config.outputDir.appendingPathComponent(name)
        try writePNG(resized, to: outputURL)
        print(outputURL.path)
    }
} catch {
    fputs("\(error)\n", stderr)
    exit(1)
}
