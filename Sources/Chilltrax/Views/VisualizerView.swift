import SwiftUI

public struct VisualizerView: View {
    @Environment(\.colorScheme) private var colorScheme

    public let mode: VisualizerMode
    public let levels: [CGFloat]
    public let phase: Double
    public let isPlaying: Bool
    public var onToggleMode: (() -> Void)?

    public init(
        mode: VisualizerMode,
        levels: [CGFloat],
        phase: Double,
        isPlaying: Bool,
        onToggleMode: (() -> Void)? = nil
    ) {
        self.mode = mode
        self.levels = levels
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
                case .bars:
                    drawBars(context: &context, size: size)
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
                .help("Switch visualizer between Waveform and Bars")
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

    public static func interpolatedLevel(in levels: [CGFloat], at progress: CGFloat) -> CGFloat {
        guard !levels.isEmpty else { return 0.08 }
        if levels.count == 1 {
            return max(0.08, min(1.0, levels[0]))
        }
        let clampedProgress = max(0.0, min(1.0, progress))
        let scaled = clampedProgress * CGFloat(levels.count - 1)
        let lowerIndex = max(0, min(levels.count - 1, Int(floor(scaled))))
        let upperIndex = max(0, min(levels.count - 1, lowerIndex + 1))
        let fraction = scaled - CGFloat(lowerIndex)
        let cosineBlend = CGFloat((1.0 - cos(Double(fraction) * .pi)) * 0.5)
        let interpolated = levels[lowerIndex] * (1.0 - cosineBlend) + levels[upperIndex] * cosineBlend
        return max(0.08, min(1.0, interpolated))
    }

    public static func barsAverageHeight(levels: [CGFloat], size: CGSize) -> CGFloat {
        let verticalPadding: CGFloat = 8
        let usableHeight = max(8, size.height - verticalPadding * 2)
        guard !levels.isEmpty else { return 4 }
        let total = levels.reduce(CGFloat(0)) { partial, rawLevel in
            let clamped = max(0.08, min(1.0, rawLevel))
            return partial + max(4, usableHeight * clamped)
        }
        return total / CGFloat(levels.count)
    }

    public static func waveformPeakVerticalSpan(levels: [CGFloat], phase: Double, size: CGSize) -> CGFloat {
        let midY = size.height / 2.0
        let verticalPadding: CGFloat = 8
        let usableAmplitude = max(4, (size.height - verticalPadding * 2) / 2.0)
        let steps = max(96, Int(size.width / 2.5))
        let averageLevel: CGFloat = {
            guard !levels.isEmpty else { return 0.08 }
            let sum = levels.reduce(0) { $0 + max(0.08, min(1.0, $1)) }
            return sum / CGFloat(levels.count)
        }()

        var minY = midY
        var maxY = midY
        for step in 0...steps {
            let progress = CGFloat(step) / CGFloat(steps)
            let binLevel = interpolatedLevel(in: levels, at: progress)
            let isHighIntensity = binLevel > 0.65
            let edgeWindow = pow(sin(Double(progress) * .pi), 0.55)
            let effectiveLevel = min(1.0, binLevel * 0.85 + averageLevel * 0.15)
            let carrier = sin(Double(progress) * .pi * 8.0 + phase * 2.1)
            let sub = sin(Double(progress) * .pi * 3.0 - phase * 1.1)
            let overtone = sin(Double(progress) * .pi * 16.0 + phase * 3.4) * (isHighIntensity ? 0.25 : 0.08)
            let rawWave = carrier * 0.68 + sub * 0.32 + overtone
            let normalizedWave = max(-1.0, min(1.0, rawWave * 1.12))
            let y = midY + CGFloat(normalizedWave * Double(usableAmplitude * effectiveLevel) * edgeWindow)
            minY = min(minY, y)
            maxY = max(maxY, y)
        }
        return maxY - minY
    }

    private func drawBars(context: inout GraphicsContext, size: CGSize) {
        let count = max(1, levels.count)
        let horizontalPadding: CGFloat = 10
        let verticalPadding: CGFloat = 8
        let usableWidth = max(10, size.width - horizontalPadding * 2)
        let usableHeight = max(8, size.height - verticalPadding * 2)
        let spacing: CGFloat = 2.75
        let totalSpacing = spacing * CGFloat(count - 1)
        let barWidth = max(2.0, (usableWidth - totalSpacing) / CGFloat(count))
        let secondaryBarColor = contrastColor

        for (index, rawLevel) in levels.enumerated() {
            let clamped = max(0.08, min(1.0, rawLevel))
            let barHeight = max(4, usableHeight * clamped)
            let x = horizontalPadding + CGFloat(index) * (barWidth + spacing)
            let y = size.height - verticalPadding - barHeight

            let rect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
            let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)

            let isAccentBar = (index % 2 == 0) || (clamped > 0.65)
            let barColor: Color
            if isPlaying {
                barColor = isAccentBar ? ChilltraxTheme.accentRed : secondaryBarColor
            } else {
                barColor = (index % 2 == 0)
                    ? ChilltraxTheme.accentRed.opacity(0.55)
                    : secondaryBarColor.opacity(0.35)
            }

            context.fill(path, with: .color(barColor))
        }
    }

    private func drawWaveform(context: inout GraphicsContext, size: CGSize) {
        let midY = size.height / 2.0
        let verticalPadding: CGFloat = 8
        let usableAmplitude = max(4, (size.height - verticalPadding * 2) / 2.0)
        let steps = max(96, Int(size.width / 2.5))
        let secondaryWaveColor = contrastColor

        let clampedLevels = levels.isEmpty ? [CGFloat(0.08)] : levels.map { max(0.08, min(1.0, $0)) }
        let averageLevel = clampedLevels.reduce(0, +) / CGFloat(clampedLevels.count)
        let peakLevel = clampedLevels.max() ?? 0.08

        // Secondary harmonic wave (black in light mode, white in dark mode), synced to bin & overall intensity
        var contrastWavePath = Path()
        for step in 0...steps {
            let progress = CGFloat(step) / CGFloat(steps)
            let x = progress * size.width
            let binLevel = Self.interpolatedLevel(in: levels, at: progress)
            let isHighIntensity = binLevel > 0.65
            let edgeWindow = pow(sin(Double(progress) * .pi), 0.55)
            let harmonicBoost = isHighIntensity ? (Double(binLevel - 0.65) * 0.85) : 0.0
            let wave = sin(Double(progress) * .pi * 6.0 - phase * 1.4) * 0.72
                + cos(Double(progress) * .pi * 13.0 + phase * 2.2) * (0.28 + harmonicBoost * 0.35)
            let normalizedWave = max(-1.0, min(1.0, wave))
            let amplitude = Double(usableAmplitude) * Double(binLevel) * 0.88 * edgeWindow
            let y = midY + CGFloat(normalizedWave * amplitude)
            if step == 0 {
                contrastWavePath.move(to: CGPoint(x: x, y: y))
            } else {
                contrastWavePath.addLine(to: CGPoint(x: x, y: y))
            }
        }

        let contrastOpacity = isPlaying ? min(0.95, 0.55 + Double(averageLevel) * 0.45) : 0.40
        let contrastLineWidth = isPlaying ? (1.6 + averageLevel * 1.0) : 1.6
        context.stroke(
            contrastWavePath,
            with: .color(secondaryWaveColor.opacity(contrastOpacity)),
            style: StrokeStyle(lineWidth: contrastLineWidth, lineCap: .round, lineJoin: .round)
        )

        // Primary red foreground wave + intensity-reactive red tint fill
        var redWavePath = Path()
        var fillPath = Path()
        fillPath.move(to: CGPoint(x: 0, y: midY))

        for step in 0...steps {
            let progress = CGFloat(step) / CGFloat(steps)
            let x = progress * size.width
            let binLevel = Self.interpolatedLevel(in: levels, at: progress)
            let isHighIntensity = binLevel > 0.65
            let edgeWindow = pow(sin(Double(progress) * .pi), 0.55)
            let effectiveLevel = min(1.0, binLevel * 0.85 + averageLevel * 0.15)
            let carrier = sin(Double(progress) * .pi * 8.0 + phase * 2.1)
            let sub = sin(Double(progress) * .pi * 3.0 - phase * 1.1)
            let overtone = sin(Double(progress) * .pi * 16.0 + phase * 3.4) * (isHighIntensity ? 0.25 : 0.08)
            let rawWave = carrier * 0.68 + sub * 0.32 + overtone
            let normalizedWave = max(-1.0, min(1.0, rawWave * 1.12))
            let y = midY + CGFloat(normalizedWave * Double(usableAmplitude * effectiveLevel) * edgeWindow)

            if step == 0 {
                redWavePath.move(to: CGPoint(x: x, y: y))
            } else {
                redWavePath.addLine(to: CGPoint(x: x, y: y))
            }
            fillPath.addLine(to: CGPoint(x: x, y: y))
        }

        fillPath.addLine(to: CGPoint(x: size.width, y: midY))
        fillPath.closeSubpath()

        let fillOpacity = isPlaying
            ? min(0.32, 0.07 + Double(averageLevel) * 0.20 + Double(max(0, peakLevel - 0.65)) * 0.18)
            : 0.05
        let redLineWidth = isPlaying ? (1.9 + averageLevel * 1.4) : 1.8

        context.fill(
            fillPath,
            with: .color(ChilltraxTheme.accentRed.opacity(fillOpacity))
        )

        context.stroke(
            redWavePath,
            with: .color(ChilltraxTheme.accentRed.opacity(isPlaying ? 1.0 : 0.65)),
            style: StrokeStyle(lineWidth: redLineWidth, lineCap: .round, lineJoin: .round)
        )
    }
}
