import SwiftUI
import AppKit
import CoreGraphics

public enum AppIcon {
    /// Exact vector path data from `icon.svg` (`viewBox="0 0 240 240"`):
    /// Music note glyph path (`fill="white"`)
    public static let musicNotePathD = "M50.875 158.203C46.9583 154.286 45 149.578 45 144.078C45 138.578 46.9583 133.869 50.875 129.953C54.7917 126.036 59.5 124.078 65 124.078C66.9167 124.078 68.6875 124.307 70.3125 124.765C71.9375 125.223 73.5 125.911 75 126.828V88.3276C75 87.0776 75.3958 85.9734 76.1875 85.0151C76.9792 84.0568 77.9583 83.4943 79.125 83.3276L129.125 75.0776C130.625 74.8276 131.979 75.1818 133.188 76.1401C134.396 77.0984 135 78.3693 135 79.9526V134.078C135 139.578 133.042 144.286 129.125 148.203C125.208 152.119 120.5 154.078 115 154.078C109.5 154.078 104.792 152.119 100.875 148.203C96.9583 144.286 95 139.578 95 134.078C95 128.578 96.9583 123.869 100.875 119.953C104.792 116.036 109.5 114.078 115 114.078C116.917 114.078 118.688 114.307 120.312 114.765C121.938 115.223 123.5 115.911 125 116.828V96.2026L85 104.078V144.078C85 149.578 83.0417 154.286 79.125 158.203C75.2083 162.119 70.5 164.078 65 164.078C59.5 164.078 54.7917 162.119 50.875 158.203Z"

    public static func renderPNGData(pixelSize: Int) -> Data? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                  data: nil,
                  width: pixelSize,
                  height: pixelSize,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }

        draw(in: ctx, pixelSize: pixelSize)

        guard let cgImage = ctx.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .png, properties: [:])
    }

    public static func renderNSImage(pointSize: CGFloat = 512) -> NSImage {
        let image = NSImage(size: NSSize(width: pointSize, height: pointSize))
        for scale in [1, 2] {
            let pixelSize = Int(pointSize) * scale
            if let data = renderPNGData(pixelSize: pixelSize),
               let rep = NSBitmapImageRep(data: data) {
                rep.size = NSSize(width: pointSize, height: pointSize)
                image.addRepresentation(rep)
            }
        }
        return image
    }

    public static func renderPlaceholderPNGData(pixelSize: Int) -> Data? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                  data: nil,
                  width: pixelSize,
                  height: pixelSize,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }

        drawPlaceholderArtwork(in: ctx, pixelSize: pixelSize)

        guard let cgImage = ctx.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .png, properties: [:])
    }

    /// Renders `icon.svg` full-bleed as a square placeholder album cover without rounded corners or margins.
    public static func renderPlaceholderArtwork(pointSize: CGFloat = 136) -> NSImage {
        let image = NSImage(size: NSSize(width: pointSize, height: pointSize))
        for scale in [1, 2] {
            let pixelSize = Int(pointSize) * scale
            if let data = renderPlaceholderPNGData(pixelSize: pixelSize),
               let rep = NSBitmapImageRep(data: data) {
                rep.size = NSSize(width: pointSize, height: pointSize)
                image.addRepresentation(rep)
            }
        }
        return image
    }

    public static func generate(size: CGFloat = 512) -> NSImage {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return renderNSImage(pointSize: size)
    }

    public static func writeIconset(to directoryURL: URL) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let specs: [(name: String, pixels: Int)] = [
            ("icon_16x16.png", 16),
            ("icon_16x16@2x.png", 32),
            ("icon_32x32.png", 32),
            ("icon_32x32@2x.png", 64),
            ("icon_128x128.png", 128),
            ("icon_128x128@2x.png", 256),
            ("icon_256x256.png", 256),
            ("icon_256x256@2x.png", 512),
            ("icon_512x512.png", 512),
            ("icon_512x512@2x.png", 1024)
        ]
        for spec in specs {
            guard let pngData = renderPNGData(pixelSize: spec.pixels) else {
                throw CocoaError(.fileWriteUnknown)
            }
            try pngData.write(to: directoryURL.appendingPathComponent(spec.name))
        }
    }

    private static func draw(in ctx: CGContext, pixelSize: Int) {
        let size = CGFloat(pixelSize)
        let scale = size / 1024.0

        ctx.saveGState()
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)
        ctx.interpolationQuality = .high

        // Flip vertically so (0, 0) is top-left matching `icon.svg` coordinates
        ctx.translateBy(x: 0, y: size)
        ctx.scaleBy(x: scale, y: -scale)

        let iconRect = CGRect(x: 100, y: 100, width: 824, height: 824)
        let cornerRadius: CGFloat = 185.4
        let squirclePath = Path(
            roundedRect: iconRect,
            cornerRadius: cornerRadius,
            style: .continuous
        ).cgPath

        // Outer macOS icon drop shadow applied to the squircle layer as a whole
        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: -10.0 * scale),
            blur: 24.0 * scale,
            color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.28)
        )
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)

        // Clip to squircle and map 240x240 `icon.svg` viewBox into 824x824 squircle
        ctx.addPath(squirclePath)
        ctx.clip()

        ctx.translateBy(x: iconRect.minX, y: iconRect.minY)
        let svgScale: CGFloat = 824.0 / 240.0
        ctx.scaleBy(x: svgScale, y: svgScale)

        drawSVGElements(in: ctx)

        ctx.endTransparencyLayer()
        ctx.restoreGState()
        ctx.restoreGState()
    }

    private static func drawPlaceholderArtwork(in ctx: CGContext, pixelSize: Int) {
        let size = CGFloat(pixelSize)
        let svgScale = size / 240.0

        ctx.saveGState()
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)
        ctx.interpolationQuality = .high

        // Flip vertically so (0, 0) is top-left matching `icon.svg` coordinates
        ctx.translateBy(x: 0, y: size)
        ctx.scaleBy(x: svgScale, y: -svgScale)

        drawSVGElements(in: ctx)

        ctx.restoreGState()
    }

    private static func drawSVGElements(in ctx: CGContext) {
        let whiteColor = CGColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
        let blackColor = CGColor(srgbRed: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
        let lightPinkColor = CGColor(srgbRed: 0xFF / 255.0, green: 0xA8 / 255.0, blue: 0xA8 / 255.0, alpha: 1.0)
        let coralRedColor = CGColor(srgbRed: 0xFF / 255.0, green: 0x52 / 255.0, blue: 0x52 / 255.0, alpha: 1.0)
        let deepRedColor = CGColor(srgbRed: 0xFA / 255.0, green: 0x00 / 255.0, blue: 0x00 / 255.0, alpha: 1.0)

        // <path d="M240 180H180V240H240V180Z" fill="white"/>
        ctx.setFillColor(whiteColor)
        ctx.fill(CGRect(x: 179.5, y: 179.5, width: 60.5, height: 60.5))

        // <path d="M240 120H180V180H240V120Z" fill="#FFA8A8"/>
        ctx.setFillColor(lightPinkColor)
        ctx.fill(CGRect(x: 179.5, y: 119.5, width: 60.5, height: 60.5))

        // <path d="M240 60H180V120H240V60Z" fill="#FF5252"/>
        ctx.setFillColor(coralRedColor)
        ctx.fill(CGRect(x: 179.5, y: 59.5, width: 60.5, height: 60.5))

        // <path d="M240 0H180V60H240V0Z" fill="#FA0000"/>
        ctx.setFillColor(deepRedColor)
        ctx.fill(CGRect(x: 179.5, y: 0, width: 60.5, height: 60.5))

        // <path d="M180 0H0V240H180V0Z" fill="black"/>
        ctx.setFillColor(blackColor)
        ctx.fill(CGRect(x: 0, y: 0, width: 180, height: 240))

        // <path ... fill="white"/> (music note)
        ctx.addPath(parseSVGPath(musicNotePathD))
        ctx.setFillColor(whiteColor)
        ctx.fillPath()
    }

    /// Parses SVG path commands (`M`, `L`, `H`, `V`, `C`, `Z`) into a `CGPath`.
    public static func parseSVGPath(_ d: String) -> CGPath {
        let path = CGMutablePath()
        var index = d.startIndex
        var currentPoint = CGPoint.zero
        var subpathStart = CGPoint.zero
        var currentCommand: Character = " "

        func skipSeparators() {
            while index < d.endIndex && (d[index].isWhitespace || d[index] == ",") {
                index = d.index(after: index)
            }
        }

        func readNumber() -> CGFloat? {
            skipSeparators()
            guard index < d.endIndex else { return nil }
            let start = index
            if d[index] == "-" || d[index] == "+" {
                index = d.index(after: index)
            }
            var hasDigits = false
            while index < d.endIndex && d[index].isNumber {
                hasDigits = true
                index = d.index(after: index)
            }
            if index < d.endIndex && d[index] == "." {
                index = d.index(after: index)
                while index < d.endIndex && d[index].isNumber {
                    hasDigits = true
                    index = d.index(after: index)
                }
            }
            guard hasDigits, let val = Double(d[start..<index]) else { return nil }
            return CGFloat(val)
        }

        while index < d.endIndex {
            skipSeparators()
            guard index < d.endIndex else { break }

            let ch = d[index]
            if ch.isLetter {
                currentCommand = ch
                index = d.index(after: index)
            }

            switch currentCommand {
            case "M":
                if let x = readNumber(), let y = readNumber() {
                    currentPoint = CGPoint(x: x, y: y)
                    subpathStart = currentPoint
                    path.move(to: currentPoint)
                    currentCommand = "L"
                }
            case "L":
                if let x = readNumber(), let y = readNumber() {
                    currentPoint = CGPoint(x: x, y: y)
                    path.addLine(to: currentPoint)
                }
            case "H":
                if let x = readNumber() {
                    currentPoint = CGPoint(x: x, y: currentPoint.y)
                    path.addLine(to: currentPoint)
                }
            case "V":
                if let y = readNumber() {
                    currentPoint = CGPoint(x: currentPoint.x, y: y)
                    path.addLine(to: currentPoint)
                }
            case "C":
                if let x1 = readNumber(), let y1 = readNumber(),
                   let x2 = readNumber(), let y2 = readNumber(),
                   let x = readNumber(), let y = readNumber() {
                    let end = CGPoint(x: x, y: y)
                    path.addCurve(
                        to: end,
                        control1: CGPoint(x: x1, y: y1),
                        control2: CGPoint(x: x2, y: y2)
                    )
                    currentPoint = end
                }
            case "Z", "z":
                path.closeSubpath()
                currentPoint = subpathStart
                currentCommand = " "
            default:
                index = d.index(after: index)
            }
        }

        return path
    }
}

