import Foundation
import AVFoundation
import UserNotifications

@MainActor
public final class RadioPlayer: NSObject, ObservableObject {
    public enum PlaybackStatus: String, Equatable, Sendable {
        case idle = "Ready"
        case buffering = "Connecting…"
        case playing = "Live"
        case paused = "Paused"
        case error = "Stream Error"
    }

    @Published public private(set) var isPlaying: Bool = false
    @Published public private(set) var status: PlaybackStatus = .idle
    @Published public private(set) var errorMessage: String?

    /// 32 normalized frequency/amplitude bins in `0.0...1.0` updated at 30fps for Waveform & Bars visualizers.
    @Published public private(set) var visualizerLevels: [CGFloat] = Array(repeating: 0.08, count: 32)
    @Published public private(set) var waveformPhase: Double = 0.0

    public var onICYMetadataReceived: ((SongMetadata) -> Void)?

    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var metadataOutput: AVPlayerItemMetadataOutput?
    private var timeControlObserver: NSKeyValueObservation?
    private var itemStatusObserver: NSKeyValueObservation?
    private var visualizerTimer: Timer?
    private var currentStreamURL: URL?

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
        player?.pause()
    }

    public func stop() {
        isPlaying = false
        status = .idle
        player?.pause()
        timeControlObserver?.invalidate()
        itemStatusObserver?.invalidate()
        timeControlObserver = nil
        itemStatusObserver = nil
        playerItem = nil
        player = nil
        currentStreamURL = nil
    }

    public func togglePlayPause(url: URL) {
        if isPlaying {
            pause()
        } else {
            play(url: url)
        }
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

    // MARK: - Real-Time Visualizer Synthesis

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
            let speed = status == .playing ? 0.18 : 0.07
            waveformPhase += speed
            let t = waveformPhase

            var nextLevels = [CGFloat]()
            nextLevels.reserveCapacity(count)

            for i in 0..<count {
                let norm = Double(i) / Double(max(1, count - 1))
                // Center-weighted chillout bass/mid/treble envelope with organic polyrhythmic modulation
                let envelope = sin(norm * .pi) * 0.65 + 0.35
                let bassPulse = pow((sin(t * 1.35) + 1.0) * 0.5, 1.8) * (1.0 - norm * 0.55)
                let midWave = (sin(t * 2.4 + Double(i) * 0.45) + 1.0) * 0.5
                let harmonic = (cos(t * 3.9 - Double(i) * 0.72) + 1.0) * 0.5
                let shimmer = (sin(t * 6.1 + Double(i * i) * 0.13) + 1.0) * 0.5

                let rawLevel: Double
                if status == .buffering {
                    rawLevel = 0.12 + 0.18 * sin(t * 2.0 + Double(i) * 0.35)
                } else {
                    rawLevel = (bassPulse * 0.38 + midWave * 0.32 + harmonic * 0.18 + shimmer * 0.12) * envelope
                }

                let clamped = max(0.08, min(0.98, rawLevel))
                let previous = Double(visualizerLevels[i])
                // Smooth attack/decay filter
                let smoothed = previous * 0.45 + clamped * 0.55
                nextLevels.append(CGFloat(smoothed))
            }
            visualizerLevels = nextLevels
        } else {
            waveformPhase += 0.02
            var settled = [CGFloat]()
            settled.reserveCapacity(count)
            for i in 0..<count {
                let prev = visualizerLevels[i]
                let target: CGFloat = 0.06
                settled.append(prev * 0.82 + target * 0.18)
            }
            visualizerLevels = settled
        }
    }
}

extension RadioPlayer: @preconcurrency AVPlayerItemMetadataOutputPushDelegate {
    public func metadataOutput(
        _ output: AVPlayerItemMetadataOutput,
        didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup],
        from track: AVPlayerItemTrack?
    ) {
        for group in groups {
            for item in group.items {
                Task { @MainActor [weak self] in
                    guard let self else { return }
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

    public func sendSongChangeNotification(song: SongMetadata, stationName: String) {
        guard canUseUserNotifications, song.isMeaningfulTrack else { return }
        requestAuthorizationIfNeeded()

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

        let request = UNNotificationRequest(
            identifier: "chilltrax.song.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}
