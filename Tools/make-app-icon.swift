// Renders the app icons into the asset catalogs of the Mac app and the iPhone app.
// Usage: swift Tools/make-app-icon.swift   (from the repository root)

import AppKit

let macDirectory = URL(fileURLWithPath: "MacVocTrainNg/Resources/Assets.xcassets/AppIcon.appiconset")
let iOSDirectory = URL(fileURLWithPath: "VocTrain/Resources/Assets.xcassets/AppIcon.appiconset")

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

/// Draws the icon on a 1024 × 1024 canvas (origin bottom left). With `fullBleed`, the
/// tile fills the canvas without rounded corners and shadow: iOS rounds them itself.
func drawIcon(in context: CGContext, fullBleed: Bool) {
    // Tile: macOS icon grid, 824 pt rounded square centred on the canvas.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath: CGPath
    if fullBleed {
        // Enlarges the tile to the canvas; everything on it is drawn as for macOS.
        context.scaleBy(x: 1024 / tile.width, y: 1024 / tile.height)
        context.translateBy(x: -tile.minX, y: -tile.minY)
        tilePath = CGPath(rect: tile, transform: nil)
    } else {
        tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, alpha: 0.35))
        context.addPath(tilePath)
        context.setFillColor(color(0x1C5CAB))
        context.fillPath()
        context.restoreGState()
    }

    context.saveGState()
    context.addPath(tilePath)
    context.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [color(0x5598E7), color(0x1C5CAB), color(0x104281)] as CFArray,
        locations: [0, 0.6, 1]
    )!
    context.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    context.restoreGState()

    // An index card, drawn centred at the origin.
    func card(rotation: CGFloat, offset: CGPoint, fill: UInt32, ruled: Bool) {
        let size = CGSize(width: 560, height: 380)
        let rect = CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
        context.saveGState()
        context.translateBy(x: 512 + offset.x, y: 512 + offset.y)
        context.rotate(by: rotation * .pi / 180)

        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: color(0x000000, alpha: 0.30))
        context.addPath(CGPath(roundedRect: rect, cornerWidth: 26, cornerHeight: 26, transform: nil))
        context.setFillColor(color(fill))
        context.fillPath()
        context.restoreGState()

        if ruled {
            context.saveGState()
            context.addPath(CGPath(roundedRect: rect, cornerWidth: 26, cornerHeight: 26, transform: nil))
            context.clip()
            // Red header line and blue rules, like a paper index card.
            context.setFillColor(color(0xD03B3B))
            context.fill(CGRect(x: rect.minX, y: rect.maxY - 92, width: rect.width, height: 7))
            context.setFillColor(color(0x86B6EF, alpha: 0.7))
            for index in 0..<5 {
                context.fill(CGRect(x: rect.minX, y: rect.maxY - 150 - CGFloat(index) * 52, width: rect.width, height: 4))
            }
            context.restoreGState()
        }
        context.restoreGState()
    }

    card(rotation: 9, offset: CGPoint(x: 26, y: 58), fill: 0xB7D3F6, ruled: false)
    card(rotation: -5, offset: CGPoint(x: -10, y: -28), fill: 0xFFFFFF, ruled: true)

    // "Aa" on the front card.
    context.saveGState()
    context.translateBy(x: 502, y: 484)
    context.rotate(by: -5 * .pi / 180)
    let font = NSFont.systemFont(ofSize: 250, weight: .heavy)
    let roundedFont = font.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 250) } ?? font
    let text = NSAttributedString(
        string: "Aa",
        attributes: [
            .font: roundedFont,
            .foregroundColor: NSColor(cgColor: color(0x104281))!,
        ])
    let line = CTLineCreateWithAttributedString(text)
    let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    context.textPosition = CGPoint(x: -bounds.midX, y: -bounds.midY)
    CTLineDraw(line, context)
    context.restoreGState()
}

/// Renders the icon as PNG. The full-bleed icon has no alpha channel, as the App Store
/// requires for iOS.
func render(pixels: Int, fullBleed: Bool = false) -> Data {
    let context = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: (fullBleed ? CGImageAlphaInfo.noneSkipLast : .premultipliedLast).rawValue
    )!
    context.interpolationQuality = .high
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    drawIcon(in: context, fullBleed: fullBleed)
    let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
    return bitmap.representation(using: .png, properties: [:])!
}

func writeContents(_ images: [[String: String]], to directory: URL) throws {
    let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
    let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    try json.write(to: directory.appendingPathComponent("Contents.json"))
    print("Wrote \(images.count) icon images to \(directory.path)")
}

var macImages: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try render(pixels: points * scale).write(to: macDirectory.appendingPathComponent(name))
        macImages.append(["idiom": "mac", "scale": "\(scale)x", "size": "\(points)x\(points)", "filename": name])
    }
}
try writeContents(macImages, to: macDirectory)

// iOS takes a single image and scales it to every size.
let iOSName = "icon_1024x1024.png"
try render(pixels: 1024, fullBleed: true).write(to: iOSDirectory.appendingPathComponent(iOSName))
try writeContents([["idiom": "universal", "platform": "ios", "size": "1024x1024", "filename": iOSName]], to: iOSDirectory)
