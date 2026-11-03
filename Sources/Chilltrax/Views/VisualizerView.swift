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
        ChilltraxTheme.visualizerBackground(for: colorScheme)
    }

    private var contrastColor: Color {
        ChilltraxTheme.visualizerContrastColor(for: colorScheme)
    }

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            Canvas { context, size in
                switch mode {
                case .spectrum:
                    drawSpectrum(context: &context, size: size)
                case .waveform:
                    drawWaveform(context: &context, size: size)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let onToggleMode {
                Button(action: onToggleMode) {
                    HStack(spacing: 4) {
                        Image(systemName: mode.systemImage)
                            .font(.system(size: 10, weight: .semibold))
                        Text(mode.title)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(contrastColor.opacity(0.75))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(contrastColor.opacity(0.07), in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(6)
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
            return ChilltraxTheme.accentRed
        } else if height >= 0.26 {
            return ChilltraxTheme.visualizerContrastColor(for: colorScheme)
        } else {
            return ChilltraxTheme.visualizerGray
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
            return ChilltraxTheme.accentRed
        } else if barHeight >= 0.26 || trailHeight >= 0.22 {
            return ChilltraxTheme.visualizerContrastColor(for: colorScheme)
        } else {
            return ChilltraxTheme.visualizerGray
        }
    }

    /// Computes normalized `(-1.0...1.0)` vertical wave offsets for the primary red waveform, ensuring punchy peaks reach full amplitude regardless of phase.
    private static func computePrimaryWaveOffsets(
        levels: [CGFloat],
        phase: Double,
        steps: Int,
        averageLevel: CGFloat,
        peakLevel: CGFloat
    ) -> [Double] {
        var rawOffsets = [Double]()
        rawOffsets.reserveCapacity(steps + 1)
        var maxAbsRaw: Double = 0.001

        for step in 0...steps {
            let progress = CGFloat(step) / CGFloat(steps)
            let binLevel = interpolatedLevel(in: levels, at: progress)
            let isHighIntensity = binLevel > 0.60
            let edgeWindow = 0.25 + 0.75 * pow(sin(Double(progress) * .pi), 0.24)
            let effectiveLevel = min(1.0, binLevel * 0.75 + peakLevel * 0.17 + averageLevel * 0.08)
            let carrier = sin(Double(progress) * .pi * 7.5 + phase * 2.1)
            let sub = sin(Double(progress) * .pi * 3.0 - phase * 1.15)
            let overtone = sin(Double(progress) * .pi * 15.0 + phase * 3.4) * (isHighIntensity ? 0.22 : 0.08)
            let rawWave = carrier * 0.66 + sub * 0.30 + overtone
            let offset = rawWave * Double(effectiveLevel) * edgeWindow
            rawOffsets.append(offset)
            maxAbsRaw = max(maxAbsRaw, abs(offset))
        }

        // Scale the peak crest to reach `targetPeak` (1.0 on punchy sounds) without flat-clipping
        let punchBoost = peakLevel > 0.72 ? (peakLevel - 0.72) / 0.28 : 0.0
        let targetPeak = Double(min(1.0, peakLevel * (0.90 + punchBoost * 0.12)))
        let scale = targetPeak / maxAbsRaw
        return rawOffsets.map { max(-1.0, min(1.0, $0 * scale)) }
    }

    public static func waveformPeakVerticalSpan(levels: [CGFloat], phase: Double, size: CGSize) -> CGFloat {
        let midY = size.height / 2.0
        let usableAmplitude = max(4, (size.height - verticalInset * 2) / 2.0)
        let steps = max(96, Int(size.width / 2.5))
        let clampedLevels = levels.isEmpty ? [CGFloat(0.07)] : levels.map { max(0.07, min(1.0, $0)) }
        let averageLevel = clampedLevels.reduce(0, +) / CGFloat(clampedLevels.count)
        let peakLevel = clampedLevels.max() ?? 0.07

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

        let clampedLevels = levels.isEmpty ? [CGFloat(0.07)] : levels.map { max(0.07, min(1.0, $0)) }
        let averageLevel = clampedLevels.reduce(0, +) / CGFloat(clampedLevels.count)
        let fadeOpacity = isPlaying
            ? min(0.16, 0.08 + Double(averageLevel) * 0.08)
            : 0.04

        for (index, rawLevel) in levels.enumerated() {
            let clamped = max(0.07, min(1.0, rawLevel))
            let shaped = CGFloat(pow(Double(clamped), 1.15))
            // Reserve subtle top headroom for the trailing fade cap so even 1.0 maximum-height red bars show a visible trail above them
            let maxBarSpan = max(8, usableHeight - (isPlaying ? 4.5 : 0.0))
            let barHeight = max(4, maxBarSpan * shaped)
            let x = horizontalPadding + CGFloat(index) * (barWidth + spacing)
            let y = size.height - verticalPadding - barHeight

            // Color determined by bar height: #808080 gray (low) -> black/contrast (mid) -> red (high/maximum)
            let baseColor = Self.spectrumBarColor(forNormalizedHeight: shaped, colorScheme: colorScheme)

            // Equalized trailing fade across low (gray), mid (black), and high (red) bars
            let explicitTrailRaw = (trailLevels != nil && index < (trailLevels?.count ?? 0))
                ? max(clamped, min(1.0, trailLevels![index]))
                : clamped
            let phaseLagWave = CGFloat(max(0.0, sin(phase * 2.1 - Double(index) * 0.42)) * 0.10 + 0.08)
            let phaseLagBoost = isPlaying
                ? phaseLagWave * (0.35 + clamped * 0.65)
                : CGFloat(0.04) * clamped
            let trailRaw = min(1.0, max(explicitTrailRaw, clamped + phaseLagBoost))
            let trailShaped = CGFloat(pow(Double(trailRaw), 1.05))
            let minTrailLead: CGFloat = isPlaying ? 5.0 : 1.0
            let maxTrailSpan = size.height - verticalPadding - 0.5
            let trailHeight = max(barHeight + minTrailLead, maxTrailSpan * trailShaped)
            let clampedTrailHeight = min(maxTrailSpan, trailHeight)
            let trailY = size.height - verticalPadding - clampedTrailHeight
            let trailRect = CGRect(x: x, y: trailY, width: barWidth, height: clampedTrailHeight)
            let trailPath = Path(roundedRect: trailRect, cornerRadius: barWidth / 2)
            let trailColor = Self.spectrumTrailColor(
                forBarHeight: shaped,
                trailHeight: trailShaped,
                colorScheme: colorScheme
            )
            context.fill(trailPath, with: .color(trailColor.opacity(fadeOpacity)))

            let rect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
            let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)

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
        let tertiaryWaveColor = ChilltraxTheme.visualizerGray

        let clampedLevels = levels.isEmpty ? [CGFloat(0.07)] : levels.map { max(0.07, min(1.0, $0)) }
        let averageLevel = clampedLevels.reduce(0, +) / CGFloat(clampedLevels.count)
        let peakLevel = clampedLevels.max() ?? 0.07

        let baseFadeOpacity = isPlaying
            ? min(0.18, 0.06 + Double(averageLevel) * 0.10 + Double(max(0, peakLevel - 0.70)) * 0.06)
            : 0.04
        let punchBoost = peakLevel > 0.72 ? (peakLevel - 0.72) / 0.28 : 0.0

        // 1. Tertiary harmonic wave in exact #808080 color + subtle movement fade
        var tertiaryRawOffsets = [Double]()
        tertiaryRawOffsets.reserveCapacity(steps + 1)
        var tertiaryMaxAbs: Double = 0.001
        for step in 0...steps {
            let progress = CGFloat(step) / CGFloat(steps)
            let mirroredLevel = Self.interpolatedLevel(in: levels, at: 1.0 - progress)
            let binLevel = Self.interpolatedLevel(in: levels, at: progress)
            let edgeWindow = 0.25 + 0.75 * pow(sin(Double(progress) * .pi), 0.24)
            let wave = sin(Double(progress) * .pi * 4.5 + phase * 1.15) * 0.68
                - sin(Double(progress) * .pi * 9.5 - phase * 1.85) * 0.32
            let blendedLevel = (binLevel * 0.50 + mirroredLevel * 0.28 + peakLevel * 0.14 + averageLevel * 0.08)
            let offset = wave * Double(blendedLevel) * edgeWindow
            tertiaryRawOffsets.append(offset)
            tertiaryMaxAbs = max(tertiaryMaxAbs, abs(offset))
        }
        let tertiaryTargetPeak = Double(min(0.96, peakLevel * (0.78 + punchBoost * 0.18)))
        let tertiaryScale = tertiaryTargetPeak / tertiaryMaxAbs

        var tertiaryWavePath = Path()
        var tertiaryFillPath = Path()
        tertiaryFillPath.move(to: CGPoint(x: 0, y: midY))
        for step in 0...steps {
            let progress = CGFloat(step) / CGFloat(steps)
            let x = progress * size.width
            let normalized = max(-1.0, min(1.0, tertiaryRawOffsets[step] * tertiaryScale))
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
        var contrastRawOffsets = [Double]()
        contrastRawOffsets.reserveCapacity(steps + 1)
        var contrastMaxAbs: Double = 0.001
        for step in 0...steps {
            let progress = CGFloat(step) / CGFloat(steps)
            let binLevel = Self.interpolatedLevel(in: levels, at: progress)
            let isHighIntensity = binLevel > 0.60
            let edgeWindow = 0.25 + 0.75 * pow(sin(Double(progress) * .pi), 0.24)
            let harmonicBoost = isHighIntensity ? (Double(binLevel - 0.60) * 0.65) : 0.0
            let wave = sin(Double(progress) * .pi * 6.0 - phase * 1.45) * 0.72
                + cos(Double(progress) * .pi * 12.0 + phase * 2.15) * (0.28 + harmonicBoost * 0.25)
            let effectiveLevel = min(1.0, binLevel * 0.76 + peakLevel * 0.16 + averageLevel * 0.08)
            let offset = wave * Double(effectiveLevel) * edgeWindow
            contrastRawOffsets.append(offset)
            contrastMaxAbs = max(contrastMaxAbs, abs(offset))
        }
        let contrastTargetPeak = Double(min(1.0, peakLevel * (0.86 + punchBoost * 0.14)))
        let contrastScale = contrastTargetPeak / contrastMaxAbs

        var contrastWavePath = Path()
        var contrastFillPath = Path()
        contrastFillPath.move(to: CGPoint(x: 0, y: midY))
        for step in 0...steps {
            let progress = CGFloat(step) / CGFloat(steps)
            let x = progress * size.width
            let normalized = max(-1.0, min(1.0, contrastRawOffsets[step] * contrastScale))
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
        let primaryOffsets = Self.computePrimaryWaveOffsets(
            levels: levels,
            phase: phase,
            steps: steps,
            averageLevel: averageLevel,
            peakLevel: peakLevel
        )

        var redWavePath = Path()
        var fillPath = Path()
        fillPath.move(to: CGPoint(x: 0, y: midY))

        for step in 0...steps {
            let progress = CGFloat(step) / CGFloat(steps)
            let x = progress * size.width
            let y = midY + CGFloat(primaryOffsets[step] * Double(usableAmplitude))

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
            with: .color(ChilltraxTheme.accentRed.opacity(baseFadeOpacity))
        )

        context.stroke(
            redWavePath,
            with: .color(ChilltraxTheme.accentRed.opacity(isPlaying ? 1.0 : 0.65)),
            style: StrokeStyle(lineWidth: redLineWidth, lineCap: .round, lineJoin: .round)
        )
    }
}
