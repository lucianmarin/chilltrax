import Foundation
import AVFoundation
import Accelerate
import UserNotifications

@MainActor
public final class RadioPlayer: NSObject, ObservableObject {
    public enum PlaybackStatus: String, Equatable, Sendable {
        case idle = "Ready"
        case buffering = "Connecting…"
        case playing = "Live"
        case paused = "Paused"
        case error = "Stream Error"

        public func toolbarLabel(for station: RadioStation) -> String {
            switch self {
            case .playing:
                return station.badgeLabel
            case .idle, .buffering, .paused, .error:
                return rawValue.uppercased()
            }
        }
    }

    @Published public private(set) var isPlaying: Bool = false
    @Published public private(set) var status: PlaybackStatus = .idle
    @Published public private(set) var errorMessage: String?

    nonisolated public static let visualizerBarCount = 56

    /// 56 normalized frequency/amplitude bins in `0.0...1.0` updated at 30fps for Waveform & Spectrum visualizers.
    @Published public private(set) var visualizerLevels: [CGFloat] = Array(repeating: 0.08, count: RadioPlayer.visualizerBarCount)
    /// Trailing envelope levels that decay behind `visualizerLevels` to render a subtle movement fade on Spectrum bars.
    @Published public private(set) var visualizerTrailLevels: [CGFloat] = Array(repeating: 0.08, count: RadioPlayer.visualizerBarCount)
    @Published public private(set) var waveformPhase: Double = 0.0

    public var onICYMetadataReceived: ((SongMetadata) -> Void)?

    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var metadataOutput: AVPlayerItemMetadataOutput?
    private var timeControlObserver: NSKeyValueObservation?
    private var itemStatusObserver: NSKeyValueObservation?
    private var visualizerTimer: Timer?
    private var currentStreamURL: URL?
    private var lastRealAudioLevels: [CGFloat]?
    private var lastRealAudioTimestamp: TimeInterval = 0

    public override init() {
        super.init()
        startVisualizerTimer()
    }

    public func play(url: URL) {
        errorMessage = nil
        status = .buffering
        isPlaying = true

        if currentStreamURL != url || player == nil || playerItem?.status == .failed {
            setupPlayer(with: url)
        }

        player?.volume = 1.0
        player?.play()
    }

    public func pause() {
        isPlaying = false
        status = .paused
        teardownActiveStream()
    }

    public func stop() {
        isPlaying = false
        status = .idle
        teardownActiveStream()
    }

    private func teardownActiveStream() {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        timeControlObserver?.invalidate()
        itemStatusObserver?.invalidate()
        timeControlObserver = nil
        itemStatusObserver = nil
        if let metaOutput = metadataOutput {
            playerItem?.remove(metaOutput)
        }
        metadataOutput = nil
        playerItem = nil
        player = nil
        currentStreamURL = nil
        lastRealAudioLevels = nil
    }

    public func togglePlayPause(url: URL) {
        if isPlaying {
            pause()
        } else {
            play(url: url)
        }
    }

    public func setSimulatedPlaybackStateForTesting(isPlaying: Bool, status: PlaybackStatus = .playing) {
        self.isPlaying = isPlaying
        self.status = isPlaying ? status : .paused
    }

    // MARK: - AVPlayer Setup & ICY Metadata

    private func setupPlayer(with url: URL) {
        timeControlObserver?.invalidate()
        itemStatusObserver?.invalidate()

        currentStreamURL = url
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 4.0

        let metaOutput = AVPlayerItemMetadataOutput(identifiers: nil)
        metaOutput.setDelegate(self, queue: .main)
        item.add(metaOutput)
        self.metadataOutput = metaOutput
        self.playerItem = item

        if let existingPlayer = player {
            existingPlayer.volume = 1.0
            existingPlayer.replaceCurrentItem(with: item)
        } else {
            let newPlayer = AVPlayer(playerItem: item)
            newPlayer.automaticallyWaitsToMinimizeStalling = true
            newPlayer.volume = 1.0
            self.player = newPlayer
        }

        itemStatusObserver = item.observe(\.status, options: [.new, .initial]) { [weak self] observedItem, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch observedItem.status {
                case .failed:
                    self.isPlaying = false
                    self.status = .error
                    self.errorMessage = observedItem.error?.localizedDescription ?? "Unable to connect to stream."
                case .readyToPlay:
                    if self.isPlaying && self.player?.timeControlStatus == .playing {
                        self.status = .playing
                    }
                case .unknown:
                    break
                @unknown default:
                    break
                }
            }
        }

        timeControlObserver = player?.observe(\.timeControlStatus, options: [.new, .initial]) { [weak self] observedPlayer, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch observedPlayer.timeControlStatus {
                case .playing:
                    self.isPlaying = true
                    self.status = .playing
                    self.errorMessage = nil
                case .waitingToPlayAtSpecifiedRate:
                    if self.isPlaying {
                        self.status = .buffering
                    }
                case .paused:
                    if !self.isPlaying {
                        self.status = self.status == .error ? .error : .paused
                    }
                @unknown default:
                    break
                }
            }
        }
    }

    // MARK: - Real-Time Audio Intensity & Visualizer Synthesis

    /// Computes normalized `0.07...1.0` frequency/intensity bins from mono/interleaved PCM float samples using `Accelerate`.
    nonisolated public static func computeSpectrumLevels(
        fromPCM samples: [Float],
        count: Int = RadioPlayer.visualizerBarCount
    ) -> [CGFloat] {
        guard count > 0 else { return [] }
        guard !samples.isEmpty else {
            return Array(repeating: 0.07, count: count)
        }

        // Overall RMS intensity
        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))
        let overallGain = min(1.0, Double(rms) * 3.2)

        let chunkSize = max(1, samples.count / count)
        var bins = [CGFloat]()
        bins.reserveCapacity(count)

        for i in 0..<count {
            let start = min(samples.count - 1, i * chunkSize)
            let end = min(samples.count, start + chunkSize)
            let sliceCount = max(1, end - start)

            var bandRMS: Float = 0
            var bandPeak: Float = 0
            samples.withUnsafeBufferPointer { buffer in
                guard let base = buffer.baseAddress else { return }
                vDSP_rmsqv(base + start, 1, &bandRMS, vDSP_Length(sliceCount))
                vDSP_maxmgv(base + start, 1, &bandPeak, vDSP_Length(sliceCount))
            }

            // Combine band energy, peak transient, and overall musical intensity
            let norm = Double(i) / Double(max(1, count - 1))
            let spectralWeight = sin(norm * .pi) * 0.22 + 0.78
            let combined = (Double(bandRMS) * 2.45 + Double(bandPeak) * 0.95) * 0.68 + overallGain * 0.32
            let scaled = combined * spectralWeight
            let clamped = max(0.07, min(1.0, scaled))
            bins.append(CGFloat(clamped))
        }

        return bins
    }

    public func updateVisualizerWithAudioSamples(_ samples: [Float]) {
        let computed = Self.computeSpectrumLevels(fromPCM: samples, count: visualizerLevels.count)
        lastRealAudioLevels = computed
        lastRealAudioTimestamp = ProcessInfo.processInfo.systemUptime

        var smoothed = [CGFloat]()
        var trails = [CGFloat]()
        smoothed.reserveCapacity(visualizerLevels.count)
        trails.reserveCapacity(visualizerLevels.count)
        let peakComputed = computed.max() ?? 0.07
        let prevAvg = visualizerLevels.reduce(0, +) / CGFloat(max(1, visualizerLevels.count))
        let isPunchyTransient = (peakComputed - prevAvg) > 0.22 || peakComputed > 0.78

        for i in 0..<visualizerLevels.count {
            let prev = visualizerLevels[i]
            var target = computed[i]
            if isPunchyTransient && target >= peakComputed * 0.82 {
                // Boost peak bands to full vertical amplitude on punchy transients
                let normToPeak = target / max(0.01, peakComputed)
                target = min(1.0, max(target, normToPeak * min(1.0, peakComputed * 1.18)))
            }
            let blend: CGFloat = target > prev ? (target > 0.78 ? 0.90 : 0.68) : 0.64
            let nextVal = prev * (1.0 - blend) + target * blend
            smoothed.append(nextVal)

            let prevTrail = i < visualizerTrailLevels.count ? visualizerTrailLevels[i] : prev
            let retention: CGFloat = 0.88
            let decayedTrail = prevTrail * retention + nextVal * (1.0 - retention)
            let movementBoost = abs(nextVal - prev) * 0.75
            trails.append(max(nextVal, min(1.0, decayedTrail + movementBoost)))
        }
        visualizerLevels = smoothed
        visualizerTrailLevels = trails

        let averageIntensity = Double(smoothed.reduce(0, +)) / Double(max(1, smoothed.count))
        waveformPhase += 0.07 + averageIntensity * 0.24
    }

    private func startVisualizerTimer() {
        visualizerTimer?.invalidate()
        visualizerTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tickVisualizer()
            }
        }
    }

    public func tickVisualizer() {
        let count = visualizerLevels.count
        let activelyStreaming = isPlaying && (status == .playing || status == .buffering)

        if activelyStreaming {
            // If real PCM audio tap samples arrived recently, let the live audio tap drive levels
            let now = ProcessInfo.processInfo.systemUptime
            if status == .playing,
               let liveLevels = lastRealAudioLevels,
               liveLevels.count == count,
               (now - lastRealAudioTimestamp) < 0.25 {
                var nextLevels = [CGFloat]()
                var nextTrails = [CGFloat]()
                nextLevels.reserveCapacity(count)
                nextTrails.reserveCapacity(count)
                for i in 0..<count {
                    let prev = visualizerLevels[i]
                    let target = liveLevels[i]
                    let blend: CGFloat = target > prev ? 0.62 : 0.60
                    let nextVal = prev * (1.0 - blend) + target * blend
                    nextLevels.append(nextVal)

                    let prevTrail = i < visualizerTrailLevels.count ? visualizerTrailLevels[i] : prev
                    let retention: CGFloat = 0.88
                    let decayedTrail = prevTrail * retention + nextVal * (1.0 - retention)
                    let movementBoost = abs(nextVal - prev) * 0.75
                    nextTrails.append(max(nextVal, min(1.0, decayedTrail + movementBoost)))
                }
                visualizerLevels = nextLevels
                visualizerTrailLevels = nextTrails
                let avg = Double(nextLevels.reduce(0, +)) / Double(max(1, count))
                waveformPhase += 0.07 + avg * 0.24
                return
            }

            var nextLevels = [CGFloat]()
            var nextTrails = [CGFloat]()
            nextLevels.reserveCapacity(count)
            nextTrails.reserveCapacity(count)
            let t = waveformPhase

            // Balanced musical baseline in lower/mid area with sharp punch transients that reach 1.0 on beats
            let phraseSwell = (sin(t * 0.45) + 1.0) * 0.5 * 0.35 + 0.52
            let beatKick = pow((sin(t * 1.95) + 1.0) * 0.5, 3.8)
            let snarePunch = pow((cos(t * 1.30 - 0.55) + 1.0) * 0.5, 4.4)
            let punchTransient = max(beatKick, snarePunch * 0.95)
            // Focal bar position shifts across the spectrum on each beat so punch peaks feel dynamic
            let punchCenter = 0.14 + 0.72 * ((sin(t * 0.63) + 1.0) * 0.5)

            for i in 0..<count {
                let norm = Double(i) / Double(max(1, count - 1))
                // Smooth center-weighted envelope with consistent variation across adjacent red/black/gray bars
                let envelope = sin(norm * .pi) * 0.42 + 0.58
                let bassPulse = beatKick * (1.0 - norm * 0.28)
                let midWave = pow((sin(t * 2.5 + Double(i) * 0.42) + 1.0) * 0.5, 1.55)
                let harmonic = pow((cos(t * 3.9 - Double(i) * 0.64) + 1.0) * 0.5, 1.65)
                let shimmer = pow((sin(t * 5.8 + Double(i) * 0.32) + 1.0) * 0.5, 1.75)

                let rawLevel: Double
                if status == .buffering {
                    rawLevel = 0.12 + 0.18 * sin(t * 2.0 + Double(i) * 0.35)
                } else {
                    let baseCombined = (bassPulse * 0.38 + midWave * 0.28 + harmonic * 0.16 + shimmer * 0.10)
                    let baseLevel = baseCombined * envelope * phraseSwell

                    // Sharp localized punch surge on beats so peak bars reach 1.0 while overall average stays low/mid
                    let distFromPunch = abs(norm - punchCenter)
                    let punchFocus = max(0.0, 1.0 - distFromPunch * 2.6)
                    let harmonicRipple = (sin(Double(i) * 0.55 + t * 3.2) + 1.0) * 0.5 * 0.22 + 0.84
                    let punchSurge = pow(punchTransient, 1.25) * punchFocus * harmonicRipple * 1.18
                    rawLevel = max(baseLevel, min(1.0, baseLevel * 0.45 + punchSurge))
                }

                let clamped = max(0.07, min(1.0, rawLevel))
                let previous = Double(visualizerLevels[i])
                // Fast attack on punchy peaks so bars snap to 1.0, and brisk decay so they return to the lower/mid area
                let blend: Double
                if clamped > previous {
                    blend = clamped > 0.78 ? 0.92 : 0.64
                } else {
                    blend = 0.65
                }
                let smoothed = CGFloat(max(0.07, min(1.0, previous * (1.0 - blend) + clamped * blend)))
                nextLevels.append(smoothed)

                let prevTrail = i < visualizerTrailLevels.count ? visualizerTrailLevels[i] : CGFloat(previous)
                let retention: CGFloat = 0.88
                let decayedTrail = prevTrail * retention + smoothed * (1.0 - retention)
                let movementBoost = abs(smoothed - CGFloat(previous)) * 0.75
                nextTrails.append(max(smoothed, min(1.0, decayedTrail + movementBoost)))
            }
            visualizerLevels = nextLevels
            visualizerTrailLevels = nextTrails
            let averageIntensity = Double(nextLevels.reduce(0, +)) / Double(max(1, count))
            let speed = status == .playing ? (0.08 + averageIntensity * 0.22) : 0.07
            waveformPhase += speed
        } else {
            waveformPhase += 0.02
            var settled = [CGFloat]()
            var settledTrails = [CGFloat]()
            settled.reserveCapacity(count)
            settledTrails.reserveCapacity(count)
            for i in 0..<count {
                let prev = visualizerLevels[i]
                let target: CGFloat = 0.06
                let nextVal = prev * 0.82 + target * 0.18
                settled.append(nextVal)
                let prevTrail = i < visualizerTrailLevels.count ? visualizerTrailLevels[i] : prev
                settledTrails.append(max(nextVal, prevTrail * 0.78 + target * 0.22))
            }
            visualizerLevels = settled
            visualizerTrailLevels = settledTrails
        }
    }
}

extension RadioPlayer: @preconcurrency AVPlayerItemMetadataOutputPushDelegate {
    public func metadataOutput(
        _ output: AVPlayerItemMetadataOutput,
        didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup],
        from track: AVPlayerItemTrack?
    ) {
        guard isPlaying else { return }
        for group in groups {
            for item in group.items {
                Task { @MainActor [weak self] in
                    guard let self, self.isPlaying else { return }
                    if let stringValue = try? await item.load(.stringValue),
                       let parsed = SongMetadata.fromICYStreamTitle(stringValue),
                       parsed.isMeaningfulTrack {
                        self.onICYMetadataReceived?(parsed)
                    }
                }
            }
        }
    }
}

// MARK: - Song Change Notification Manager

@MainActor
public final class SongNotificationManager {
    public static let shared = SongNotificationManager()

    private var hasRequestedAuthorization = false

    private init() {}

    /// Safely checks whether the process is running inside a signed/valid macOS `.app` bundle
    /// before accessing `UNUserNotificationCenter.current()`, preventing crashes during `swift test`.
    private var canUseUserNotifications: Bool {
        guard let bundleID = Bundle.main.bundleIdentifier, !bundleID.isEmpty else {
            return false
        }
        return Bundle.main.bundlePath.hasSuffix(".app")
    }

    public func requestAuthorizationIfNeeded() {
        guard canUseUserNotifications, !hasRequestedAuthorization else { return }
        hasRequestedAuthorization = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    public static func makeNotificationContent(song: SongMetadata, station: RadioStation) -> UNMutableNotificationContent {
        makeNotificationContent(song: song, stationName: station.title)
    }

    public static func makeNotificationContent(song: SongMetadata, stationName: String) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = song.title.isEmpty ? stationName : song.title
        if !song.artist.isEmpty && !song.albumOrMix.isEmpty {
            content.subtitle = "\(song.artist) • \(song.albumOrMix)"
        } else if !song.artist.isEmpty {
            content.subtitle = song.artist
        } else {
            content.subtitle = stationName
        }
        content.body = "Now playing on \(stationName)"
        return content
    }

    public func sendSongChangeNotification(song: SongMetadata, stationName: String) {
        guard canUseUserNotifications, song.isMeaningfulTrack else { return }
        requestAuthorizationIfNeeded()

        let content = Self.makeNotificationContent(song: song, stationName: stationName)

        let request = UNNotificationRequest(
            identifier: "chilltrax.song.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}
