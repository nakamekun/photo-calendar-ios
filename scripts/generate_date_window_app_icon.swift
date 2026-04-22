import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

private let canvasSize: CGFloat = 1024
private let fileManager = FileManager.default
private let cwd = URL(fileURLWithPath: fileManager.currentDirectoryPath)
private let appIconDirectory = cwd.appendingPathComponent("PhotoCalendarApp/Resources/Assets.xcassets/AppIcon.appiconset")
private let appStoreDirectory = cwd.appendingPathComponent("appstore_assets")
private let conceptsDirectory = appStoreDirectory.appendingPathComponent("icon_concepts")

private struct IconVariant {
    let slug: String
    let background: UInt32
    let backgroundAccent: UInt32
    let photoTop: UInt32
    let photoMiddle: UInt32
    let photoBottom: UInt32
    let glow: UInt32
    let spark: UInt32
    let badgeFill: UInt32
    let badgeText: UInt32
    let badgeSubtext: UInt32
    let horizonA: UInt32
    let horizonB: UInt32
    let rayAlpha: CGFloat
    let glowAlpha: CGFloat
    let badgeScale: CGFloat
    let photoRotation: CGFloat
    let hasLiftedLight: Bool
    let hasCornerCurl: Bool
}

private let dramaticLight = IconVariant(
    slug: "a-dramatic-light",
    background: 0x20354A,
    backgroundAccent: 0x304F68,
    photoTop: 0xFFC15D,
    photoMiddle: 0xF1782F,
    photoBottom: 0x182F45,
    glow: 0xFFE073,
    spark: 0xFFFFFF,
    badgeFill: 0xF8F4EC,
    badgeText: 0x17202A,
    badgeSubtext: 0xA05F36,
    horizonA: 0xB94E30,
    horizonB: 0x183248,
    rayAlpha: 0.42,
    glowAlpha: 0.98,
    badgeScale: 1.28,
    photoRotation: -0.032,
    hasLiftedLight: true,
    hasCornerCurl: false
)

private let refinedContrast = IconVariant(
    slug: "b-refined-contrast",
    background: 0x243446,
    backgroundAccent: 0x38536B,
    photoTop: 0xFFB451,
    photoMiddle: 0xDB5E34,
    photoBottom: 0x13283A,
    glow: 0xFFD56B,
    spark: 0xFFF7D8,
    badgeFill: 0xF5F2EA,
    badgeText: 0x151D26,
    badgeSubtext: 0x8D563B,
    horizonA: 0x9E4A34,
    horizonB: 0x162B3D,
    rayAlpha: 0.28,
    glowAlpha: 0.82,
    badgeScale: 1.22,
    photoRotation: 0.014,
    hasLiftedLight: false,
    hasCornerCurl: true
)

private let selectedVariant = dramaticLight
private let conceptVariants = [dramaticLight, refinedContrast]

private struct IconImage {
    let filename: String
    let side: Int
}

private let outputImages: [IconImage] = [
    IconImage(filename: "icon-20@2x.png", side: 40),
    IconImage(filename: "icon-20@3x.png", side: 60),
    IconImage(filename: "icon-29@2x.png", side: 58),
    IconImage(filename: "icon-29@3x.png", side: 87),
    IconImage(filename: "icon-40@2x.png", side: 80),
    IconImage(filename: "icon-40@3x.png", side: 120),
    IconImage(filename: "icon-60@2x.png", side: 120),
    IconImage(filename: "icon-60@3x.png", side: 180),
    IconImage(filename: "icon-ipad-20@1x.png", side: 20),
    IconImage(filename: "icon-ipad-20@2x.png", side: 40),
    IconImage(filename: "icon-ipad-29@1x.png", side: 29),
    IconImage(filename: "icon-ipad-29@2x.png", side: 58),
    IconImage(filename: "icon-ipad-40@1x.png", side: 40),
    IconImage(filename: "icon-ipad-40@2x.png", side: 80),
    IconImage(filename: "icon-ipad-76@2x.png", side: 152),
    IconImage(filename: "icon-ipad-83.5@2x.png", side: 167),
    IconImage(filename: "icon-1024.png", side: 1024),
]

private func rectFromTop(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> CGRect {
    CGRect(x: x, y: canvasSize - y - height, width: width, height: height)
}

private func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 0xff) / 255,
        green: CGFloat((hex >> 8) & 0xff) / 255,
        blue: CGFloat(hex & 0xff) / 255,
        alpha: alpha
    )
}

private func drawText(
    _ text: String,
    context: CGContext,
    rect: CGRect,
    fontName: String,
    fontSize: CGFloat,
    color: CGColor,
    alignment: CTTextAlignment = .center
) {
    let font = CTFontCreateWithName(fontName as CFString, fontSize, nil)
    let attributes: [CFString: Any] = [
        kCTFontAttributeName: font,
        kCTForegroundColorAttributeName: color,
    ]
    let attributed = CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary)!
    let line = CTLineCreateWithAttributedString(attributed)

    var ascent: CGFloat = 0
    var descent: CGFloat = 0
    var leading: CGFloat = 0
    let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
    let x: CGFloat
    switch alignment {
    case .left:
        x = rect.minX
    case .right:
        x = rect.maxX - width
    default:
        x = rect.midX - (width / 2)
    }
    let baselineY = rect.midY - ((ascent - descent) / 2)

    context.textMatrix = .identity
    context.textPosition = CGPoint(x: x, y: baselineY)
    CTLineDraw(line, context)
}

private func drawIconContent(in context: CGContext, variant: IconVariant) {
    context.setFillColor(color(variant.background))
    context.fill(CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize))

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let backgroundGradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [color(variant.backgroundAccent), color(variant.background)] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        backgroundGradient,
        start: CGPoint(x: canvasSize * 0.1, y: canvasSize),
        end: CGPoint(x: canvasSize, y: 0),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )

    let photoRect = rectFromTop(x: 118, y: 244, width: 788, height: 614)
    let photoPath = CGPath(roundedRect: photoRect, cornerWidth: 112, cornerHeight: 112, transform: nil)
    if variant.hasLiftedLight {
        let outsideRay = CGMutablePath()
        outsideRay.move(to: CGPoint(x: photoRect.maxX - 56, y: photoRect.maxY + 62))
        outsideRay.addLine(to: CGPoint(x: photoRect.maxX + 96, y: photoRect.maxY + 44))
        outsideRay.addLine(to: CGPoint(x: photoRect.minX + 302, y: photoRect.minY - 44))
        outsideRay.addLine(to: CGPoint(x: photoRect.minX + 178, y: photoRect.minY - 22))
        outsideRay.closeSubpath()
        context.addPath(outsideRay)
        context.setFillColor(color(variant.glow, alpha: 0.22))
        context.fillPath()
    }

    context.saveGState()
    context.translateBy(x: photoRect.midX, y: photoRect.midY)
    context.rotate(by: variant.photoRotation)
    context.translateBy(x: -photoRect.midX, y: -photoRect.midY)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -36), blur: 58, color: color(0x000000, alpha: 0.42))
    context.addPath(photoPath)
    context.setFillColor(color(variant.photoBottom))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(photoPath)
    context.clip()

    let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [color(variant.photoTop), color(variant.photoMiddle), color(variant.photoBottom)] as CFArray,
        locations: [0, 0.42, 1]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: photoRect.midX, y: photoRect.maxY),
        end: CGPoint(x: photoRect.midX, y: photoRect.minY),
        options: []
    )

    let lowerContrast = CGGradient(
        colorsSpace: colorSpace,
        colors: [color(0x000000, alpha: 0.0), color(0x000000, alpha: 0.34)] as CFArray,
        locations: [0.42, 1]
    )!
    context.drawLinearGradient(
        lowerContrast,
        start: CGPoint(x: photoRect.midX, y: photoRect.maxY),
        end: CGPoint(x: photoRect.midX, y: photoRect.minY),
        options: []
    )

    let radial = CGGradient(
        colorsSpace: colorSpace,
        colors: [color(variant.glow, alpha: variant.glowAlpha), color(variant.glow, alpha: 0.0)] as CFArray,
        locations: [0, 1]
    )!
    context.drawRadialGradient(
        radial,
        startCenter: CGPoint(x: photoRect.maxX - 178, y: photoRect.maxY - 128),
        startRadius: 4,
        endCenter: CGPoint(x: photoRect.maxX - 178, y: photoRect.maxY - 128),
        endRadius: 310,
        options: []
    )

    context.setFillColor(color(variant.horizonA, alpha: 0.66))
    let sand = CGMutablePath()
    sand.move(to: CGPoint(x: photoRect.minX, y: photoRect.minY + 132))
    sand.addCurve(
        to: CGPoint(x: photoRect.maxX, y: photoRect.minY + 182),
        control1: CGPoint(x: photoRect.minX + 230, y: photoRect.minY + 236),
        control2: CGPoint(x: photoRect.maxX - 190, y: photoRect.minY + 96)
    )
    sand.addLine(to: CGPoint(x: photoRect.maxX, y: photoRect.minY))
    sand.addLine(to: CGPoint(x: photoRect.minX, y: photoRect.minY))
    sand.closeSubpath()
    context.addPath(sand)
    context.fillPath()

    context.setFillColor(color(variant.horizonB, alpha: 0.7))
    let hill = CGMutablePath()
    hill.move(to: CGPoint(x: photoRect.minX, y: photoRect.minY + 220))
    hill.addCurve(
        to: CGPoint(x: photoRect.maxX, y: photoRect.minY + 252),
        control1: CGPoint(x: photoRect.minX + 250, y: photoRect.minY + 330),
        control2: CGPoint(x: photoRect.maxX - 220, y: photoRect.minY + 168)
    )
    hill.addLine(to: CGPoint(x: photoRect.maxX, y: photoRect.minY))
    hill.addLine(to: CGPoint(x: photoRect.minX, y: photoRect.minY))
    hill.closeSubpath()
    context.addPath(hill)
    context.fillPath()

    context.setFillColor(color(variant.glow, alpha: 0.98))
    context.fillEllipse(in: CGRect(x: photoRect.maxX - 196, y: photoRect.maxY - 146, width: 58, height: 58))
    context.setFillColor(color(variant.spark, alpha: 0.9))
    context.fillEllipse(in: CGRect(x: photoRect.maxX - 178, y: photoRect.maxY - 128, width: 20, height: 20))

    context.setFillColor(color(variant.spark, alpha: 0.2))
    context.fillEllipse(in: CGRect(x: photoRect.maxX - 332, y: photoRect.maxY - 206, width: 26, height: 26))
    context.fillEllipse(in: CGRect(x: photoRect.maxX - 270, y: photoRect.maxY - 272, width: 14, height: 14))

    context.setFillColor(color(variant.spark, alpha: variant.rayAlpha))
    let lightRay = CGMutablePath()
    lightRay.move(to: CGPoint(x: photoRect.maxX - 186, y: photoRect.maxY))
    lightRay.addLine(to: CGPoint(x: photoRect.maxX - 52, y: photoRect.maxY))
    lightRay.addLine(to: CGPoint(x: photoRect.minX + 262, y: photoRect.minY))
    lightRay.addLine(to: CGPoint(x: photoRect.minX + 128, y: photoRect.minY))
    lightRay.closeSubpath()
    context.addPath(lightRay)
    context.fillPath()

    context.setStrokeColor(color(variant.spark, alpha: variant.rayAlpha * 0.76))
    context.setLineWidth(10)
    context.move(to: CGPoint(x: photoRect.maxX - 132, y: photoRect.maxY - 8))
    context.addLine(to: CGPoint(x: photoRect.minX + 208, y: photoRect.minY + 18))
    context.strokePath()

    if variant.hasCornerCurl {
        let curl = CGMutablePath()
        curl.move(to: CGPoint(x: photoRect.maxX - 130, y: photoRect.minY))
        curl.addQuadCurve(to: CGPoint(x: photoRect.maxX, y: photoRect.minY + 112), control: CGPoint(x: photoRect.maxX - 12, y: photoRect.minY + 10))
        curl.addLine(to: CGPoint(x: photoRect.maxX, y: photoRect.minY))
        curl.closeSubpath()
        context.addPath(curl)
        context.setFillColor(color(0xFFFFFF, alpha: 0.18))
        context.fillPath()
    }
    context.restoreGState()

    context.addPath(photoPath)
    context.setStrokeColor(color(0xFFFFFF, alpha: 0.18))
    context.setLineWidth(3)
    context.strokePath()
    context.restoreGState()

    let badgeWidth = 250 * variant.badgeScale
    let badgeHeight = 214 * variant.badgeScale
    let badgeRect = rectFromTop(x: 168, y: 136, width: badgeWidth, height: badgeHeight)
    let badgePath = CGPath(roundedRect: badgeRect, cornerWidth: 62, cornerHeight: 62, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -20), blur: 38, color: color(0x000000, alpha: 0.36))
    context.addPath(badgePath)
    context.setFillColor(color(variant.badgeFill))
    context.fillPath()
    context.restoreGState()

    context.addPath(badgePath)
    context.setStrokeColor(color(0xFFFFFF, alpha: 0.28))
    context.setLineWidth(2)
    context.strokePath()

    drawText(
        "APR",
        context: context,
        rect: CGRect(x: badgeRect.minX + 48, y: badgeRect.maxY - (74 * variant.badgeScale), width: badgeRect.width - 96, height: 42 * variant.badgeScale),
        fontName: "HelveticaNeue-Bold",
        fontSize: 35 * variant.badgeScale,
        color: color(variant.badgeSubtext),
        alignment: .left
    )
    drawText(
        "1",
        context: context,
        rect: CGRect(x: badgeRect.minX, y: badgeRect.minY + (4 * variant.badgeScale), width: badgeRect.width, height: 168 * variant.badgeScale),
        fontName: "HelveticaNeue-CondensedBlack",
        fontSize: 172 * variant.badgeScale,
        color: color(variant.badgeText)
    )
}

private func makeIcon(side: Int, variant: IconVariant) -> CGImage {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: side,
        height: side,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
    ) else {
        fatalError("Failed to create context")
    }

    let scale = CGFloat(side) / canvasSize
    context.interpolationQuality = .high
    context.scaleBy(x: scale, y: scale)
    drawIconContent(in: context, variant: variant)

    guard let image = context.makeImage() else {
        fatalError("Failed to make image")
    }
    return image
}

private func writePNG(_ image: CGImage, to url: URL) {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("Failed to create destination for \(url.path)")
    }
    CGImageDestinationAddImage(destination, image, [
        kCGImageDestinationLossyCompressionQuality: 1.0
    ] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
        fatalError("Failed to write \(url.path)")
    }
}

try fileManager.createDirectory(at: appStoreDirectory, withIntermediateDirectories: true)
try fileManager.createDirectory(at: conceptsDirectory, withIntermediateDirectories: true)

for output in outputImages {
    writePNG(makeIcon(side: output.side, variant: selectedVariant), to: appIconDirectory.appendingPathComponent(output.filename))
}

let marketingIcon = makeIcon(side: 1024, variant: selectedVariant)
writePNG(marketingIcon, to: appStoreDirectory.appendingPathComponent("photo_calendar_app_icon_1024.png"))
writePNG(marketingIcon, to: appStoreDirectory.appendingPathComponent("photo_calendar_app_icon_opaque_1024.png"))

for variant in conceptVariants {
    writePNG(
        makeIcon(side: 1024, variant: variant),
        to: conceptsDirectory.appendingPathComponent("photo_calendar_icon_\(variant.slug)_1024.png")
    )
}

print("Generated One Photo Per Day app icon variants")
