import SwiftUI

public struct VisualizerView: View {
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
                    .foregroundStyle(Color.black.opacity(0.75))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.07), in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(6)
                .help("Switch visualizer between Waveform and Bars")
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(ChilltraxTheme.visualizerWhite)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.12), lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func drawBars(context: inout GraphicsContext, size: CGSize) {
        let count = max(1, levels.count)
        let horizontalPadding: CGFloat = 10
        let verticalPadding: CGFloat = 8
        let usableWidth = max(10, size.width - horizontalPadding * 2)
        let usableHeight = max(8, size.height - verticalPadding * 2)
        let spacing: CGFloat = 3.5
        let totalSpacing = spacing * CGFloat(count - 1)
        let barWidth = max(2.5, (usableWidth - totalSpacing) / CGFloat(count))

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
                barColor = isAccentBar ? ChilltraxTheme.accentRed : ChilltraxTheme.visualizerBlack
            } else {
                barColor = (index % 2 == 0)
                    ? ChilltraxTheme.accentRed.opacity(0.55)
                    : ChilltraxTheme.visualizerBlack.opacity(0.35)
            }

            context.fill(path, with: .color(barColor))
        }
    }

    private func drawWaveform(context: inout GraphicsContext, size: CGSize) {
        let midY = size.height / 2.0
        let usableAmplitude = (size.height * 0.42)
        let steps = max(64, Int(size.width / 3))

        let averageLevel: CGFloat = {
            guard !levels.isEmpty else { return 0.1 }
            let sum = levels.reduce(0, +)
            return sum / CGFloat(levels.count)
        }()

        // Secondary black harmonic wave
        var blackWavePath = Path()
        for step in 0...steps {
            let progress = CGFloat(step) / CGFloat(steps)
            let x = progress * size.width
            let binIndex = min(levels.count - 1, max(0, Int(progress * CGFloat(levels.count - 1))))
            let binLevel = levels.isEmpty ? 0.1 : levels[binIndex]
            let window = sin(Double(progress) * .pi)
            let wave = sin(Double(progress) * .pi * 5.0 - phase * 1.4)
                * cos(Double(progress) * .pi * 2.5 + phase * 0.8)
            let amplitude = Double(usableAmplitude) * Double(max(0.06, binLevel * 0.8)) * window
            let y = midY + CGFloat(wave * amplitude)
            if step == 0 {
                blackWavePath.move(to: CGPoint(x: x, y: y))
            } else {
                blackWavePath.addLine(to: CGPoint(x: x, y: y))
            }
        }

        context.stroke(
            blackWavePath,
            with: .color(ChilltraxTheme.visualizerBlack.opacity(isPlaying ? 0.85 : 0.45)),
            style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round)
        )

        // Primary red foreground wave + subtle red tint fill
        var redWavePath = Path()
        var fillPath = Path()
        fillPath.move(to: CGPoint(x: 0, y: midY))

        for step in 0...steps {
            let progress = CGFloat(step) / CGFloat(steps)
            let x = progress * size.width
            let binIndex = min(levels.count - 1, max(0, Int(progress * CGFloat(levels.count - 1))))
            let binLevel = levels.isEmpty ? 0.1 : levels[binIndex]
            let window = sin(Double(progress) * .pi)
            let carrier = sin(Double(progress) * .pi * 7.0 + phase * 2.1)
            let sub = sin(Double(progress) * .pi * 3.0 - phase * 1.1) * 0.45
            let combinedWave = (carrier * 0.7 + sub * 0.3)
            let effectiveLevel = max(0.06, (binLevel * 0.7 + averageLevel * 0.3))
            let y = midY + CGFloat(combinedWave * Double(usableAmplitude * effectiveLevel) * window)

            if step == 0 {
                redWavePath.move(to: CGPoint(x: x, y: y))
            } else {
                redWavePath.addLine(to: CGPoint(x: x, y: y))
            }
            fillPath.addLine(to: CGPoint(x: x, y: y))
        }

        fillPath.addLine(to: CGPoint(x: size.width, y: midY))
        fillPath.closeSubpath()

        context.fill(
            fillPath,
            with: .color(ChilltraxTheme.accentRed.opacity(isPlaying ? 0.14 : 0.06))
        )

        context.stroke(
            redWavePath,
            with: .color(ChilltraxTheme.accentRed.opacity(isPlaying ? 1.0 : 0.65)),
            style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)
        )
    }
}
