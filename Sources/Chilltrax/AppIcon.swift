import SwiftUI
import AppKit
import CoreGraphics

public enum AppIcon {
    /// Exact vector path data from `icon.svg` (`viewBox="0 0 240 240"`):
    /// 1. Center dot path (`fill="white"`)
    public static let centerDotPathD = "M90 108.75C92.9837 108.75 95.8452 109.935 97.9549 112.045C100.065 114.155 101.25 117.016 101.25 120C101.25 122.984 100.065 125.845 97.9549 127.955C95.8452 130.065 92.9837 131.25 90 131.25C87.0163 131.25 84.1548 130.065 82.0451 127.955C79.9353 125.845 78.75 122.984 78.75 120C78.75 117.016 79.9353 114.155 82.0451 112.045C84.1548 109.935 87.0163 108.75 90 108.75Z"

    /// 2. Inner wave arcs path (`fill="white"`, `fill-rule="evenodd"`)
    public static let innerWavePathD = "M59.175 101.1C57.5949 99.5179 56.7074 97.3734 56.7074 95.1375C56.7074 92.9015 57.5949 90.757 59.175 89.175C67.3504 80.9998 78.4384 76.4071 90 76.4071C101.562 76.4071 112.65 80.9998 120.825 89.175C121.654 89.9474 122.319 90.8789 122.78 91.9139C123.241 92.9489 123.489 94.0662 123.509 95.1991C123.529 96.332 123.321 97.4573 122.896 98.508C122.472 99.5586 121.84 100.513 121.039 101.314C120.238 102.115 119.284 102.747 118.233 103.171C117.182 103.596 116.057 103.804 114.924 103.784C113.791 103.764 112.674 103.516 111.639 103.055C110.604 102.594 109.672 101.929 108.9 101.1C106.419 98.6168 103.472 96.647 100.229 95.303C96.9864 93.959 93.5104 93.2673 90 93.2673C86.4896 93.2673 83.0135 93.959 79.7706 95.303C76.5276 96.647 73.5813 98.6168 71.1 101.1C69.5179 102.68 67.3734 103.568 65.1375 103.568C62.9015 103.568 60.757 102.68 59.175 101.1ZM59.175 138.9C60.757 137.32 62.9015 136.432 65.1375 136.432C67.3734 136.432 69.5179 137.32 71.1 138.9C73.5813 141.383 76.5276 143.353 79.7706 144.697C83.0135 146.041 86.4896 146.733 90 146.733C93.5104 146.733 96.9864 146.041 100.229 144.697C103.472 143.353 106.419 141.383 108.9 138.9C109.672 138.071 110.604 137.406 111.639 136.945C112.674 136.484 113.791 136.236 114.924 136.216C116.057 136.196 117.182 136.404 118.233 136.829C119.284 137.253 120.238 137.885 121.039 138.686C121.84 139.487 122.472 140.441 122.896 141.492C123.321 142.543 123.529 143.668 123.509 144.801C123.489 145.934 123.241 147.051 122.78 148.086C122.319 149.121 121.654 150.053 120.825 150.825C112.65 159 101.562 163.593 90 163.593C78.4384 163.593 67.3504 159 59.175 150.825C57.5949 149.243 56.7074 147.098 56.7074 144.862C56.7074 142.627 57.5949 140.482 59.175 138.9Z"

    /// 3. Outer wave arcs path (`fill="white"`, `fill-rule="evenodd"`)
    public static let outerWavePathD = "M34.3125 76.2375C32.7324 74.6554 31.8449 72.5109 31.8449 70.275C31.8449 68.039 32.7324 65.8945 34.3125 64.3125C41.6252 56.999 50.3069 51.1976 59.8618 47.2396C69.4167 43.2815 79.6577 41.2443 90 41.2443C100.342 41.2443 110.583 43.2815 120.138 47.2396C129.693 51.1976 138.375 56.999 145.687 64.3125C146.516 65.0849 147.181 66.0164 147.643 67.0514C148.104 68.0864 148.352 69.2037 148.372 70.3366C148.392 71.4695 148.183 72.5948 147.759 73.6455C147.335 74.6961 146.703 75.6505 145.902 76.4517C145.1 77.2529 144.146 77.8845 143.095 78.3089C142.045 78.7332 140.92 78.9416 139.787 78.9216C138.654 78.9017 137.536 78.6537 136.501 78.1925C135.466 77.7314 134.535 77.0665 133.762 76.2375C128.016 70.4888 121.194 65.9285 113.685 62.8172C106.176 59.7059 98.128 58.1045 90 58.1045C81.872 58.1045 73.8237 59.7059 66.3147 62.8172C58.8058 65.9285 51.9835 70.4888 46.2375 76.2375C44.6555 77.8176 42.5109 78.7051 40.275 78.7051C38.039 78.7051 35.8945 77.8176 34.3125 76.2375ZM34.3125 163.762C35.8945 162.182 38.039 161.295 40.275 161.295C42.5109 161.295 44.6555 162.182 46.2375 163.762C51.9835 169.511 58.8058 174.071 66.3147 177.183C73.8237 180.294 81.872 181.896 90 181.896C98.128 181.896 106.176 180.294 113.685 177.183C121.194 174.071 128.016 169.511 133.762 163.762C134.535 162.934 135.466 162.269 136.501 161.807C137.536 161.346 138.654 161.098 139.787 161.078C140.92 161.058 142.045 161.267 143.095 161.691C144.146 162.115 145.1 162.747 145.902 163.548C146.703 164.35 147.335 165.304 147.759 166.355C148.183 167.405 148.392 168.53 148.372 169.663C148.352 170.796 148.104 171.914 147.643 172.949C147.181 173.984 146.516 174.915 145.687 175.687C138.375 183.001 129.693 188.802 120.138 192.76C110.583 196.718 100.342 198.756 90 198.756C79.6577 198.756 69.4167 196.718 59.8618 192.76C50.3069 188.802 41.6252 183.001 34.3125 175.687C32.7324 174.105 31.8449 171.961 31.8449 169.725C31.8449 167.489 32.7324 165.345 34.3125 163.762Z"

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

        let whiteColor = CGColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)

        // Outer macOS icon drop shadow
        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: -10.0 * scale),
            blur: 24.0 * scale,
            color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.28)
        )
        ctx.addPath(squirclePath)
        ctx.setFillColor(whiteColor)
        ctx.fillPath()
        ctx.restoreGState()

        // Clip to squircle and map 240x240 `icon.svg` viewBox into 824x824 squircle
        ctx.saveGState()
        ctx.addPath(squirclePath)
        ctx.clip()

        ctx.translateBy(x: iconRect.minX, y: iconRect.minY)
        let svgScale: CGFloat = 824.0 / 240.0
        ctx.scaleBy(x: svgScale, y: svgScale)

        drawSVGElements(in: ctx)

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

        // <rect width="240" height="240" fill="white"/>
        ctx.setFillColor(whiteColor)
        ctx.fill(CGRect(x: 0, y: 0, width: 240, height: 240))

        // <rect x="180" y="180" width="60" height="60" fill="white"/>
        ctx.setFillColor(whiteColor)
        ctx.fill(CGRect(x: 179.5, y: 180, width: 60.5, height: 60))

        // <rect x="180" y="120" width="60" height="60" fill="#FFA8A8"/>
        ctx.setFillColor(lightPinkColor)
        ctx.fill(CGRect(x: 179.5, y: 120, width: 60.5, height: 60))

        // <rect x="180" y="60" width="60" height="60" fill="#FF5252"/>
        ctx.setFillColor(coralRedColor)
        ctx.fill(CGRect(x: 179.5, y: 60, width: 60.5, height: 60.5))

        // <rect x="180" width="60" height="60" fill="#FA0000"/>
        ctx.setFillColor(deepRedColor)
        ctx.fill(CGRect(x: 179.5, y: 0, width: 60.5, height: 60.5))

        // <rect width="180" height="240" fill="black"/>
        ctx.setFillColor(blackColor)
        ctx.fill(CGRect(x: 0, y: 0, width: 180, height: 240))

        // <path ... fill="white"/> (center dot)
        ctx.addPath(parseSVGPath(centerDotPathD))
        ctx.setFillColor(whiteColor)
        ctx.fillPath()

        // <path ... fill-rule="evenodd" clip-rule="evenodd" fill="white"/> (inner wave)
        ctx.addPath(parseSVGPath(innerWavePathD))
        ctx.setFillColor(whiteColor)
        ctx.fillPath(using: .evenOdd)

        // <path ... fill-rule="evenodd" clip-rule="evenodd" fill="white"/> (outer wave)
        ctx.addPath(parseSVGPath(outerWavePathD))
        ctx.setFillColor(whiteColor)
        ctx.fillPath(using: .evenOdd)
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

