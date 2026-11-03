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
    private let defaults: UserDefaults
    private var metadataPollingTask: Task<Void, Never>?
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
        startPollingAutomatically: Bool = true
    ) {
        self.client = client
        self.historyStore = historyStore
        self.radioPlayer = radioPlayer ?? RadioPlayer()
        self.defaults = defaults

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

        self.radioPlayer.onICYMetadataReceived = { [weak self] icyMetadata in
            guard let self else { return }
            self.handleIncomingSongMetadata(icyMetadata, sourceIsICY: true)
        }

        if startPollingAutomatically {
            startMetadataPolling()
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
        metadataPollingTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshNowPlayingMetadata()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000) // Poll every 10s
                if Task.isCancelled { break }
                await self.refreshNowPlayingMetadata()
            }
        }
    }

    public func refreshNowPlayingMetadata() async {
        // When streaming an official Chilltrax stream (or when no custom ICY metadata has overridden it),
        // fetch live track details from chilltrax.com
        let shouldQueryChilltraxSongInfo = selectedStream.isChilltraxOfficial
        if shouldQueryChilltraxSongInfo {
            do {
                let metadata = try await client.fetchNowPlaying(fetchAlbumCover: fetchAlbumCoverFromChilltrax)
                handleIncomingSongMetadata(metadata, sourceIsICY: false)
            } catch {
                // Keep existing metadata on transient failure
            }
        } else if fetchAlbumCoverFromChilltrax && currentSong.coverURLString == nil {
            if let cover = try? await client.fetchCurrentAlbumCoverURLString() {
                var updated = currentSong
                updated.coverURLString = cover
                currentSong = updated
                historyEntries = historyStore.recordSong(updated, station: selectedStream, existingEntries: historyEntries)
            }
        }
    }

    public func handleIncomingSongMetadata(_ incoming: SongMetadata, sourceIsICY: Bool) {
        guard incoming.isMeaningfulTrack else { return }

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
        let isActivelyPlaying = radioPlayer.isPlaying && radioPlayer.status != .paused
        let shouldNotify = isNewTrack && hasReceivedInitialMetadata && notifyOnSongChange && isActivelyPlaying

        currentSong = merged
        hasReceivedInitialMetadata = true

        // Record in compressed local history store
        historyEntries = historyStore.recordSong(
            merged,
            station: selectedStream,
            existingEntries: historyEntries
        )
        if !historySearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updateHistoryExpansionForSearch(previousQuery: historySearchQuery)
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
        historyEntries = []
        historyStore.save([])
    }

    private func refreshCoverArtForSettingChange() async {
        if fetchAlbumCoverFromChilltrax {
            if let cover = try? await client.fetchCurrentAlbumCoverURLString() {
                var updated = currentSong
                updated.coverURLString = cover
                currentSong = updated
                historyEntries = historyStore.recordSong(updated, station: selectedStream, existingEntries: historyEntries)
            }
        } else {
            var updated = currentSong
            updated.coverURLString = nil
            currentSong = updated
        }
    }
}
