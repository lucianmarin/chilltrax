import SwiftUI

public struct VisualizerView: View {
    @Environment(\.colorScheme) private var colorScheme

    public let mode: VisualizerMode
    public let levels: [CGFloat]
    public let trailLevels: [CGFloat]?
    public let phase: Double
    public let isPlaying: Bool
    public var onToggleMode: (() -> Void)?

    public init(
        mode: VisualizerMode,
        levels: [CGFloat],
        trailLevels: [CGFloat]? = nil,
        phase: Double,
        isPlaying: Bool,
        onToggleMode: (() -> Void)? = nil
    ) {
        self.mode = mode
        self.levels = levels
        self.trailLevels = trailLevels
        self.phase = phase
        self.isPlaying = isPlaying
        self.onToggleMode = onToggleMode
    }

    private var backgroundColor: Color {
        MactraxTheme.visualizerBackground(for: colorScheme)
    }

    private var contrastColor: Color {
        MactraxTheme.visualizerContrastColor(for: colorScheme)
    }

    private var labelBackgroundColor: Color {
        MactraxTheme.visualizerLabelBackground(for: colorScheme)
    }

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            Canvas { context, size in
                switch mode {
                case .spectrum:
                    drawSpectrum(context: &context, size: size)
                case .waveform:
                    drawWaveform(context: &context, size: size)
                case .off:
                    break
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)

            if let onToggleMode {
                Button(action: onToggleMode) {
                    HStack(spacing: 4) {
                        Image(systemName: mode.systemImage)
                            .font(.system(size: 10, weight: .semibold))
                        Text(mode.title)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(contrastColor.opacity(0.78))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(labelBackgroundColor, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(6)
                .zIndex(1)
                .help("Switch visualizer between Waveform and Spectrum")
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(backgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(contrastColor.opacity(0.14), lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    public static let verticalInset: CGFloat = 4

    /// Precomputed spatial lookup table for waveform rendering and interpolation across `0...steps`.
    private struct WaveformLookupTable: Sendable {
        let steps: Int
        let levelsCount: Int
        let progress: [CGFloat]
        let edgeWindow: [Double]
        let lowerIndex: [Int]
        let upperIndex: [Int]
        let cosineBlend: [CGFloat]
        let sin30: [Double]
        let cos30: [Double]
        let sin45: [Double]
        let cos45: [Double]
        let sin60: [Double]
        let cos60: [Double]
        let sin75: [Double]
        let cos75: [Double]
        let sin95: [Double]
        let cos95: [Double]
        let sin120: [Double]
        let cos120: [Double]
        let sin150: [Double]
        let cos150: [Double]

        init(steps: Int, levelsCount: Int) {
            self.steps = steps
            self.levelsCount = levelsCount
            let count = steps + 1
            var progress = [CGFloat](repeating: 0, count: count)
            var edgeWindow = [Double](repeating: 0, count: count)
            var lowerIndex = [Int](repeating: 0, count: count)
            var upperIndex = [Int](repeating: 0, count: count)
            var cosineBlend = [CGFloat](repeating: 0, count: count)
            var sin30 = [Double](repeating: 0, count: count)
            var cos30 = [Double](repeating: 0, count: count)
            var sin45 = [Double](repeating: 0, count: count)
            var cos45 = [Double](repeating: 0, count: count)
            var sin60 = [Double](repeating: 0, count: count)
            var cos60 = [Double](repeating: 0, count: count)
            var sin75 = [Double](repeating: 0, count: count)
            var cos75 = [Double](repeating: 0, count: count)
            var sin95 = [Double](repeating: 0, count: count)
            var cos95 = [Double](repeating: 0, count: count)
            var sin120 = [Double](repeating: 0, count: count)
            var cos120 = [Double](repeating: 0, count: count)
            var sin150 = [Double](repeating: 0, count: count)
            var cos150 = [Double](repeating: 0, count: count)

            let maxLevelIdx = max(0, levelsCount - 1)
            for step in 0...steps {
                let p = CGFloat(step) / CGFloat(steps)
                let pd = Double(p)
                progress[step] = p
                edgeWindow[step] = 0.25 + 0.75 * pow(max(0.0, sin(pd * .pi)), 0.24)

                if levelsCount > 1 {
                    let scaled = p * CGFloat(maxLevelIdx)
                    let low = max(0, min(maxLevelIdx, Int(floor(scaled))))
                    let high = max(0, min(maxLevelIdx, low + 1))
                    let frac = scaled - CGFloat(low)
                    lowerIndex[step] = low
                    upperIndex[step] = high
                    cosineBlend[step] = CGFloat((1.0 - cos(Double(frac) * .pi)) * 0.5)
                }

                let piP = pd * .pi
                sin30[step] = sin(piP * 3.0)
                cos30[step] = cos(piP * 3.0)
                sin45[step] = sin(piP * 4.5)
                cos45[step] = cos(piP * 4.5)
                sin60[step] = sin(piP * 6.0)
                cos60[step] = cos(piP * 6.0)
                sin75[step] = sin(piP * 7.5)
                cos75[step] = cos(piP * 7.5)
                sin95[step] = sin(piP * 9.5)
                cos95[step] = cos(piP * 9.5)
                sin120[step] = sin(piP * 12.0)
                cos120[step] = cos(piP * 12.0)
                sin150[step] = sin(piP * 15.0)
                cos150[step] = cos(piP * 15.0)
            }

            self.progress = progress
            self.edgeWindow = edgeWindow
            self.lowerIndex = lowerIndex
            self.upperIndex = upperIndex
            self.cosineBlend = cosineBlend
            self.sin30 = sin30
            self.cos30 = cos30
            self.sin45 = sin45
            self.cos45 = cos45
            self.sin60 = sin60
            self.cos60 = cos60
            self.sin75 = sin75
            self.cos75 = cos75
            self.sin95 = sin95
            self.cos95 = cos95
            self.sin120 = sin120
            self.cos120 = cos120
            self.sin150 = sin150
            self.cos150 = cos150
        }

        @inline(__always)
        func interpolate(in levels: [CGFloat], atStep step: Int) -> CGFloat {
            guard !levels.isEmpty else { return 0.07 }
            if levels.count == 1 {
                return max(0.07, min(1.0, levels[0]))
            }
            let blend = cosineBlend[step]
            let interpolated = levels[lowerIndex[step]] * (1.0 - blend) + levels[upperIndex[step]] * blend
            return max(0.07, min(1.0, interpolated))
        }
    }

    private struct SpectrumLookupTable: Sendable {
        let count: Int
        let sin042: [Double]
        let cos042: [Double]

        init(count: Int) {
            self.count = count
            var sin042 = [Double](repeating: 0, count: count)
            var cos042 = [Double](repeating: 0, count: count)
            for i in 0..<count {
                let angle = Double(i) * 0.42
                sin042[i] = sin(angle)
                cos042[i] = cos(angle)
            }
            self.sin042 = sin042
            self.cos042 = cos042
        }
    }

    nonisolated private static let defaultSpectrumTable = SpectrumLookupTable(count: RadioPlayer.visualizerBarCount)
    nonisolated private static let defaultCompactWaveformTable = WaveformLookupTable(
        steps: 179,
        levelsCount: RadioPlayer.visualizerBarCount
    )
    nonisolated(unsafe) private static var cachedWaveformTable = WaveformLookupTable(
        steps: 180,
        levelsCount: RadioPlayer.visualizerBarCount
    )
    private static let tableLock = NSLock()

    private static func waveformTable(steps: Int, levelsCount: Int) -> WaveformLookupTable {
        if steps == defaultCompactWaveformTable.steps && levelsCount == defaultCompactWaveformTable.levelsCount {
            return defaultCompactWaveformTable
        }
        tableLock.lock()
        defer { tableLock.unlock() }
        if cachedWaveformTable.steps == steps && cachedWaveformTable.levelsCount == levelsCount {
            return cachedWaveformTable
        }
        let table = WaveformLookupTable(steps: steps, levelsCount: levelsCount)
        cachedWaveformTable = table
        return table
    }

    @inline(__always)
    private static func computeAverageAndPeak(in levels: [CGFloat]) -> (average: CGFloat, peak: CGFloat) {
        guard !levels.isEmpty else { return (0.07, 0.07) }
        var sum: CGFloat = 0
        var peak: CGFloat = 0.07
        for raw in levels {
            let clamped = max(0.07, min(1.0, raw))
            sum += clamped
            if clamped > peak {
                peak = clamped
            }
        }
        return (sum / CGFloat(levels.count), peak)
    }

    public static func interpolatedLevel(in levels: [CGFloat], at progress: CGFloat) -> CGFloat {
        guard !levels.isEmpty else { return 0.07 }
        if levels.count == 1 {
            return max(0.07, min(1.0, levels[0]))
        }
        let clampedProgress = max(0.0, min(1.0, progress))
        let scaled = clampedProgress * CGFloat(levels.count - 1)
        let lowerIndex = max(0, min(levels.count - 1, Int(floor(scaled))))
        let upperIndex = max(0, min(levels.count - 1, lowerIndex + 1))
        let fraction = scaled - CGFloat(lowerIndex)
        let cosineBlend = CGFloat((1.0 - cos(Double(fraction) * .pi)) * 0.5)
        let interpolated = levels[lowerIndex] * (1.0 - cosineBlend) + levels[upperIndex] * cosineBlend
        return max(0.07, min(1.0, interpolated))
    }

    public static func spectrumAverageHeight(levels: [CGFloat], size: CGSize) -> CGFloat {
        let usableHeight = max(8, size.height - verticalInset * 2)
        guard !levels.isEmpty else { return 4 }
        let total = levels.reduce(CGFloat(0)) { partial, rawLevel in
            let clamped = max(0.07, min(1.0, rawLevel))
            let shaped = CGFloat(pow(Double(clamped), 1.15))
            return partial + max(4, usableHeight * shaped)
        }
        return total / CGFloat(levels.count)
    }

    public static func barsAverageHeight(levels: [CGFloat], size: CGSize) -> CGFloat {
        spectrumAverageHeight(levels: levels, size: size)
    }

    /// Returns the spectrum bar color based on normalized bar height (`0.0...1.0`):
    /// low height -> `#808080` gray, mid height -> black/contrast, high/maximum height -> accent red.
    public static func spectrumBarColor(forNormalizedHeight height: CGFloat, colorScheme: ColorScheme = .light) -> Color {
        if height >= 0.62 {
            return MactraxTheme.accentRed
        } else if height >= 0.26 {
            return MactraxTheme.visualizerContrastColor(for: colorScheme)
        } else {
            return MactraxTheme.visualizerGray
        }
    }

    /// Returns the trailing fade color for a spectrum bar based on both the current bar height and the trail's peak height,
    /// ensuring trails left behind by high red bars stay red and trails from mid black bars stay black/contrast as bars drop.
    public static func spectrumTrailColor(
        forBarHeight barHeight: CGFloat,
        trailHeight: CGFloat,
        colorScheme: ColorScheme = .light
    ) -> Color {
        if barHeight >= 0.62 || trailHeight >= 0.56 {
            return MactraxTheme.accentRed
        } else if barHeight >= 0.26 || trailHeight >= 0.22 {
            return MactraxTheme.visualizerContrastColor(for: colorScheme)
        } else {
            return MactraxTheme.visualizerGray
        }
    }

    /// Computes normalized `(-1.0...1.0)` vertical wave offsets for the primary red waveform, ensuring punchy peaks reach full amplitude regardless of phase.
    private static func computePrimaryWaveOffsets(
        levels: [CGFloat],
        phase: Double,
        steps: Int,
        averageLevel: CGFloat,
        peakLevel: CGFloat,
        table: WaveformLookupTable? = nil
    ) -> [Double] {
        let lookup = table ?? waveformTable(steps: steps, levelsCount: levels.count)
        var rawOffsets = [Double](repeating: 0, count: steps + 1)
        var maxAbsRaw: Double = 0.001

        let sinP21 = sin(phase * 2.1)
        let cosP21 = cos(phase * 2.1)
        let sinP115 = sin(phase * 1.15)
        let cosP115 = cos(phase * 1.15)
        let sinP34 = sin(phase * 3.4)
        let cosP34 = cos(phase * 3.4)

        for step in 0...steps {
            let binLevel = lookup.interpolate(in: levels, atStep: step)
            let isHighIntensity = binLevel > 0.60
            let edgeWindow = lookup.edgeWindow[step]
            let effectiveLevel = min(1.0, binLevel * 0.75 + peakLevel * 0.17 + averageLevel * 0.08)
            // sin(p * .pi * 7.5 + phase * 2.1)
            let carrier = lookup.sin75[step] * cosP21 + lookup.cos75[step] * sinP21
            // sin(p * .pi * 3.0 - phase * 1.15)
            let sub = lookup.sin30[step] * cosP115 - lookup.cos30[step] * sinP115
            // sin(p * .pi * 15.0 + phase * 3.4)
            let overtone = (lookup.sin150[step] * cosP34 + lookup.cos150[step] * sinP34) * (isHighIntensity ? 0.22 : 0.08)
            let rawWave = carrier * 0.66 + sub * 0.30 + overtone
            let offset = rawWave * Double(effectiveLevel) * edgeWindow
            rawOffsets[step] = offset
            maxAbsRaw = max(maxAbsRaw, abs(offset))
        }

        // Scale the peak crest to reach `targetPeak` (1.0 on punchy sounds) without flat-clipping
        let punchBoost = peakLevel > 0.72 ? (peakLevel - 0.72) / 0.28 : 0.0
        let targetPeak = Double(min(1.0, peakLevel * (0.90 + punchBoost * 0.12)))
        let scale = targetPeak / maxAbsRaw
        for step in 0...steps {
            rawOffsets[step] = max(-1.0, min(1.0, rawOffsets[step] * scale))
        }
        return rawOffsets
    }

    public static func waveformPeakVerticalSpan(levels: [CGFloat], phase: Double, size: CGSize) -> CGFloat {
        let midY = size.height / 2.0
        let usableAmplitude = max(4, (size.height - verticalInset * 2) / 2.0)
        let steps = max(96, Int(size.width / 2.5))
        let (averageLevel, peakLevel) = computeAverageAndPeak(in: levels)

        let offsets = computePrimaryWaveOffsets(
            levels: levels,
            phase: phase,
            steps: steps,
            averageLevel: averageLevel,
            peakLevel: peakLevel
        )

        var minY = midY
        var maxY = midY
        for offset in offsets {
            let y = midY + CGFloat(offset * Double(usableAmplitude))
            minY = min(minY, y)
            maxY = max(maxY, y)
        }
        return maxY - minY
    }

    private func drawSpectrum(context: inout GraphicsContext, size: CGSize) {
        let count = max(1, levels.count)
        let horizontalPadding: CGFloat = 10
        let verticalPadding = Self.verticalInset
        let usableWidth = max(10, size.width - horizontalPadding * 2)
        let usableHeight = max(8, size.height - verticalPadding * 2)
        // Slimmer spacing and bar width to accommodate 33.3% more bars (56 vs 42)
        let spacing: CGFloat = 2.0
        let totalSpacing = spacing * CGFloat(count - 1)
        let barWidth = max(1.5, (usableWidth - totalSpacing) / CGFloat(count))
        let cornerRadius = barWidth / 2

        let (averageLevel, _) = Self.computeAverageAndPeak(in: levels)
        let fadeOpacity = isPlaying
            ? min(0.16, 0.08 + Double(averageLevel) * 0.08)
            : 0.04

        let maxBarSpan = max(8, usableHeight - (isPlaying ? 4.5 : 0.0))
        let minTrailLead: CGFloat = isPlaying ? 5.0 : 1.0
        let maxTrailSpan = size.height - verticalPadding - 0.5
        let spectrumTable = Self.defaultSpectrumTable
        let useTable = (count == spectrumTable.count)
        let sinP21 = sin(phase * 2.1)
        let cosP21 = cos(phase * 2.1)

        for (index, rawLevel) in levels.enumerated() {
            let clamped = max(0.07, min(1.0, rawLevel))
            let shaped = CGFloat(pow(Double(clamped), 1.15))
            // Reserve subtle top headroom for the trailing fade cap so even 1.0 maximum-height red bars show a visible trail above them
            let barHeight = max(4, maxBarSpan * shaped)
            let x = horizontalPadding + CGFloat(index) * (barWidth + spacing)
            let y = size.height - verticalPadding - barHeight

            // Color determined by bar height: #808080 gray (low) -> black/contrast (mid) -> red (high/maximum)
            let baseColor = Self.spectrumBarColor(forNormalizedHeight: shaped, colorScheme: colorScheme)

            // Equalized trailing fade across low (gray), mid (black), and high (red) bars
            let explicitTrailRaw = (trailLevels != nil && index < (trailLevels?.count ?? 0))
                ? max(clamped, min(1.0, trailLevels![index]))
                : clamped
            let sinPhaseLag: Double
            if useTable {
                // sin(phase * 2.1 - index * 0.42)
                sinPhaseLag = sinP21 * spectrumTable.cos042[index] - cosP21 * spectrumTable.sin042[index]
            } else {
                sinPhaseLag = sin(phase * 2.1 - Double(index) * 0.42)
            }
            let phaseLagWave = CGFloat(max(0.0, sinPhaseLag) * 0.10 + 0.08)
            let phaseLagBoost = isPlaying
                ? phaseLagWave * (0.35 + clamped * 0.65)
                : CGFloat(0.04) * clamped
            let trailRaw = min(1.0, max(explicitTrailRaw, clamped + phaseLagBoost))
            let trailShaped = CGFloat(pow(Double(trailRaw), 1.05))
            let trailHeight = max(barHeight + minTrailLead, maxTrailSpan * trailShaped)
            let clampedTrailHeight = min(maxTrailSpan, trailHeight)
            let trailY = size.height - verticalPadding - clampedTrailHeight
            let trailRect = CGRect(x: x, y: trailY, width: barWidth, height: clampedTrailHeight)
            let trailPath = Path(roundedRect: trailRect, cornerRadius: cornerRadius)
            let trailColor = Self.spectrumTrailColor(
                forBarHeight: shaped,
                trailHeight: trailShaped,
                colorScheme: colorScheme
            )
            context.fill(trailPath, with: .color(trailColor.opacity(fadeOpacity)))

            let rect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
            let path = Path(roundedRect: rect, cornerRadius: cornerRadius)

            let barColor = isPlaying ? baseColor : baseColor.opacity(0.45)

            context.fill(path, with: .color(barColor))
        }
    }

    private func drawWaveform(context: inout GraphicsContext, size: CGSize) {
        let midY = size.height / 2.0
        let verticalPadding = Self.verticalInset
        let usableAmplitude = max(4, (size.height - verticalPadding * 2) / 2.0)
        let steps = max(96, Int(size.width / 2.5))
        let secondaryWaveColor = contrastColor
        let tertiaryWaveColor = MactraxTheme.visualizerGray

        let (averageLevel, peakLevel) = Self.computeAverageAndPeak(in: levels)
        let lookup = Self.waveformTable(steps: steps, levelsCount: levels.count)

        let baseFadeOpacity = isPlaying
            ? min(0.18, 0.06 + Double(averageLevel) * 0.10 + Double(max(0, peakLevel - 0.70)) * 0.06)
            : 0.04
        let punchBoost = peakLevel > 0.72 ? (peakLevel - 0.72) / 0.28 : 0.0

        // Precompute interpolated bin levels once across 0...steps and reuse for all 3 waves
        var binLevels = [CGFloat](repeating: 0.07, count: steps + 1)
        for step in 0...steps {
            binLevels[step] = lookup.interpolate(in: levels, atStep: step)
        }

        // Precompute per-frame temporal sin/cos components once
        let sinP115 = sin(phase * 1.15)
        let cosP115 = cos(phase * 1.15)
        let sinP185 = sin(phase * 1.85)
        let cosP185 = cos(phase * 1.85)
        let sinP145 = sin(phase * 1.45)
        let cosP145 = cos(phase * 1.45)
        let sinP215 = sin(phase * 2.15)
        let cosP215 = cos(phase * 2.15)
        let sinP21 = sin(phase * 2.1)
        let cosP21 = cos(phase * 2.1)
        let sinP34 = sin(phase * 3.4)
        let cosP34 = cos(phase * 3.4)

        var waveOffsets = [Double](repeating: 0, count: steps + 1)

        // 1. Tertiary harmonic wave in exact #808080 color + subtle movement fade
        var tertiaryMaxAbs: Double = 0.001
        for step in 0...steps {
            let binLevel = binLevels[step]
            let mirroredLevel = binLevels[steps - step]
            let edgeWindow = lookup.edgeWindow[step]
            // sin(p * .pi * 4.5 + phase * 1.15) * 0.68 - sin(p * .pi * 9.5 - phase * 1.85) * 0.32
            let w1 = lookup.sin45[step] * cosP115 + lookup.cos45[step] * sinP115
            let w2 = lookup.sin95[step] * cosP185 - lookup.cos95[step] * sinP185
            let wave = w1 * 0.68 - w2 * 0.32
            let blendedLevel = (binLevel * 0.50 + mirroredLevel * 0.28 + peakLevel * 0.14 + averageLevel * 0.08)
            let offset = wave * Double(blendedLevel) * edgeWindow
            waveOffsets[step] = offset
            tertiaryMaxAbs = max(tertiaryMaxAbs, abs(offset))
        }
        let tertiaryTargetPeak = Double(min(0.96, peakLevel * (0.78 + punchBoost * 0.18)))
        let tertiaryScale = tertiaryTargetPeak / tertiaryMaxAbs

        var tertiaryWavePath = Path()
        var tertiaryFillPath = Path()
        tertiaryFillPath.move(to: CGPoint(x: 0, y: midY))
        for step in 0...steps {
            let x = lookup.progress[step] * size.width
            let normalized = max(-1.0, min(1.0, waveOffsets[step] * tertiaryScale))
            let y = midY + CGFloat(normalized * Double(usableAmplitude))
            if step == 0 {
                tertiaryWavePath.move(to: CGPoint(x: x, y: y))
            } else {
                tertiaryWavePath.addLine(to: CGPoint(x: x, y: y))
            }
            tertiaryFillPath.addLine(to: CGPoint(x: x, y: y))
        }
        tertiaryFillPath.addLine(to: CGPoint(x: size.width, y: midY))
        tertiaryFillPath.closeSubpath()

        context.fill(
            tertiaryFillPath,
            with: .color(tertiaryWaveColor.opacity(baseFadeOpacity * 0.85))
        )
        let tertiaryLineWidth = isPlaying ? (1.4 + averageLevel * 0.35) : 1.35
        context.stroke(
            tertiaryWavePath,
            with: .color(isPlaying ? tertiaryWaveColor : tertiaryWaveColor.opacity(0.60)),
            style: StrokeStyle(lineWidth: tertiaryLineWidth, lineCap: .round, lineJoin: .round)
        )

        // 2. Secondary harmonic wave (black in light mode, white in dark mode) + subtle movement fade
        var contrastMaxAbs: Double = 0.001
        for step in 0...steps {
            let binLevel = binLevels[step]
            let isHighIntensity = binLevel > 0.60
            let edgeWindow = lookup.edgeWindow[step]
            let harmonicBoost = isHighIntensity ? (Double(binLevel - 0.60) * 0.65) : 0.0
            // sin(p * .pi * 6.0 - phase * 1.45) * 0.72 + cos(p * .pi * 12.0 + phase * 2.15) * (0.28 + harmonicBoost * 0.25)
            let w1 = lookup.sin60[step] * cosP145 - lookup.cos60[step] * sinP145
            let w2 = lookup.cos120[step] * cosP215 - lookup.sin120[step] * sinP215
            let wave = w1 * 0.72 + w2 * (0.28 + harmonicBoost * 0.25)
            let effectiveLevel = min(1.0, binLevel * 0.76 + peakLevel * 0.16 + averageLevel * 0.08)
            let offset = wave * Double(effectiveLevel) * edgeWindow
            waveOffsets[step] = offset
            contrastMaxAbs = max(contrastMaxAbs, abs(offset))
        }
        let contrastTargetPeak = Double(min(1.0, peakLevel * (0.86 + punchBoost * 0.14)))
        let contrastScale = contrastTargetPeak / contrastMaxAbs

        var contrastWavePath = Path()
        var contrastFillPath = Path()
        contrastFillPath.move(to: CGPoint(x: 0, y: midY))
        for step in 0...steps {
            let x = lookup.progress[step] * size.width
            let normalized = max(-1.0, min(1.0, waveOffsets[step] * contrastScale))
            let y = midY + CGFloat(normalized * Double(usableAmplitude))
            if step == 0 {
                contrastWavePath.move(to: CGPoint(x: x, y: y))
            } else {
                contrastWavePath.addLine(to: CGPoint(x: x, y: y))
            }
            contrastFillPath.addLine(to: CGPoint(x: x, y: y))
        }
        contrastFillPath.addLine(to: CGPoint(x: size.width, y: midY))
        contrastFillPath.closeSubpath()

        context.fill(
            contrastFillPath,
            with: .color(secondaryWaveColor.opacity(baseFadeOpacity * 0.85))
        )
        let contrastOpacity = isPlaying ? min(0.90, 0.55 + Double(averageLevel) * 0.35) : 0.40
        let contrastLineWidth = isPlaying ? (1.55 + averageLevel * 0.45) : 1.5
        context.stroke(
            contrastWavePath,
            with: .color(secondaryWaveColor.opacity(contrastOpacity)),
            style: StrokeStyle(lineWidth: contrastLineWidth, lineCap: .round, lineJoin: .round)
        )

        // 3. Primary red foreground wave + subtle red tint fade
        var primaryMaxAbs: Double = 0.001
        for step in 0...steps {
            let binLevel = binLevels[step]
            let isHighIntensity = binLevel > 0.60
            let edgeWindow = lookup.edgeWindow[step]
            let effectiveLevel = min(1.0, binLevel * 0.75 + peakLevel * 0.17 + averageLevel * 0.08)
            let carrier = lookup.sin75[step] * cosP21 + lookup.cos75[step] * sinP21
            let sub = lookup.sin30[step] * cosP115 - lookup.cos30[step] * sinP115
            let overtone = (lookup.sin150[step] * cosP34 + lookup.cos150[step] * sinP34) * (isHighIntensity ? 0.22 : 0.08)
            let rawWave = carrier * 0.66 + sub * 0.30 + overtone
            let offset = rawWave * Double(effectiveLevel) * edgeWindow
            waveOffsets[step] = offset
            primaryMaxAbs = max(primaryMaxAbs, abs(offset))
        }
        let primaryTargetPeak = Double(min(1.0, peakLevel * (0.90 + punchBoost * 0.12)))
        let primaryScale = primaryTargetPeak / primaryMaxAbs

        var redWavePath = Path()
        var fillPath = Path()
        fillPath.move(to: CGPoint(x: 0, y: midY))

        for step in 0...steps {
            let x = lookup.progress[step] * size.width
            let normalized = max(-1.0, min(1.0, waveOffsets[step] * primaryScale))
            let y = midY + CGFloat(normalized * Double(usableAmplitude))

            if step == 0 {
                redWavePath.move(to: CGPoint(x: x, y: y))
            } else {
                redWavePath.addLine(to: CGPoint(x: x, y: y))
            }
            fillPath.addLine(to: CGPoint(x: x, y: y))
        }

        fillPath.addLine(to: CGPoint(x: size.width, y: midY))
        fillPath.closeSubpath()

        let redLineWidth = isPlaying ? (1.8 + averageLevel * 0.55) : 1.75

        context.fill(
            fillPath,
            with: .color(MactraxTheme.accentRed.opacity(baseFadeOpacity))
        )

        context.stroke(
            redWavePath,
            with: .color(MactraxTheme.accentRed.opacity(isPlaying ? 1.0 : 0.65)),
            style: StrokeStyle(lineWidth: redLineWidth, lineCap: .round, lineJoin: .round)
        )
    }
}
