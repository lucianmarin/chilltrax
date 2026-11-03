import Foundation
import SwiftUI
import Combine

@MainActor
public final class AppState: ObservableObject {
    private enum DefaultsKeys {
        static let selectedStreamURL = "chilltrax.selectedStreamURL"
        static let selectedStreamName = "chilltrax.selectedStreamName"
        static let customStreams = "chilltrax.customStreams"
        static let discoveredStreams = "chilltrax.discoveredStreams"
        static let visualizerMode = "chilltrax.visualizerMode"
        static let notifyOnSongChange = "chilltrax.notifyOnSongChange"
        static let fetchAlbumCoverFromChilltrax = "chilltrax.fetchAlbumCoverFromChilltrax"
        static let isHistoryExpanded = "chilltrax.isHistoryExpanded"
        static let historyCommitDelaySeconds = "chilltrax.historyCommitDelaySeconds"
    }

    // MARK: - Published UI & Player State

    @Published public var currentSong: SongMetadata = .placeholder
    @Published public var selectedStream: StationStream {
        didSet {
            defaults.set(selectedStream.urlString, forKey: DefaultsKeys.selectedStreamURL)
            defaults.set(selectedStream.name, forKey: DefaultsKeys.selectedStreamName)
        }
    }
    @Published public var discoveredStreams: [StationStream] = StationStream.defaultChilltraxStreams {
        didSet {
            if let encoded = try? JSONEncoder().encode(discoveredStreams) {
                defaults.set(encoded, forKey: DefaultsKeys.discoveredStreams)
            }
        }
    }
    @Published public var customStreams: [StationStream] = [] {
        didSet {
            if let encoded = try? JSONEncoder().encode(customStreams) {
                defaults.set(encoded, forKey: DefaultsKeys.customStreams)
            }
        }
    }
    @Published public var visualizerMode: VisualizerMode {
        didSet {
            defaults.set(visualizerMode.rawValue, forKey: DefaultsKeys.visualizerMode)
        }
    }
    @Published public var notifyOnSongChange: Bool {
        didSet {
            defaults.set(notifyOnSongChange, forKey: DefaultsKeys.notifyOnSongChange)
            if notifyOnSongChange {
                SongNotificationManager.shared.requestAuthorizationIfNeeded()
            }
        }
    }
    @Published public var fetchAlbumCoverFromChilltrax: Bool {
        didSet {
            defaults.set(fetchAlbumCoverFromChilltrax, forKey: DefaultsKeys.fetchAlbumCoverFromChilltrax)
            if fetchAlbumCoverFromChilltrax {
                Task {
                    await refreshCoverArtForSettingChange()
                }
            } else {
                var updated = currentSong
                updated.coverURLString = nil
                currentSong = updated
            }
        }
    }
    @Published public var isHistoryExpanded: Bool {
        didSet {
            defaults.set(isHistoryExpanded, forKey: DefaultsKeys.isHistoryExpanded)
        }
    }
    @Published public var historyCommitDelaySeconds: Int {
        didSet {
            let clamped = min(99, max(0, historyCommitDelaySeconds))
            if historyCommitDelaySeconds != clamped {
                historyCommitDelaySeconds = clamped
                return
            }
            defaults.set(clamped, forKey: DefaultsKeys.historyCommitDelaySeconds)
            minimumHistoryPlayDuration = TimeInterval(clamped)
            scheduleHistoryRecordingIfNeeded()
        }
    }
    @Published public var historySearchQuery: String = "" {
        didSet {
            updateHistoryExpansionForSearch(previousQuery: oldValue)
        }
    }
    @Published public private(set) var historyEntries: [SongHistoryEntry] = []
    @Published public private(set) var isDiscoveringBroadcasts: Bool = false
    @Published public private(set) var discoveryStatusMessage: String?

    public let radioPlayer: RadioPlayer
    public let client: ChilltraxClient
    public let historyStore: CompressedHistoryStore
    public private(set) var minimumHistoryPlayDuration: TimeInterval
    private let defaults: UserDefaults
    private let startPollingAutomatically: Bool
    private var metadataPollingTask: Task<Void, Never>?
    private var pendingHistoryTask: Task<Void, Never>?
    private var currentSongPlayStartDate: Date?
    private var currentSongAccumulatedPlayTime: TimeInterval = 0
    private var hasRecordedCurrentSongInHistory: Bool = false
    private var wasActivelyPlayingForHistory: Bool = false
    private var cancellables = Set<AnyCancellable>()
    private var hasReceivedInitialMetadata = false

    public var filteredHistoryEntries: [SongHistoryEntry] {
        guard !historySearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return historyEntries
        }
        return historyEntries.filter { $0.matches(searchQuery: historySearchQuery) }
    }

    public var allAvailableStreams: [StationStream] {
        var combined = discoveredStreams
        for custom in customStreams where !combined.contains(where: { $0.urlString.caseInsensitiveCompare(custom.urlString) == .orderedSame }) {
            combined.append(custom)
        }
        return combined
    }

    public init(
        client: ChilltraxClient = ChilltraxClient(),
        historyStore: CompressedHistoryStore = CompressedHistoryStore(),
        radioPlayer: RadioPlayer? = nil,
        defaults: UserDefaults = .standard,
        startPollingAutomatically: Bool = true,
        minimumHistoryPlayDuration: TimeInterval? = nil
    ) {
        self.client = client
        self.historyStore = historyStore
        self.radioPlayer = radioPlayer ?? RadioPlayer()
        self.defaults = defaults
        self.startPollingAutomatically = startPollingAutomatically

        let initialDelaySeconds: Int
        if defaults.object(forKey: DefaultsKeys.historyCommitDelaySeconds) != nil {
            initialDelaySeconds = min(99, max(0, defaults.integer(forKey: DefaultsKeys.historyCommitDelaySeconds)))
        } else if let minimumHistoryPlayDuration {
            initialDelaySeconds = min(99, max(0, Int(minimumHistoryPlayDuration.rounded())))
        } else {
            initialDelaySeconds = 10
        }
        self.historyCommitDelaySeconds = initialDelaySeconds
        if let minimumHistoryPlayDuration {
            self.minimumHistoryPlayDuration = min(99.0, max(0.0, minimumHistoryPlayDuration))
        } else {
            self.minimumHistoryPlayDuration = TimeInterval(initialDelaySeconds)
        }

        // Load persisted settings
        let initialDiscovered: [StationStream]
        if let rawDiscovered = defaults.data(forKey: DefaultsKeys.discoveredStreams),
           let decoded = try? JSONDecoder().decode([StationStream].self, from: rawDiscovered),
           !decoded.isEmpty {
            initialDiscovered = decoded
        } else {
            initialDiscovered = StationStream.defaultChilltraxStreams
        }
        self.discoveredStreams = initialDiscovered

        let initialCustom: [StationStream]
        if let rawCustom = defaults.data(forKey: DefaultsKeys.customStreams),
           let decoded = try? JSONDecoder().decode([StationStream].self, from: rawCustom) {
            initialCustom = decoded
        } else {
            initialCustom = []
        }
        self.customStreams = initialCustom

        let savedURL = defaults.string(forKey: DefaultsKeys.selectedStreamURL)
        let savedName = defaults.string(forKey: DefaultsKeys.selectedStreamName)
        if let savedURL, !savedURL.isEmpty {
            let matching = (initialDiscovered + initialCustom).first {
                $0.urlString.caseInsensitiveCompare(savedURL) == .orderedSame
            }
            self.selectedStream = matching ?? StationStream(
                name: savedName ?? "Custom Station",
                urlString: savedURL,
                formatDetails: "Custom URL",
                isChilltraxOfficial: savedURL.lowercased().contains("chilltrax") || savedURL.lowercased().contains("electronicmusicradiogroup")
            )
        } else {
            self.selectedStream = .defaultStream
        }

        if let modeRaw = defaults.string(forKey: DefaultsKeys.visualizerMode),
           let mode = VisualizerMode(rawValue: modeRaw) {
            self.visualizerMode = mode
        } else {
            self.visualizerMode = .bars
        }

        if defaults.object(forKey: DefaultsKeys.notifyOnSongChange) != nil {
            self.notifyOnSongChange = defaults.bool(forKey: DefaultsKeys.notifyOnSongChange)
        } else {
            self.notifyOnSongChange = true
        }

        if defaults.object(forKey: DefaultsKeys.fetchAlbumCoverFromChilltrax) != nil {
            self.fetchAlbumCoverFromChilltrax = defaults.bool(forKey: DefaultsKeys.fetchAlbumCoverFromChilltrax)
        } else {
            self.fetchAlbumCoverFromChilltrax = true
        }

        if defaults.object(forKey: DefaultsKeys.isHistoryExpanded) != nil {
            self.isHistoryExpanded = defaults.bool(forKey: DefaultsKeys.isHistoryExpanded)
        } else {
            self.isHistoryExpanded = false
        }

        // Load compressed song history from disk
        self.historyEntries = historyStore.load()

        // Forward nested RadioPlayer objectWillChange so SwiftUI views observing AppState stay in sync
        self.radioPlayer.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(self.radioPlayer.$isPlaying, self.radioPlayer.$status)
            .sink { [weak self] isPlaying, status in
                self?.handlePlaybackActivityChange(isPlaying: isPlaying, status: status)
            }
            .store(in: &cancellables)

        self.radioPlayer.onICYMetadataReceived = { [weak self] icyMetadata in
            guard let self, self.radioPlayer.isPlaying else { return }
            self.handleIncomingSongMetadata(icyMetadata, sourceIsICY: true)
        }
    }

    // MARK: - Playback Controls

    public func togglePlayPause() {
        if radioPlayer.isPlaying {
            radioPlayer.pause()
        } else {
            playSelectedStream()
        }
    }

    public func playSelectedStream() {
        guard let rawURL = selectedStream.url else { return }
        Task {
            let playableURL = await client.resolvePlayableStreamURL(for: rawURL)
            radioPlayer.play(url: playableURL)
            await refreshNowPlayingMetadata()
        }
    }

    public func selectStream(_ stream: StationStream, autoPlayIfCurrentlyPlaying: Bool = true) {
        let wasPlaying = radioPlayer.isPlaying
        selectedStream = stream
        if wasPlaying && autoPlayIfCurrentlyPlaying {
            radioPlayer.stop()
            playSelectedStream()
        }
    }

    public func addAndSelectCustomStream(name: String, urlString: String) -> Bool {
        let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty,
              let url = URL(string: trimmedURL),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmedName.isEmpty ? (url.host ?? "Custom Station") : trimmedName
        let isChilltrax = trimmedURL.lowercased().contains("chilltrax")
            || trimmedURL.lowercased().contains("electronicmusicradiogroup")

        let custom = StationStream(
            id: trimmedURL,
            name: resolvedName,
            urlString: trimmedURL,
            formatDetails: "Custom Stream URL",
            isChilltraxOfficial: isChilltrax
        )

        if let index = customStreams.firstIndex(where: { $0.urlString.caseInsensitiveCompare(trimmedURL) == .orderedSame }) {
            customStreams[index] = custom
        } else {
            customStreams.insert(custom, at: 0)
        }

        selectStream(custom)
        return true
    }

    public func removeCustomStream(_ stream: StationStream) {
        customStreams.removeAll { $0.id == stream.id }
        if selectedStream.id == stream.id {
            selectStream(discoveredStreams.first ?? .defaultStream)
        }
    }

    public func toggleVisualizerMode() {
        visualizerMode = visualizerMode == .bars ? .waveform : .bars
    }

    public func toggleHistoryExpanded() {
        isHistoryExpanded.toggle()
    }

    private func updateHistoryExpansionForSearch(previousQuery: String) {
        let trimmed = historySearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let previousTrimmed = previousQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let hasResults = !filteredHistoryEntries.isEmpty
            if isHistoryExpanded != hasResults {
                isHistoryExpanded = hasResults
            }
        } else if !previousTrimmed.isEmpty {
            if isHistoryExpanded {
                isHistoryExpanded = false
            }
        }
    }

    // MARK: - Broadcast Discovery from chilltrax.com

    public func discoverBroadcastsFromChilltraxWebsite() async {
        isDiscoveringBroadcasts = true
        discoveryStatusMessage = "Scanning chilltrax.com for broadcast streams…"
        defer { isDiscoveringBroadcasts = false }

        do {
            let found = try await client.discoverBroadcastStreamsFromWebsite()
            discoveredStreams = found
            discoveryStatusMessage = "Found \(found.count) broadcast streams on chilltrax.com."
            // Ensure current selection stays valid or updated
            if let updatedMatch = found.first(where: { $0.urlString.caseInsensitiveCompare(selectedStream.urlString) == .orderedSame }) {
                selectedStream = updatedMatch
            }
        } catch {
            if discoveredStreams.isEmpty {
                discoveredStreams = StationStream.defaultChilltraxStreams
            }
            discoveryStatusMessage = "Could not reach chilltrax.com (\(error.localizedDescription)). Showing built-in Chilltrax streams."
        }
    }

    // MARK: - Song Metadata, Album Cover & History Recording

    public func startMetadataPolling() {
        metadataPollingTask?.cancel()
        guard radioPlayer.isPlaying else {
            metadataPollingTask = nil
            return
        }
        metadataPollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled && self.radioPlayer.isPlaying {
                try? await Task.sleep(nanoseconds: 10_000_000_000) // Poll every 10s while playing
                if Task.isCancelled || !self.radioPlayer.isPlaying { break }
                await self.refreshNowPlayingMetadata()
            }
        }
    }

    public func stopMetadataPolling() {
        metadataPollingTask?.cancel()
        metadataPollingTask = nil
    }

    public func refreshNowPlayingMetadata() async {
        guard radioPlayer.isPlaying else { return }
        // When streaming an official Chilltrax stream (or when no custom ICY metadata has overridden it),
        // fetch live track details from chilltrax.com
        let shouldQueryChilltraxSongInfo = selectedStream.isChilltraxOfficial
        if shouldQueryChilltraxSongInfo {
            do {
                let metadata = try await client.fetchNowPlaying(fetchAlbumCover: fetchAlbumCoverFromChilltrax)
                guard radioPlayer.isPlaying else { return }
                handleIncomingSongMetadata(metadata, sourceIsICY: false)
            } catch {
                // Keep existing metadata on transient failure
            }
        } else if fetchAlbumCoverFromChilltrax && currentSong.coverURLString == nil {
            if let cover = try? await client.fetchCurrentAlbumCoverURLString() {
                guard radioPlayer.isPlaying else { return }
                var updated = currentSong
                updated.coverURLString = cover
                currentSong = updated
                if hasRecordedCurrentSongInHistory {
                    historyEntries = historyStore.recordSong(updated, station: selectedStream, existingEntries: historyEntries)
                }
            }
        }
    }

    private var isActivelyPlayingForHistory: Bool {
        radioPlayer.isPlaying && radioPlayer.status != .paused && radioPlayer.status != .error
    }

    private func handlePlaybackActivityChange(isPlaying: Bool, status: RadioPlayer.PlaybackStatus) {
        let isActiveNow = isPlaying && status != .paused && status != .error
        guard isActiveNow != wasActivelyPlayingForHistory else { return }
        wasActivelyPlayingForHistory = isActiveNow

        if isActiveNow {
            currentSongPlayStartDate = Date()
            if startPollingAutomatically {
                startMetadataPolling()
            }
            scheduleHistoryRecordingIfNeeded()
        } else {
            stopMetadataPolling()
            if let start = currentSongPlayStartDate {
                currentSongAccumulatedPlayTime += max(0, Date().timeIntervalSince(start))
                currentSongPlayStartDate = nil
            }
            pendingHistoryTask?.cancel()
            pendingHistoryTask = nil
            if !isPlaying {
                currentSong = .placeholder
                currentSongAccumulatedPlayTime = 0
                hasRecordedCurrentSongInHistory = false
            }
        }
    }

    private func scheduleHistoryRecordingIfNeeded() {
        guard !hasRecordedCurrentSongInHistory,
              currentSong.isMeaningfulTrack,
              isActivelyPlayingForHistory else {
            return
        }

        let currentSegment = currentSongPlayStartDate.map { max(0, Date().timeIntervalSince($0)) } ?? 0
        let totalPlayed = currentSongAccumulatedPlayTime + currentSegment
        let remaining = max(0, minimumHistoryPlayDuration - totalPlayed)

        pendingHistoryTask?.cancel()
        pendingHistoryTask = nil

        if remaining <= 0 {
            commitCurrentSongToHistory()
            return
        }

        let targetKey = currentSong.normalizedKey
        let sleepNanoseconds = UInt64((remaining * 1_000_000_000).rounded(.up))
        pendingHistoryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: sleepNanoseconds)
            guard !Task.isCancelled, let self else { return }
            guard self.isActivelyPlayingForHistory,
                  self.currentSong.normalizedKey == targetKey,
                  !self.hasRecordedCurrentSongInHistory else {
                return
            }
            self.commitCurrentSongToHistory()
        }
    }

    private func commitCurrentSongToHistory() {
        guard currentSong.isMeaningfulTrack else { return }
        hasRecordedCurrentSongInHistory = true
        pendingHistoryTask = nil
        historyEntries = historyStore.recordSong(
            currentSong,
            station: selectedStream,
            existingEntries: historyEntries
        )
        if !historySearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updateHistoryExpansionForSearch(previousQuery: historySearchQuery)
        }
    }

    public func handleIncomingSongMetadata(_ incoming: SongMetadata, sourceIsICY: Bool) {
        guard radioPlayer.isPlaying, incoming.isMeaningfulTrack else { return }

        // If we are on an official Chilltrax stream and receive bare ICY metadata, preserve the richer
        // Chilltrax album/mix/cover fields if it's the same track
        var merged = incoming
        if merged.normalizedKey == currentSong.normalizedKey {
            if merged.albumOrMix.isEmpty { merged.albumOrMix = currentSong.albumOrMix }
            if merged.year.isEmpty { merged.year = currentSong.year }
            if merged.buyURLString.isEmpty { merged.buyURLString = currentSong.buyURLString }
            if merged.coverURLString == nil { merged.coverURLString = currentSong.coverURLString }
        }
        if !fetchAlbumCoverFromChilltrax {
            merged.coverURLString = nil
        }

        let previousKey = currentSong.normalizedKey
        let isNewTrack = previousKey != merged.normalizedKey
        let isActivelyPlaying = isActivelyPlayingForHistory
        let shouldNotify = isNewTrack && hasReceivedInitialMetadata && notifyOnSongChange && isActivelyPlaying

        currentSong = merged
        hasReceivedInitialMetadata = true

        if isNewTrack {
            pendingHistoryTask?.cancel()
            pendingHistoryTask = nil
            currentSongAccumulatedPlayTime = 0
            hasRecordedCurrentSongInHistory = false
            currentSongPlayStartDate = isActivelyPlaying ? Date() : nil
            if isActivelyPlaying {
                scheduleHistoryRecordingIfNeeded()
            }
        } else if hasRecordedCurrentSongInHistory {
            // Enrich already-recorded entry with any newly arrived cover/album metadata
            historyEntries = historyStore.recordSong(
                merged,
                station: selectedStream,
                existingEntries: historyEntries
            )
            if !historySearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                updateHistoryExpansionForSearch(previousQuery: historySearchQuery)
            }
        } else if isActivelyPlaying && pendingHistoryTask == nil {
            scheduleHistoryRecordingIfNeeded()
        }

        if shouldNotify {
            SongNotificationManager.shared.sendSongChangeNotification(
                song: merged,
                stationName: selectedStream.name
            )
        }

        // If a song change was detected via ICY stream title and Chilltrax metadata/cover is enabled,
        // immediately trigger a background fetch for the updated cover art / details
        if sourceIsICY && isNewTrack && (selectedStream.isChilltraxOfficial || fetchAlbumCoverFromChilltrax) {
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                await self?.refreshNowPlayingMetadata()
            }
        }
    }

    public func clearHistory() {
        pendingHistoryTask?.cancel()
        pendingHistoryTask = nil
        historyEntries = []
        historyStore.save([])
    }

    private func refreshCoverArtForSettingChange() async {
        if fetchAlbumCoverFromChilltrax {
            guard radioPlayer.isPlaying else { return }
            if let cover = try? await client.fetchCurrentAlbumCoverURLString() {
                guard radioPlayer.isPlaying else { return }
                var updated = currentSong
                updated.coverURLString = cover
                currentSong = updated
                if hasRecordedCurrentSongInHistory {
                    historyEntries = historyStore.recordSong(updated, station: selectedStream, existingEntries: historyEntries)
                }
            }
        } else {
            var updated = currentSong
            updated.coverURLString = nil
            currentSong = updated
        }
    }
}
