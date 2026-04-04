import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let fileManager = FileManager.default
let cwd = URL(fileURLWithPath: fileManager.currentDirectoryPath)
let inputURL = URL(fileURLWithPath: "appstore_assets/photo_calendar_app_icon_1024.png", relativeTo: cwd)
let outputURL = URL(fileURLWithPath: "appstore_assets/photo_calendar_app_icon_opaque_1024.png", relativeTo: cwd)

guard let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fatalError("Failed to load source icon")
}

let width = image.width
let height = image.height
let colorSpace = CGColorSpaceCreateDeviceRGB()
let bitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

guard let context = CGContext(
    data: nil,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: bitmapInfo
) else {
    fatalError("Failed to create bitmap context")
}

context.setFillColor(red: 7.0 / 255.0, green: 8.0 / 255.0, blue: 11.0 / 255.0, alpha: 1.0)
context.fill(CGRect(x: 0, y: 0, width: width, height: height))
context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

guard let flattened = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("Failed to encode flattened icon")
}

CGImageDestinationAddImage(destination, flattened, [
    kCGImageDestinationLossyCompressionQuality: 1.0
] as CFDictionary)

guard CGImageDestinationFinalize(destination) else {
    fatalError("Failed to write flattened icon")
}

print(outputURL.path)
