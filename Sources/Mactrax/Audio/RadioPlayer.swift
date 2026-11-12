import Foundation
import AVFoundation
import Accelerate
import UserNotifications

@MainActor
public final class RadioPlayer: NSObject, ObservableObject {
    public enum PlaybackStatus: String, Equatable, Sendable {
        case idle = "Ready"
        case buffering = "Loading"
        case playing = "Live"
        case paused = "Paused"
        case error = "Error"

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

    /// Controls whether the 30fps visualizer timer should run while streaming.
    public var isVisualizerEnabled: Bool = true {
        didSet {
            guard isVisualizerEnabled != oldValue else { return }
            updateVisualizerTimerState()
        }
    }

    /// Controls whether the player window is currently visible on screen (not minimized, hidden, or occluded).
    public var isWindowVisible: Bool = true {
        didSet {
            guard isWindowVisible != oldValue else { return }
            updateVisualizerTimerState()
        }
    }

    nonisolated public static let visualizerBarCount = 56

    /// Precomputed per-bar trigonometric & envelope tables for `visualizerBarCount` (56) bars.
    private struct BarLookupTable: Sendable {
        let count: Int
        let norm: [Double]
        let spectralWeight: [Double]
        let envelope: [Double]
        let bassWeight: [Double]
        let sin042: [Double]
        let cos042: [Double]
        let sin064: [Double]
        let cos064: [Double]
        let sin032: [Double]
        let cos032: [Double]
        let sin055: [Double]
        let cos055: [Double]
        let sin035: [Double]
        let cos035: [Double]

        init(count: Int) {
            self.count = count
            var norm = [Double](repeating: 0, count: count)
            var spectralWeight = [Double](repeating: 0, count: count)
            var envelope = [Double](repeating: 0, count: count)
            var bassWeight = [Double](repeating: 0, count: count)
            var sin042 = [Double](repeating: 0, count: count)
            var cos042 = [Double](repeating: 0, count: count)
            var sin064 = [Double](repeating: 0, count: count)
            var cos064 = [Double](repeating: 0, count: count)
            var sin032 = [Double](repeating: 0, count: count)
            var cos032 = [Double](repeating: 0, count: count)
            var sin055 = [Double](repeating: 0, count: count)
            var cos055 = [Double](repeating: 0, count: count)
            var sin035 = [Double](repeating: 0, count: count)
            var cos035 = [Double](repeating: 0, count: count)

            let denom = Double(max(1, count - 1))
            for i in 0..<count {
                let n = Double(i) / denom
                let idx = Double(i)
                let sinPiN = sin(n * .pi)
                norm[i] = n
                spectralWeight[i] = sinPiN * 0.22 + 0.78
                envelope[i] = sinPiN * 0.42 + 0.58
                bassWeight[i] = 1.0 - n * 0.28
                sin042[i] = sin(idx * 0.42)
                cos042[i] = cos(idx * 0.42)
                sin064[i] = sin(idx * 0.64)
                cos064[i] = cos(idx * 0.64)
                sin032[i] = sin(idx * 0.32)
                cos032[i] = cos(idx * 0.32)
                sin055[i] = sin(idx * 0.55)
                cos055[i] = cos(idx * 0.55)
                sin035[i] = sin(idx * 0.35)
                cos035[i] = cos(idx * 0.35)
            }

            self.norm = norm
            self.spectralWeight = spectralWeight
            self.envelope = envelope
            self.bassWeight = bassWeight
            self.sin042 = sin042
            self.cos042 = cos042
            self.sin064 = sin064
            self.cos064 = cos064
            self.sin032 = sin032
            self.cos032 = cos032
            self.sin055 = sin055
            self.cos055 = cos055
            self.sin035 = sin035
            self.cos035 = cos035
        }
    }

    nonisolated private static let defaultBarTable = BarLookupTable(count: RadioPlayer.visualizerBarCount)

    /// 56 normalized frequency/amplitude bins in `0.0...1.0` updated at 30fps for Waveform & Spectrum visualizers.
    /// Changes are coalesced into a single `objectWillChange` emission per visualizer tick.
    public private(set) var visualizerLevels: [CGFloat] = Array(repeating: 0.08, count: RadioPlayer.visualizerBarCount)
    /// Trailing envelope levels that decay behind `visualizerLevels` to render a subtle movement fade on Spectrum bars.
    public private(set) var visualizerTrailLevels: [CGFloat] = Array(repeating: 0.08, count: RadioPlayer.visualizerBarCount)
    public private(set) var waveformPhase: Double = 0.0

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
        updateVisualizerTimerState()
    }

    public func pause() {
        stop()
    }

    public func stop() {
        isPlaying = false
        status = .idle
        teardownActiveStream()
    }

    private func teardownActiveStream() {
        stopVisualizerTimer()
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
        resetVisualizerLevels()
    }

    public func togglePlayPause(url: URL) {
        if isPlaying {
            stop()
        } else {
            play(url: url)
        }
    }

    public func setSimulatedPlaybackStateForTesting(isPlaying: Bool, status: PlaybackStatus = .playing) {
        self.isPlaying = isPlaying
        self.status = isPlaying ? status : (status == .playing ? .idle : status)
        updateVisualizerTimerState()
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
                    self.updateVisualizerTimerState()
                case .readyToPlay:
                    if self.isPlaying && self.player?.timeControlStatus == .playing {
                        self.status = .playing
                    }
                    self.updateVisualizerTimerState()
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
                        self.status = self.status == .error ? .error : .idle
                    }
                @unknown default:
                    break
                }
                self.updateVisualizerTimerState()
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
        let useDefaultTable = (count == defaultBarTable.count)
        let denom = Double(max(1, count - 1))

        samples.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            for i in 0..<count {
                let start = min(samples.count - 1, i * chunkSize)
                let end = min(samples.count, start + chunkSize)
                let sliceCount = max(1, end - start)

                var bandRMS: Float = 0
                var bandPeak: Float = 0
                vDSP_rmsqv(base + start, 1, &bandRMS, vDSP_Length(sliceCount))
                vDSP_maxmgv(base + start, 1, &bandPeak, vDSP_Length(sliceCount))

                // Combine band energy, peak transient, and overall musical intensity
                let spectralWeight: Double
                if useDefaultTable {
                    spectralWeight = defaultBarTable.spectralWeight[i]
                } else {
                    let norm = Double(i) / denom
                    spectralWeight = sin(norm * .pi) * 0.22 + 0.78
                }
                let combined = (Double(bandRMS) * 2.45 + Double(bandPeak) * 0.95) * 0.68 + overallGain * 0.32
                let scaled = combined * spectralWeight
                let clamped = max(0.07, min(1.0, scaled))
                bins.append(CGFloat(clamped))
            }
        }

        return bins
    }

    public func updateVisualizerWithAudioSamples(_ samples: [Float]) {
        let count = visualizerLevels.count
        let computed = Self.computeSpectrumLevels(fromPCM: samples, count: count)
        lastRealAudioLevels = computed
        lastRealAudioTimestamp = ProcessInfo.processInfo.systemUptime

        var peakComputed: CGFloat = 0.07
        for val in computed where val > peakComputed {
            peakComputed = val
        }
        var prevSum: CGFloat = 0
        for val in visualizerLevels {
            prevSum += val
        }
        let prevAvg = prevSum / CGFloat(max(1, count))
        let isPunchyTransient = (peakComputed - prevAvg) > 0.22 || peakComputed > 0.78

        objectWillChange.send()
        if visualizerTrailLevels.count != count {
            visualizerTrailLevels = Array(repeating: 0.08, count: count)
        }

        var sumSmoothed: CGFloat = 0
        for i in 0..<count {
            let prev = visualizerLevels[i]
            var target = computed[i]
            if isPunchyTransient && target >= peakComputed * 0.82 {
                // Boost peak bands to full vertical amplitude on punchy transients
                let normToPeak = target / max(0.01, peakComputed)
                target = min(1.0, max(target, normToPeak * min(1.0, peakComputed * 1.18)))
            }
            let blend: CGFloat = target > prev ? (target > 0.78 ? 0.90 : 0.68) : 0.64
            let nextVal = prev * (1.0 - blend) + target * blend
            visualizerLevels[i] = nextVal
            sumSmoothed += nextVal

            let prevTrail = visualizerTrailLevels[i]
            let retention: CGFloat = 0.88
            let decayedTrail = prevTrail * retention + nextVal * (1.0 - retention)
            let movementBoost = abs(nextVal - prev) * 0.75
            visualizerTrailLevels[i] = max(nextVal, min(1.0, decayedTrail + movementBoost))
        }

        let averageIntensity = Double(sumSmoothed) / Double(max(1, count))
        waveformPhase += 0.07 + averageIntensity * 0.24
    }

    public var isVisualizerTimerRunning: Bool {
        visualizerTimer?.isValid == true
    }

    private func updateVisualizerTimerState() {
        let shouldRun = isVisualizerEnabled && isWindowVisible && isPlaying && (status == .playing || status == .buffering)
        if shouldRun {
            startVisualizerTimer()
        } else {
            stopVisualizerTimer()
        }
    }

    private func startVisualizerTimer() {
        guard visualizerTimer == nil else { return }
        let interval = 1.0 / 30.0
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tickVisualizer()
            }
        }
        timer.tolerance = interval * 0.15
        visualizerTimer = timer
    }

    private func stopVisualizerTimer() {
        visualizerTimer?.invalidate()
        visualizerTimer = nil
    }

    private func resetVisualizerLevels() {
        let idleValue: CGFloat = 0.08
        let needsReset = visualizerLevels.contains { $0 != idleValue }
            || visualizerTrailLevels.contains { $0 != idleValue }
        guard needsReset else { return }
        objectWillChange.send()
        for i in 0..<visualizerLevels.count {
            visualizerLevels[i] = idleValue
        }
        for i in 0..<visualizerTrailLevels.count {
            visualizerTrailLevels[i] = idleValue
        }
    }

    public func tickVisualizer() {
        let count = visualizerLevels.count
        if visualizerTrailLevels.count != count {
            visualizerTrailLevels = Array(repeating: 0.08, count: count)
        }
        let activelyStreaming = isPlaying && (status == .playing || status == .buffering)

        objectWillChange.send()

        if activelyStreaming {
            // If real PCM audio tap samples arrived recently, let the live audio tap drive levels
            let now = ProcessInfo.processInfo.systemUptime
            if status == .playing,
               let liveLevels = lastRealAudioLevels,
               liveLevels.count == count,
               (now - lastRealAudioTimestamp) < 0.25 {
                var sumLevels: CGFloat = 0
                for i in 0..<count {
                    let prev = visualizerLevels[i]
                    let target = liveLevels[i]
                    let blend: CGFloat = target > prev ? 0.62 : 0.60
                    let nextVal = prev * (1.0 - blend) + target * blend
                    visualizerLevels[i] = nextVal
                    sumLevels += nextVal

                    let prevTrail = visualizerTrailLevels[i]
                    let retention: CGFloat = 0.88
                    let decayedTrail = prevTrail * retention + nextVal * (1.0 - retention)
                    let movementBoost = abs(nextVal - prev) * 0.75
                    visualizerTrailLevels[i] = max(nextVal, min(1.0, decayedTrail + movementBoost))
                }
                let avg = Double(sumLevels) / Double(max(1, count))
                waveformPhase += 0.07 + avg * 0.24
                return
            }

            let t = waveformPhase
            let table = Self.defaultBarTable
            let useTable = (count == table.count)

            // Balanced musical baseline in lower/mid area with sharp punch transients that reach 1.0 on beats
            let phraseSwell = (sin(t * 0.45) + 1.0) * 0.5 * 0.35 + 0.52
            let beatKick = pow((sin(t * 1.95) + 1.0) * 0.5, 3.8)
            let snarePunch = pow((cos(t * 1.30 - 0.55) + 1.0) * 0.5, 4.4)
            let punchTransient = max(beatKick, snarePunch * 0.95)
            let punchTransientScaled = pow(punchTransient, 1.25) * 1.18
            // Focal bar position shifts across the spectrum on each beat so punch peaks feel dynamic
            let punchCenter = 0.14 + 0.72 * ((sin(t * 0.63) + 1.0) * 0.5)

            // Precompute per-frame trig components for angle-addition identities
            let sinT25 = sin(t * 2.5)
            let cosT25 = cos(t * 2.5)
            let sinT39 = sin(t * 3.9)
            let cosT39 = cos(t * 3.9)
            let sinT58 = sin(t * 5.8)
            let cosT58 = cos(t * 5.8)
            let sinT32 = sin(t * 3.2)
            let cosT32 = cos(t * 3.2)
            let sinT20 = sin(t * 2.0)
            let cosT20 = cos(t * 2.0)

            var sumLevels: CGFloat = 0
            let isBuffering = (status == .buffering)

            for i in 0..<count {
                let rawLevel: Double
                if isBuffering {
                    let sinBuffering: Double
                    if useTable {
                        // sin(t * 2.0 + i * 0.35)
                        sinBuffering = sinT20 * table.cos035[i] + cosT20 * table.sin035[i]
                    } else {
                        sinBuffering = sin(t * 2.0 + Double(i) * 0.35)
                    }
                    rawLevel = 0.12 + 0.18 * sinBuffering
                } else {
                    let norm: Double
                    let envelope: Double
                    let bassPulse: Double
                    let sinMid: Double
                    let cosHarm: Double
                    let sinShim: Double
                    let sinRip: Double

                    if useTable {
                        norm = table.norm[i]
                        envelope = table.envelope[i]
                        bassPulse = beatKick * table.bassWeight[i]
                        // sin(t * 2.5 + i * 0.42)
                        sinMid = sinT25 * table.cos042[i] + cosT25 * table.sin042[i]
                        // cos(t * 3.9 - i * 0.64)
                        cosHarm = cosT39 * table.cos064[i] + sinT39 * table.sin064[i]
                        // sin(t * 5.8 + i * 0.32)
                        sinShim = sinT58 * table.cos032[i] + cosT58 * table.sin032[i]
                        // sin(i * 0.55 + t * 3.2)
                        sinRip = table.sin055[i] * cosT32 + table.cos055[i] * sinT32
                    } else {
                        norm = Double(i) / Double(max(1, count - 1))
                        envelope = sin(norm * .pi) * 0.42 + 0.58
                        bassPulse = beatKick * (1.0 - norm * 0.28)
                        sinMid = sin(t * 2.5 + Double(i) * 0.42)
                        cosHarm = cos(t * 3.9 - Double(i) * 0.64)
                        sinShim = sin(t * 5.8 + Double(i) * 0.32)
                        sinRip = sin(Double(i) * 0.55 + t * 3.2)
                    }

                    let midWave = pow(max(0.0, (sinMid + 1.0) * 0.5), 1.55)
                    let harmonic = pow(max(0.0, (cosHarm + 1.0) * 0.5), 1.65)
                    let shimmer = pow(max(0.0, (sinShim + 1.0) * 0.5), 1.75)

                    let baseCombined = (bassPulse * 0.38 + midWave * 0.28 + harmonic * 0.16 + shimmer * 0.10)
                    let baseLevel = baseCombined * envelope * phraseSwell

                    // Sharp localized punch surge on beats so peak bars reach 1.0 while overall average stays low/mid
                    let distFromPunch = abs(norm - punchCenter)
                    let punchFocus = max(0.0, 1.0 - distFromPunch * 2.6)
                    let harmonicRipple = (sinRip + 1.0) * 0.5 * 0.22 + 0.84
                    let punchSurge = punchTransientScaled * punchFocus * harmonicRipple
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
                visualizerLevels[i] = smoothed
                sumLevels += smoothed

                let prevTrail = visualizerTrailLevels[i]
                let retention: CGFloat = 0.88
                let decayedTrail = prevTrail * retention + smoothed * (1.0 - retention)
                let movementBoost = abs(smoothed - CGFloat(previous)) * 0.75
                visualizerTrailLevels[i] = max(smoothed, min(1.0, decayedTrail + movementBoost))
            }
            let averageIntensity = Double(sumLevels) / Double(max(1, count))
            let speed = status == .playing ? (0.08 + averageIntensity * 0.22) : 0.07
            waveformPhase += speed
        } else {
            waveformPhase += 0.02
            let target: CGFloat = 0.06
            for i in 0..<count {
                let prev = visualizerLevels[i]
                let nextVal = prev * 0.82 + target * 0.18
                visualizerLevels[i] = nextVal
                let prevTrail = visualizerTrailLevels[i]
                visualizerTrailLevels[i] = max(nextVal, prevTrail * 0.78 + target * 0.22)
            }
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
            identifier: "mactrax.song.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}
