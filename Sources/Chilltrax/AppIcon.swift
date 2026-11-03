import SwiftUI
import AppKit
import CoreGraphics

public enum AppIcon {
    /// Exact vector path data from `icon.svg` (`viewBox="0 0 240 240"`):
    /// 1. Top "Chill" path (`fill="white"`)
    public static let chillPathD = "M131.532 43.258C131.532 40.6207 132.069 38.3207 133.142 36.358C134.215 34.3647 135.703 32.8313 137.604 31.758C139.505 30.654 141.683 30.102 144.136 30.102C147.295 30.102 149.901 30.8993 151.956 32.494C154.041 34.058 155.437 36.266 156.142 39.118H149.196C148.828 38.014 148.199 37.1553 147.31 36.542C146.451 35.898 145.378 35.576 144.09 35.576C142.25 35.576 140.793 36.2507 139.72 37.6C138.647 38.9187 138.11 40.8047 138.11 43.258C138.11 45.6807 138.647 47.5667 139.72 48.916C140.793 50.2347 142.25 50.894 144.09 50.894C146.697 50.894 148.399 49.7287 149.196 47.398H156.142C155.437 50.158 154.041 52.3507 151.956 53.976C149.871 55.6013 147.264 56.414 144.136 56.414C141.683 56.414 139.505 55.8773 137.604 54.804C135.703 53.7 134.215 52.1667 133.142 50.204C132.069 48.2107 131.532 45.8953 131.532 43.258ZM173.832 30.148C175.764 30.148 177.481 30.5773 178.984 31.436C180.486 32.264 181.652 33.506 182.48 35.162C183.338 36.7873 183.768 38.75 183.768 41.05V56H177.328V41.924C177.328 39.9 176.822 38.3513 175.81 37.278C174.798 36.174 173.418 35.622 171.67 35.622C169.891 35.622 168.48 36.174 167.438 37.278C166.426 38.3513 165.92 39.9 165.92 41.924V56H159.48V21.96H165.92V33.69C166.748 32.586 167.852 31.7273 169.232 31.114C170.612 30.47 172.145 30.148 173.832 30.148ZM191.778 27.48C190.643 27.48 189.693 27.1273 188.926 26.422C188.19 25.686 187.822 24.7813 187.822 23.708C187.822 22.6347 188.19 21.7453 188.926 21.04C189.693 20.304 190.643 19.936 191.778 19.936C192.913 19.936 193.848 20.304 194.584 21.04C195.351 21.7453 195.734 22.6347 195.734 23.708C195.734 24.7813 195.351 25.686 194.584 26.422C193.848 27.1273 192.913 27.48 191.778 27.48ZM194.952 30.516V56H188.512V30.516H194.952ZM206.375 21.96V56H199.935V21.96H206.375ZM217.797 21.96V56H211.357V21.96H217.797Z"

    /// 2. Middle "trax" path (`fill="black"`)
    public static let traxPathD = "M143.017 115.806V128.134C143.017 128.993 143.217 129.621 143.615 130.02C144.045 130.388 144.75 130.572 145.731 130.572H148.721V136H144.673C139.245 136 136.531 133.363 136.531 128.088V115.806H133.495V110.516H136.531V104.214H143.017V110.516H148.721V115.806H143.017ZM158.413 114.472C159.241 113.123 160.315 112.065 161.633 111.298C162.983 110.531 164.516 110.148 166.233 110.148V116.91H164.531C162.507 116.91 160.974 117.385 159.931 118.336C158.919 119.287 158.413 120.943 158.413 123.304V136H151.973V110.516H158.413V114.472ZM167.535 123.166C167.535 120.59 168.041 118.305 169.053 116.312C170.096 114.319 171.491 112.785 173.239 111.712C175.018 110.639 176.996 110.102 179.173 110.102C181.074 110.102 182.73 110.485 184.141 111.252C185.582 112.019 186.732 112.985 187.591 114.15V110.516H194.077V136H187.591V132.274C186.763 133.47 185.613 134.467 184.141 135.264C182.7 136.031 181.028 136.414 179.127 136.414C176.98 136.414 175.018 135.862 173.239 134.758C171.491 133.654 170.096 132.105 169.053 130.112C168.041 128.088 167.535 125.773 167.535 123.166ZM187.591 123.258C187.591 121.694 187.284 120.36 186.671 119.256C186.058 118.121 185.23 117.263 184.187 116.68C183.144 116.067 182.025 115.76 180.829 115.76C179.633 115.76 178.529 116.051 177.517 116.634C176.505 117.217 175.677 118.075 175.033 119.21C174.42 120.314 174.113 121.633 174.113 123.166C174.113 124.699 174.42 126.049 175.033 127.214C175.677 128.349 176.505 129.223 177.517 129.836C178.56 130.449 179.664 130.756 180.829 130.756C182.025 130.756 183.144 130.465 184.187 129.882C185.23 129.269 186.058 128.41 186.671 127.306C187.284 126.171 187.591 124.822 187.591 123.258ZM213.063 136L207.819 128.088L203.173 136H196.273L204.599 123.212L196.181 110.516H203.449L208.647 118.382L213.339 110.516H220.239L211.867 123.212L220.331 136H213.063Z"

    /// 3. Bottom-right "#" path (`fill="white"`)
    public static let hashPathD = "M211.569 195.346L210.051 202.43H215.893V208.18H208.809L207.153 216H201.035L202.691 208.18H194.319L192.663 216H186.591L188.247 208.18H181.301V202.43H189.489L191.007 195.346H184.107V189.596H192.249L193.859 181.96H199.931L198.321 189.596H206.693L208.303 181.96H214.421L212.811 189.596H218.699V195.346H211.569ZM205.451 195.346H197.079L195.561 202.43H203.933L205.451 195.346Z"

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
        let grayColor = CGColor(srgbRed: 0xD9 / 255.0, green: 0xD9 / 255.0, blue: 0xD9 / 255.0, alpha: 1.0)
        let redColor = CGColor(srgbRed: 0xE6 / 255.0, green: 0x0E / 255.0, blue: 0x30 / 255.0, alpha: 1.0)

        // <rect width="240" height="240" fill="white"/>
        ctx.setFillColor(whiteColor)
        ctx.fill(CGRect(x: 0, y: 0, width: 240, height: 240))

        // <rect width="240" height="80" fill="black"/>
        ctx.setFillColor(blackColor)
        ctx.fill(CGRect(x: 0, y: 0, width: 240, height: 80.5))

        // <rect y="80" width="240" height="80" fill="#D9D9D9"/>
        ctx.setFillColor(grayColor)
        ctx.fill(CGRect(x: 0, y: 80, width: 240, height: 80.5))

        // <rect x="160" y="160" width="80" height="80" fill="#E60E30"/>
        ctx.setFillColor(redColor)
        ctx.fill(CGRect(x: 160, y: 160, width: 80, height: 80))

        // <path ... fill="white"/> ("Chill")
        ctx.addPath(parseSVGPath(chillPathD))
        ctx.setFillColor(whiteColor)
        ctx.fillPath()

        // <path ... fill="black"/> ("trax")
        ctx.addPath(parseSVGPath(traxPathD))
        ctx.setFillColor(blackColor)
        ctx.fillPath()

        // <path ... fill="white"/> ("#")
        ctx.addPath(parseSVGPath(hashPathD))
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

