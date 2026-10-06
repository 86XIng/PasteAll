// Draws the DMG window background: a light gray canvas with a dashed arrow
// pointing from PasteAll to Applications. Regenerate after layout changes:
//   swift packaging/dmg/make-background.swift packaging/dmg
// Coordinates match icon_locations in dmg-settings.py (top-left origin, points).
import AppKit

let canvas = CGSize(width: 560, height: 420)
let arrowCenter = CGPoint(x: 280, y: 236)
let background = CGColor(red: 232 / 255, green: 230 / 255, blue: 230 / 255, alpha: 1)
let stroke = CGColor(red: 0.25, green: 0.25, blue: 0.25, alpha: 1)

func arrowPath(center: CGPoint) -> CGPath {
    let shaftLength: CGFloat = 46, shaftHeight: CGFloat = 34
    let headLength: CGFloat = 52, headHeight: CGFloat = 86
    let left = center.x - (shaftLength + headLength) / 2
    let neck = left + shaftLength
    let tip = neck + headLength
    let path = CGMutablePath()
    path.move(to: CGPoint(x: left, y: center.y - shaftHeight / 2))
    path.addLine(to: CGPoint(x: neck, y: center.y - shaftHeight / 2))
    path.addLine(to: CGPoint(x: neck, y: center.y - headHeight / 2))
    path.addLine(to: CGPoint(x: tip, y: center.y))
    path.addLine(to: CGPoint(x: neck, y: center.y + headHeight / 2))
    path.addLine(to: CGPoint(x: neck, y: center.y + shaftHeight / 2))
    path.addLine(to: CGPoint(x: left, y: center.y + shaftHeight / 2))
    path.closeSubpath()
    return path
}

func render(scale: CGFloat, to url: URL) throws {
    let width = Int(canvas.width * scale), height = Int(canvas.height * scale)
    guard let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { throw CocoaError(.fileWriteUnknown) }

    // Flip to a top-left origin so coordinates read like Finder's.
    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: scale, y: -scale)

    context.setFillColor(background)
    context.fill(CGRect(origin: .zero, size: canvas))

    context.addPath(arrowPath(center: arrowCenter))
    context.setStrokeColor(stroke)
    context.setLineWidth(2)
    context.setLineJoin(.miter)
    context.setLineDash(phase: 0, lengths: [6, 4])
    context.strokePath()

    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
    else { throw CocoaError(.fileWriteUnknown) }
    // 72 DPI per point, so the 2x file is recognized as a HiDPI variant.
    let dpi = 72 * scale
    CGImageDestinationAddImage(destination, image, [
        kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi,
    ] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
}

let directory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")
try render(scale: 1, to: directory.appendingPathComponent("background.png"))
try render(scale: 2, to: directory.appendingPathComponent("background@2x.png"))
print("Wrote background.png and background@2x.png to \(directory.path)")
