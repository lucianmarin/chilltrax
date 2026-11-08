import Foundation
import SwiftUI
import AppKit
import Combine

@MainActor
public final class AppState: ObservableObject {
    private enum DefaultsKeys {
        static let selectedStation = "chilltrax.selectedStation"
        static let selectedStreamURL = "chilltrax.selectedStreamURL"
        static let selectedStreamName = "chilltrax.selectedStreamName"
        static let customStreams = "chilltrax.customStreams"
        static let discoveredStreams = "chilltrax.discoveredStreams"
        static let stationAPIEndpoints = "chilltrax.stationAPIEndpoints"
        static let visualizerMode = "chilltrax.visualizerMode"
        static let lastActiveVisualizerMode = "chilltrax.lastActiveVisualizerMode"
        static let notifyOnSongChange = "chilltrax.notifyOnSongChange"
        static let fetchAlbumCoverFromChilltrax = "chilltrax.fetchAlbumCoverFromChilltrax"
        static let isHistoryExpanded = "chilltrax.isHistoryExpanded"
        static let historyCommitDelaySeconds = "chilltrax.historyCommitDelaySeconds"
    }

    // MARK: - Published UI & Player State

    @Published public var currentSong: SongMetadata = .placeholder
    @Published public var selectedStation: RadioStation = .chilltrax {
        didSet {
            defaults.set(selectedStation.rawValue, forKey: DefaultsKeys.selectedStation)
        }
    }
    @Published public var selectedStream: StationStream {
        didSet {
            defaults.set(selectedStream.urlString, forKey: DefaultsKeys.selectedStreamURL)
            defaults.set(selectedStream.name, forKey: DefaultsKeys.selectedStreamName)
            if selectedStation != selectedStream.station {
                selectedStation = selectedStream.station
            }
        }
    }
    @Published public var discoveredStreams: [StationStream] = StationStream.defaultAllStreams {
        didSet {
            if let encoded = try? JSONEncoder().encode(discoveredStreams) {
                defaults.set(encoded, forKey: DefaultsKeys.discoveredStreams)
            }
        }
    }
    @Published public var stationAPIEndpoints: [RadioStation: StationAPIEndpoints] {
        didSet {
            if let encoded = try? JSONEncoder().encode(stationAPIEndpoints) {
                defaults.set(encoded, forKey: DefaultsKeys.stationAPIEndpoints)
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
            if visualizerMode.isVisible {
                lastActiveVisualizerMode = visualizerMode
                defaults.set(visualizerMode.rawValue, forKey: DefaultsKeys.lastActiveVisualizerMode)
            }
        }
    }
    private var lastActiveVisualizerMode: VisualizerMode = .spectrum
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
            }
        }
    }
    nonisolated public static let historyPageSize = 50

    @Published public var isHistoryExpanded: Bool {
        didSet {
            defaults.set(isHistoryExpanded, forKey: DefaultsKeys.isHistoryExpanded)
            if !isUpdatingExpansionFromSearch {
                isHistoryManuallyExpanded = isHistoryExpanded
            }
            if !isHistoryExpanded {
                visibleHistoryLimit = Self.historyPageSize
            }
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
            visibleHistoryLimit = Self.historyPageSize
            updateHistoryExpansionForSearch(previousQuery: oldValue)
        }
    }
    @Published public private(set) var visibleHistoryLimit: Int = AppState.historyPageSize
    @Published public private(set) var historyEntries: [SongHistoryEntry] = []
    @Published public private(set) var copiedHistoryEntryID: UUID? = nil
    private var copiedCurrentSongNormalizedKey: String? = nil
    @Published public private(set) var isDiscoveringBroadcasts: Bool = false
    @Published public private(set) var discoveryStatusMessage: String?

    public let radioPlayer: RadioPlayer
    public let client: ChilltraxClient
    public let historyStore: CompressedHistoryStore
    public let coverCache: AlbumCoverCache
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
    private var isUpdatingExpansionFromSearch = false
    private var isHistoryManuallyExpanded = false

    public var filteredHistoryEntries: [SongHistoryEntry] {
        guard !historySearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return historyEntries
        }
        return historyEntries.filter { $0.matches(searchQuery: historySearchQuery) }
    }

    public var displayedHistoryEntries: [SongHistoryEntry] {
        Array(filteredHistoryEntries.prefix(visibleHistoryLimit))
    }

    public var hasMoreHistoryEntries: Bool {
        filteredHistoryEntries.count > visibleHistoryLimit
    }

    public var isSearchBarVisible: Bool {
        isHistoryExpanded
    }

    public var isHistoryButtonHighlighted: Bool {
        let hasSearchResults = !historySearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !filteredHistoryEntries.isEmpty
        return isHistoryExpanded || hasSearchResults
    }

    @discardableResult
    public func copyHistoryEntryToClipboard(_ entry: SongHistoryEntry) -> String {
        copiedHistoryEntryID = entry.id
        copiedCurrentSongNormalizedKey = nil
        let text = entry.clipboardText
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        return text
    }

    public func historyBadgeLabel(for entry: SongHistoryEntry) -> String {
        copiedHistoryEntryID == entry.id ? "COPY" : entry.stationBadgeLabel
    }

    public func loadMoreHistoryIfNeeded(currentEntry: SongHistoryEntry? = nil) {
        let total = filteredHistoryEntries.count
        guard total > visibleHistoryLimit else { return }
        if let currentEntry {
            let currentDisplayed = displayedHistoryEntries
            let thresholdIndex = max(0, currentDisplayed.count - 5)
            guard let index = currentDisplayed.firstIndex(where: { $0.id == currentEntry.id }),
                  index >= thresholdIndex else {
                return
            }
        }
        visibleHistoryLimit = min(total, visibleHistoryLimit + Self.historyPageSize)
    }

    public var streamsForSelectedStation: [StationStream] {
        let filtered = discoveredStreams.filter { $0.station == selectedStation }
        return filtered.isEmpty ? selectedStation.defaultStreams : filtered
    }

    public var currentStationAPIEndpoints: StationAPIEndpoints {
        stationAPIEndpoints[selectedStation] ?? selectedStation.defaultAPIEndpoints
    }

    public var toolbarStatusLabel: String {
        radioPlayer.status.toolbarLabel(for: selectedStation)
    }

    public var canSwitchStationFromToolbarStatus: Bool {
        radioPlayer.status == .playing
    }

    public var currentSongFormattedTitle: String? {
        guard radioPlayer.isPlaying, currentSong.isMeaningfulTrack else {
            return nil
        }
        let text = currentSong.clipboardText.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    public var canCopyCurrentSongToClipboard: Bool {
        currentSongFormattedTitle != nil
    }

    @discardableResult
    public func copyCurrentSongToClipboard() -> String? {
        guard let text = currentSongFormattedTitle else { return nil }
        copiedCurrentSongNormalizedKey = currentSong.normalizedKey
        copiedHistoryEntryID = historyEntries.first(where: { $0.normalizedKey == currentSong.normalizedKey })?.id
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        return text
    }

    public var canOpenCurrentSongOnAppleMusic: Bool {
        currentSongAppleMusicURL != nil
    }

    public var currentSongAppleMusicURL: URL? {
        guard radioPlayer.isPlaying, currentSong.isMeaningfulTrack else {
            return nil
        }
        if let buyURL = currentSong.buyURL {
            return buyURL
        }
        let query = [currentSong.artist, currentSong.title]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !query.isEmpty,
              let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        return URL(string: "https://music.apple.com/us/search?term=\(encoded)")
    }

    @discardableResult
    public func openCurrentSongOnAppleMusic(openURL: (URL) -> Bool = { NSWorkspace.shared.open($0) }) -> URL? {
        guard let url = currentSongAppleMusicURL else { return nil }
        _ = openURL(url)
        return url
    }

    public var allAvailableStreams: [StationStream] {
        var combined = streamsForSelectedStation
        for custom in customStreams where !combined.contains(where: { $0.urlString.caseInsensitiveCompare(custom.urlString) == .orderedSame }) {
            combined.append(custom)
        }
        return combined
    }

    public init(
        client: ChilltraxClient = ChilltraxClient(),
        historyStore: CompressedHistoryStore = CompressedHistoryStore(),
        coverCache: AlbumCoverCache? = nil,
        radioPlayer: RadioPlayer? = nil,
        defaults: UserDefaults = .standard,
        startPollingAutomatically: Bool = true,
        minimumHistoryPlayDuration: TimeInterval? = nil
    ) {
        self.client = client
        self.historyStore = historyStore
        self.coverCache = coverCache ?? AlbumCoverCache(client: client)
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
        var initialDiscovered: [StationStream]
        if let rawDiscovered = defaults.data(forKey: DefaultsKeys.discoveredStreams),
           let decoded = try? JSONDecoder().decode([StationStream].self, from: rawDiscovered),
           !decoded.isEmpty {
            initialDiscovered = decoded
        } else {
            initialDiscovered = StationStream.defaultAllStreams
        }
        for station in RadioStation.allCases where !initialDiscovered.contains(where: { $0.station == station }) {
            initialDiscovered.append(contentsOf: station.defaultStreams)
        }
        self.discoveredStreams = initialDiscovered

        var defaultEndpoints: [RadioStation: StationAPIEndpoints] = [:]
        for station in RadioStation.allCases {
            defaultEndpoints[station] = station.defaultAPIEndpoints
        }
        if let rawEndpoints = defaults.data(forKey: DefaultsKeys.stationAPIEndpoints),
           let decoded = try? JSONDecoder().decode([RadioStation: StationAPIEndpoints].self, from: rawEndpoints) {
            for (station, endpoints) in decoded {
                defaultEndpoints[station] = endpoints
            }
        }
        self.stationAPIEndpoints = defaultEndpoints

        let initialCustom: [StationStream]
        if let rawCustom = defaults.data(forKey: DefaultsKeys.customStreams),
           let decoded = try? JSONDecoder().decode([StationStream].self, from: rawCustom) {
            initialCustom = decoded
        } else {
            initialCustom = []
        }
        self.customStreams = initialCustom

        let savedStationRaw = defaults.string(forKey: DefaultsKeys.selectedStation)
        let savedStation = savedStationRaw.flatMap(RadioStation.init(rawValue:))
        let savedURL = defaults.string(forKey: DefaultsKeys.selectedStreamURL)
        let savedName = defaults.string(forKey: DefaultsKeys.selectedStreamName)
        if let savedURL, !savedURL.isEmpty {
            let matching = (initialDiscovered + initialCustom).first {
                $0.urlString.caseInsensitiveCompare(savedURL) == .orderedSame
            }
            let resolvedStream = matching ?? StationStream(
                name: savedName ?? "Chilltrax",
                urlString: savedURL,
                formatDetails: "Live Stream",
                isChilltraxOfficial: true,
                station: savedStation
            )
            self.selectedStation = savedStation ?? resolvedStream.station
            self.selectedStream = resolvedStream
        } else {
            let station = savedStation ?? .chilltrax
            self.selectedStation = station
            self.selectedStream = StationStream.preferredDefaultStream(for: station, in: initialDiscovered)
        }

        if let lastActiveRaw = defaults.string(forKey: DefaultsKeys.lastActiveVisualizerMode),
           let lastActive = VisualizerMode(persistedRawValue: lastActiveRaw),
           lastActive.isVisible {
            self.lastActiveVisualizerMode = lastActive
        } else {
            self.lastActiveVisualizerMode = .spectrum
        }

        if let modeRaw = defaults.string(forKey: DefaultsKeys.visualizerMode),
           let mode = VisualizerMode(persistedRawValue: modeRaw) {
            self.visualizerMode = mode
            if mode.isVisible {
                self.lastActiveVisualizerMode = mode
            }
        } else {
            self.visualizerMode = .spectrum
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

        let initialHistoryExpanded: Bool
        if defaults.object(forKey: DefaultsKeys.isHistoryExpanded) != nil {
            initialHistoryExpanded = defaults.bool(forKey: DefaultsKeys.isHistoryExpanded)
        } else {
            initialHistoryExpanded = false
        }
        self.isHistoryExpanded = initialHistoryExpanded
        self.isHistoryManuallyExpanded = initialHistoryExpanded

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

    public func selectStation(_ station: RadioStation, autoPlayIfCurrentlyPlaying: Bool = true) {
        guard selectedStation != station || selectedStream.station != station else { return }
        selectedStation = station
        let targetStream = StationStream.preferredDefaultStream(for: station, in: discoveredStreams)
        if radioPlayer.isPlaying {
            currentSong = .placeholder
            pendingHistoryTask?.cancel()
            pendingHistoryTask = nil
            currentSongAccumulatedPlayTime = 0
            hasRecordedCurrentSongInHistory = false
        }
        selectStream(targetStream, autoPlayIfCurrentlyPlaying: autoPlayIfCurrentlyPlaying)
    }

    public func toggleStation(autoPlayIfCurrentlyPlaying: Bool = true) {
        selectStation(selectedStation.nextStation, autoPlayIfCurrentlyPlaying: autoPlayIfCurrentlyPlaying)
    }

    @discardableResult
    public func handleToolbarStatusTap(
        autoPlayIfCurrentlyPlaying: Bool = true,
        openSettings: () -> Void
    ) -> Bool {
        if canSwitchStationFromToolbarStatus {
            toggleStation(autoPlayIfCurrentlyPlaying: autoPlayIfCurrentlyPlaying)
            return true
        } else {
            openSettings()
            return false
        }
    }

    public func selectStream(_ stream: StationStream, autoPlayIfCurrentlyPlaying: Bool = true) {
        let wasPlaying = radioPlayer.isPlaying
        let stationChanged = selectedStation != stream.station
        selectedStation = stream.station
        selectedStream = stream
        if stationChanged && wasPlaying {
            currentSong = .placeholder
            pendingHistoryTask?.cancel()
            pendingHistoryTask = nil
            currentSongAccumulatedPlayTime = 0
            hasRecordedCurrentSongInHistory = false
        }
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
            selectStream(StationStream.preferredDefaultStream(for: selectedStation, in: discoveredStreams))
        }
    }

    public var isVisualizerVisible: Bool {
        visualizerMode.isVisible
    }

    public func toggleVisualizerVisibility() {
        if visualizerMode.isVisible {
            visualizerMode = .off
        } else {
            visualizerMode = lastActiveVisualizerMode.isVisible ? lastActiveVisualizerMode : .spectrum
        }
    }

    public func toggleVisualizerMode() {
        switch visualizerMode {
        case .spectrum:
            visualizerMode = .waveform
        case .waveform:
            visualizerMode = .spectrum
        case .off:
            visualizerMode = lastActiveVisualizerMode.isVisible ? lastActiveVisualizerMode : .spectrum
        }
    }

    public func toggleHistoryExpanded() {
        isHistoryExpanded.toggle()
    }

    public func toggleAlbumCovers() {
        fetchAlbumCoverFromChilltrax.toggle()
    }

    private func updateHistoryExpansionForSearch(previousQuery: String) {
        guard !isHistoryManuallyExpanded else { return }
        isUpdatingExpansionFromSearch = true
        defer { isUpdatingExpansionFromSearch = false }
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

    // MARK: - Broadcast & API Discovery from chilltrax.com and radiodanz.com

    public func discoverBroadcastsFromChilltraxWebsite() async {
        isDiscoveringBroadcasts = true
        discoveryStatusMessage = "Scanning chilltrax.com and radiodanz.com for broadcasts and API URLs…"
        defer { isDiscoveringBroadcasts = false }

        do {
            let results = try await client.discoverAllStationsConfiguration(
                previousEndpointsByStation: stationAPIEndpoints
            )

            var combinedStreams: [StationStream] = []
            var updatedEndpoints = stationAPIEndpoints
            var updatedAPISites: [String] = []

            for station in RadioStation.allCases {
                if let result = results[station] {
                    combinedStreams.append(contentsOf: result.streams)
                    updatedEndpoints[station] = result.apiEndpoints
                    if result.didChangeAPIEndpoints {
                        updatedAPISites.append(station.domain)
                    }
                } else {
                    let existing = discoveredStreams.filter { $0.station == station }
                    combinedStreams.append(contentsOf: existing.isEmpty ? station.defaultStreams : existing)
                }
            }

            discoveredStreams = combinedStreams
            stationAPIEndpoints = updatedEndpoints

            let chilltraxCount = results[.chilltrax]?.streams.count ?? 0
            let danzCount = results[.radioDanz]?.streams.count ?? 0
            let apiSummary: String
            if updatedAPISites.isEmpty {
                apiSummary = "API URLs verified."
            } else {
                apiSummary = "Updated API URLs for \(updatedAPISites.joined(separator: ", "))."
            }
            discoveryStatusMessage = "Found \(chilltraxCount) Chilltrax and \(danzCount) Radio Danz broadcasts. \(apiSummary)"

            // Ensure current selection stays valid or updated
            if let updatedMatch = combinedStreams.first(where: { $0.urlString.caseInsensitiveCompare(selectedStream.urlString) == .orderedSame }) {
                selectedStream = updatedMatch
            } else if !combinedStreams.contains(where: { $0.station == selectedStation && $0.id == selectedStream.id }) {
                selectedStream = StationStream.preferredDefaultStream(for: selectedStation, in: streamsForSelectedStation)
            }
        } catch {
            if discoveredStreams.isEmpty {
                discoveredStreams = StationStream.defaultAllStreams
            }
            discoveryStatusMessage = "Could not reach station websites (\(error.localizedDescription)). Showing built-in streams."
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
        let activeStation = selectedStation
        let endpoints = stationAPIEndpoints[activeStation] ?? activeStation.defaultAPIEndpoints
        let shouldQueryStationSongInfo = selectedStream.isChilltraxOfficial
        if shouldQueryStationSongInfo {
            do {
                let metadata = try await client.fetchNowPlaying(
                    station: activeStation,
                    endpoints: endpoints,
                    fetchAlbumCover: fetchAlbumCoverFromChilltrax
                )
                guard radioPlayer.isPlaying, selectedStation == activeStation else { return }
                handleIncomingSongMetadata(metadata, sourceIsICY: false)
            } catch {
                // Keep existing metadata on transient failure
            }
        } else if fetchAlbumCoverFromChilltrax && currentSong.coverURLString == nil {
            if let cover = try? await client.fetchCurrentAlbumCoverURLString(
                station: activeStation,
                endpoints: endpoints
            ) {
                guard radioPlayer.isPlaying, selectedStation == activeStation else { return }
                var updated = currentSong
                updated.coverURLString = cover
                currentSong = updated
                cacheAlbumCoverForHistoryItem(updated.coverURL)
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
        if copiedCurrentSongNormalizedKey == currentSong.normalizedKey,
           let matchingEntry = historyEntries.first(where: { $0.normalizedKey == currentSong.normalizedKey }) {
            copiedHistoryEntryID = matchingEntry.id
        }
        cacheAlbumCoverForHistoryItem(currentSong.coverURL)
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
        } else if !fetchAlbumCoverFromChilltrax {
            merged.coverURLString = nil
        }

        let previousKey = currentSong.normalizedKey
        let isNewTrack = previousKey != merged.normalizedKey
        let isActivelyPlaying = isActivelyPlayingForHistory
        let shouldNotify = isNewTrack && hasReceivedInitialMetadata && notifyOnSongChange && isActivelyPlaying

        currentSong = merged
        hasReceivedInitialMetadata = true
        cacheAlbumCoverForHistoryItem(merged.coverURL)

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
            cacheAlbumCoverForHistoryItem(merged.coverURL)
            if !historySearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                updateHistoryExpansionForSearch(previousQuery: historySearchQuery)
            }
        } else if isActivelyPlaying && pendingHistoryTask == nil {
            scheduleHistoryRecordingIfNeeded()
        }

        if shouldNotify {
            SongNotificationManager.shared.sendSongChangeNotification(
                song: merged,
                stationName: selectedStation.title
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
        copiedHistoryEntryID = nil
        historyStore.save([])
        coverCache.clearAll()
    }

    private func cacheAlbumCoverForHistoryItem(_ coverURL: URL?) {
        guard fetchAlbumCoverFromChilltrax, let coverURL else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.coverCache.cacheCoverIfNeeded(for: coverURL)
            self.objectWillChange.send()
        }
    }

    private func refreshCoverArtForSettingChange() async {
        guard fetchAlbumCoverFromChilltrax else { return }

        // 1. Fetch current playing song cover if playing and missing
        if radioPlayer.isPlaying, currentSong.isMeaningfulTrack, currentSong.coverURL == nil {
            let activeStation = selectedStation
            let endpoints = stationAPIEndpoints[activeStation] ?? activeStation.defaultAPIEndpoints
            if let cover = try? await client.fetchCurrentAlbumCoverURLString(
                station: activeStation,
                endpoints: endpoints
            ) {
                if radioPlayer.isPlaying, selectedStation == activeStation {
                    var updated = currentSong
                    updated.coverURLString = cover
                    currentSong = updated
                    cacheAlbumCoverForHistoryItem(updated.coverURL)
                    if hasRecordedCurrentSongInHistory {
                        historyEntries = historyStore.recordSong(updated, station: selectedStream, existingEntries: historyEntries)
                    }
                }
            }
        }

        // 2. Backfill any history entries that were recorded without cover URLs while the setting was off
        await backfillMissingHistoryAlbumCovers()
    }

    public func backfillMissingHistoryAlbumCovers() async {
        guard fetchAlbumCoverFromChilltrax else { return }
        let entriesMissingCovers = historyEntries.filter { $0.coverURL == nil }
        guard !entriesMissingCovers.isEmpty else { return }

        let stationsWithMissing = Set(entriesMissingCovers.map(\.station))
        var recentCoverMap: [String: SongMetadata] = [:]

        for station in stationsWithMissing {
            let endpoints = stationAPIEndpoints[station] ?? station.defaultAPIEndpoints
            if let recentTracks = try? await client.fetchLastTenTracks(station: station, endpoints: endpoints) {
                for track in recentTracks where track.coverURL != nil {
                    recentCoverMap[track.normalizedKey] = track
                }
            }
        }

        guard fetchAlbumCoverFromChilltrax else { return }

        var updatedEntries = historyEntries
        var didChange = false
        var urlsToCache: [URL] = []

        for index in updatedEntries.indices where updatedEntries[index].coverURL == nil {
            let entry = updatedEntries[index]
            if let matched = recentCoverMap[entry.normalizedKey],
               let cover = matched.coverURLString,
               !cover.isEmpty {
                updatedEntries[index].coverURLString = cover
                if updatedEntries[index].albumOrMix.isEmpty, !matched.albumOrMix.isEmpty {
                    updatedEntries[index].albumOrMix = matched.albumOrMix
                }
                if updatedEntries[index].year.isEmpty, !matched.year.isEmpty {
                    updatedEntries[index].year = matched.year
                }
                if updatedEntries[index].buyURLString.isEmpty, !matched.buyURLString.isEmpty {
                    updatedEntries[index].buyURLString = matched.buyURLString
                }
                if let url = updatedEntries[index].coverURL {
                    urlsToCache.append(url)
                }
                didChange = true
            }
        }

        if didChange {
            historyEntries = updatedEntries
            historyStore.save(updatedEntries)
            for url in urlsToCache {
                cacheAlbumCoverForHistoryItem(url)
            }
        }

        // 3. For any remaining entries still missing cover URLs, look up cover art via iTunes Search API
        let remainingIndices = historyEntries.indices.filter { historyEntries[$0].coverURL == nil }
        for index in remainingIndices {
            guard fetchAlbumCoverFromChilltrax, index < historyEntries.count else { break }
            let entry = historyEntries[index]
            guard entry.coverURL == nil else { continue }
            if let foundCover = try? await client.searchAlbumCoverURLString(
                artist: entry.artist,
                title: entry.title,
                album: entry.albumOrMix
            ), !foundCover.isEmpty {
                guard fetchAlbumCoverFromChilltrax else { break }
                if let targetIndex = historyEntries.firstIndex(where: { $0.id == entry.id }),
                   historyEntries[targetIndex].coverURL == nil {
                    var current = historyEntries
                    current[targetIndex].coverURLString = foundCover
                    historyEntries = current
                    historyStore.save(current)
                    cacheAlbumCoverForHistoryItem(current[targetIndex].coverURL)
                }
            }
        }

        // Also update currentSong if it matches one of the backfilled history entries and still lacks a cover
        if currentSong.isMeaningfulTrack,
           currentSong.coverURL == nil,
           let matchedEntry = historyEntries.first(where: { $0.normalizedKey == currentSong.normalizedKey && $0.coverURL != nil }) {
            var updatedSong = currentSong
            updatedSong.coverURLString = matchedEntry.coverURLString
            currentSong = updatedSong
        }
    }
}
