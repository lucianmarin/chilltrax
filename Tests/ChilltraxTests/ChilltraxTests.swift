import XCTest
import SwiftUI
@testable import Chilltrax

final class ChilltraxTests: XCTestCase {

    // MARK: - Broadcast Discovery & PLS Parsing

    func testParseBroadcastStreamsFromChilltraxHTML() {
        let sampleHTML = """
        <html>
        <body>
        <script>
            streamurl: "https://www.chilltrax.com/listen/?mode=redirect",
        </script>
        <div id="listen-section">
            <ul>
                <li><a href="http://streams.electronicmusicradiogroup.org:9050" target="_blank">Highest (HD) Quality 128Kbps AAC+</a></li>
                <li><a href="http://streams.electronicmusicradiogroup.org:9000" target="_blank">High Quality 128Kbps MP3</a></li>
                <li><a id="firewallStream" href="https://www.chilltrax.com/listen" target="_blank">High Quality 128Kbps MP3 (firewall friendly)</a></li>
                <li><a href="http://streams.electronicmusicradiogroup.org:9020" target="_blank">High Quality 80Kbps AAC+</a></li>
                <li><a href="http://streams.electronicmusicradiogroup.org:9010" target="_blank">High Quality 64Kbps AAC+</a></li>
            </ul>
        </div>
        </body>
        </html>
        """

        let streams = ChilltraxClient.parseBroadcastStreams(fromHTML: sampleHTML)
        XCTAssertGreaterThanOrEqual(streams.count, 6)
        XCTAssertTrue(streams.contains { $0.urlString == "https://www.chilltrax.com/listen/?mode=redirect" })
        XCTAssertTrue(streams.contains { $0.urlString == "http://streams.electronicmusicradiogroup.org:9050" })
        XCTAssertTrue(streams.contains { $0.urlString == "http://streams.electronicmusicradiogroup.org:9000" })
        XCTAssertTrue(streams.contains { $0.urlString == "https://www.chilltrax.com/listen" })
        XCTAssertTrue(streams.contains { $0.urlString == "https://streamssleu.chilltrax.com/stream?sid=1" })
    }

    func testParsePLSStreamURL() {
        let pls = """
        [playlist]
        NumberOfEntries=1
        File1=https://streamssleu.chilltrax.com/stream?sid=1
        Title1=chilltrax
        Length1=-1
        Version=2
        """
        let url = ChilltraxClient.parsePLSStreamURL(from: pls)
        XCTAssertEqual(url?.absoluteString, "https://streamssleu.chilltrax.com/stream?sid=1")
    }

    // MARK: - Metadata & Cover Art Decoding

    func testNowPlayingAndCoverJSONDecoding() throws {
        let infoJSON = """
        {"artist":"Boycott &amp; Lumynesynth","title":"Shadows","mix":"Shadows - Single","label":"Sekora","year":"2026","buycd":"https:\\/\\/geo.music.apple.com\\/us\\/album\\/shadows\\/123","newSong":"0","songID":5832}
        """.data(using: .utf8)!

        let coverJSON = """
        {"cover":"https:\\/\\/is1-ssl.mzstatic.com\\/image\\/thumb\\/Music\\/300x300bb.jpg"}
        """.data(using: .utf8)!

        let info = try JSONDecoder().decode(ChilltraxNowPlayingResponse.self, from: infoJSON)
        let cover = try JSONDecoder().decode(ChilltraxCoverResponse.self, from: coverJSON)

        let metadata = info.toSongMetadata(coverURLString: cover.cover)
        XCTAssertEqual(metadata.artist, "Boycott & Lumynesynth")
        XCTAssertEqual(metadata.title, "Shadows")
        XCTAssertEqual(metadata.albumOrMix, "Shadows - Single")
        XCTAssertEqual(metadata.year, "2026")
        XCTAssertEqual(metadata.songID, 5832)
        XCTAssertEqual(metadata.coverURL?.absoluteString, "https://is1-ssl.mzstatic.com/image/thumb/Music/300x300bb.jpg")
        XCTAssertEqual(metadata.displayName, "Boycott & Lumynesynth — Shadows")
    }

    func testICYStreamTitleParsing() {
        let song = SongMetadata.fromICYStreamTitle("Tycho - Awake")
        XCTAssertEqual(song?.artist, "Tycho")
        XCTAssertEqual(song?.title, "Awake")
        XCTAssertEqual(song?.displayName, "Tycho — Awake")
        XCTAssertTrue(song?.isMeaningfulTrack ?? false)
    }

    // MARK: - Compressed Text File History Persistence & Search

    func testCompressedHistoryStorePersistenceAndDeduplication() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChilltraxTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("history.tsv.lzfse")
        let store = CompressedHistoryStore(fileURL: fileURL)

        let station = StationStream.defaultStream
        let song1 = SongMetadata(
            artist: "Bonobo",
            title: "Kerala",
            albumOrMix: "Migration",
            year: "2017",
            coverURLString: "https://www.chilltrax.com/images/cover/kerala.jpg"
        )
        let song2 = SongMetadata(
            artist: "Zero 7",
            title: "In the Waiting Line",
            albumOrMix: "Simple Things",
            year: "2001",
            coverURLString: "images/cover/zero7.jpg"
        )

        let t1 = Date(timeIntervalSince1970: 1_700_000_000)
        let t2 = Date(timeIntervalSince1970: 1_700_000_240)

        var entries = store.recordSong(song1, station: station, playedAt: t1)
        XCTAssertEqual(entries.count, 1)

        // Recording the exact same song consecutively should not create a duplicate row
        entries = store.recordSong(song1, station: station, playedAt: t1.addingTimeInterval(15), existingEntries: entries)
        XCTAssertEqual(entries.count, 1)

        // Recording a new song appends it at the top (newest first)
        entries = store.recordSong(song2, station: station, playedAt: t2, existingEntries: entries)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.first?.artist, "Zero 7")

        // Verify the on-disk file is LZFSE-compressed and smaller than or distinct from plain text header
        let rawBytes = try Data(contentsOf: fileURL)
        XCTAssertFalse(rawBytes.isEmpty)
        XCTAssertNil(String(data: rawBytes, encoding: .utf8), "File on disk should be LZFSE-compressed binary data, not raw uncompressed text")
        XCTAssertNotNil(try? (rawBytes as NSData).decompressed(using: .lzfse))

        // Simulate app restart by instantiating a new CompressedHistoryStore pointing at the same file
        let reloadedStore = CompressedHistoryStore(fileURL: fileURL)
        let reloaded = reloadedStore.load()
        XCTAssertEqual(reloaded.count, 2)
        XCTAssertEqual(reloaded[0].artist, "Zero 7")
        XCTAssertEqual(reloaded[0].title, "In the Waiting Line")
        XCTAssertEqual(reloaded[0].coverURL?.absoluteString, "https://www.chilltrax.com/images/cover/zero7.jpg")
        XCTAssertEqual(reloaded[1].artist, "Bonobo")
        XCTAssertEqual(reloaded[1].title, "Kerala")

        // Verify search matching across artist, title, album, and year
        XCTAssertTrue(reloaded[0].matches(searchQuery: "waiting zero"))
        XCTAssertTrue(reloaded[1].matches(searchQuery: "migration 2017"))
        XCTAssertFalse(reloaded[0].matches(searchQuery: "bonobo"))
    }

    // MARK: - AppState Custom Station & Search Filtering

    @MainActor
    func testAppStateCustomStreamAndHistorySearch() {
        let suiteName = "ChilltraxTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("history-\(UUID().uuidString).tsv.lzfse")
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let store = CompressedHistoryStore(fileURL: tempFile)
        let state = AppState(
            historyStore: store,
            defaults: defaults,
            startPollingAutomatically: false,
            minimumHistoryPlayDuration: 0
        )

        // Test visualizer mode toggle
        XCTAssertEqual(state.visualizerMode, .bars)
        state.toggleVisualizerMode()
        XCTAssertEqual(state.visualizerMode, .waveform)

        // Test custom stream configuration
        XCTAssertFalse(state.addAndSelectCustomStream(name: "Invalid", urlString: "not-a-url"))
        XCTAssertTrue(state.addAndSelectCustomStream(name: "Ambient Sleeping Pill", urlString: "https://radio.stereoscenic.com/asp-s"))
        XCTAssertEqual(state.selectedStream.name, "Ambient Sleeping Pill")
        XCTAssertEqual(state.selectedStream.urlString, "https://radio.stereoscenic.com/asp-s")

        // Test song change recording & search filtering while playing
        state.radioPlayer.setSimulatedPlaybackStateForTesting(isPlaying: true, status: .playing)
        state.handleIncomingSongMetadata(
            SongMetadata(artist: "Air", title: "La Femme d'Argent", albumOrMix: "Moon Safari", coverURLString: "https://example.com/air.jpg"),
            sourceIsICY: false
        )
        state.handleIncomingSongMetadata(
            SongMetadata(artist: "Massive Attack", title: "Teardrop", albumOrMix: "Mezzanine", coverURLString: "https://example.com/ma.jpg"),
            sourceIsICY: false
        )

        XCTAssertEqual(state.historyEntries.count, 2)
        XCTAssertFalse(state.isHistoryExpanded)

        // Searching with matching results automatically expands the player with history results
        state.historySearchQuery = "moon"
        XCTAssertEqual(state.filteredHistoryEntries.count, 1)
        XCTAssertEqual(state.filteredHistoryEntries.first?.artist, "Air")
        XCTAssertTrue(state.isHistoryExpanded)

        // Searching with no matching results collapses the player back to compact
        state.historySearchQuery = "nonexistent-artist-xyz"
        XCTAssertTrue(state.filteredHistoryEntries.isEmpty)
        XCTAssertFalse(state.isHistoryExpanded)

        // Matching query expands again, and clearing search query collapses back to compact
        state.historySearchQuery = "teardrop"
        XCTAssertEqual(state.filteredHistoryEntries.count, 1)
        XCTAssertTrue(state.isHistoryExpanded)
        state.historySearchQuery = ""
        XCTAssertFalse(state.isHistoryExpanded)

        // Disabling album cover setting clears current song cover URL
        state.fetchAlbumCoverFromChilltrax = false
        XCTAssertNil(state.currentSong.coverURL)
    }

    func testAppIconVectorRenderingFromSVG() {
        let chillBox = AppIcon.parseSVGPath(AppIcon.chillPathD).boundingBoxOfPath
        let traxBox = AppIcon.parseSVGPath(AppIcon.traxPathD).boundingBoxOfPath
        let hashBox = AppIcon.parseSVGPath(AppIcon.hashPathD).boundingBoxOfPath
        XCTAssertFalse(chillBox.isEmpty)
        XCTAssertFalse(traxBox.isEmpty)
        XCTAssertFalse(hashBox.isEmpty)

        let pngData = AppIcon.renderPNGData(pixelSize: 1024)
        XCTAssertNotNil(pngData)
        XCTAssertGreaterThan(pngData?.count ?? 0, 5_000)

        let placeholderData = AppIcon.renderPlaceholderPNGData(pixelSize: 240)
        XCTAssertNotNil(placeholderData)
        XCTAssertGreaterThan(placeholderData?.count ?? 0, 1_000)

        XCTAssertEqual(ChilltraxTheme.visualizerBackground(for: .light), ChilltraxTheme.visualizerWhite)
        XCTAssertEqual(ChilltraxTheme.visualizerContrastColor(for: .light), ChilltraxTheme.visualizerBlack)
        XCTAssertEqual(ChilltraxTheme.visualizerBackground(for: .dark), ChilltraxTheme.visualizerBlack)
        XCTAssertEqual(ChilltraxTheme.visualizerContrastColor(for: .dark), ChilltraxTheme.visualizerWhite)
    }

    @MainActor
    func testWindowExpandCollapsePreservesTopEdgeAndLayoutHeight() {
        let suiteName = "ChilltraxWindowTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("window-history-\(UUID().uuidString).tsv.lzfse")
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let state = AppState(
            historyStore: CompressedHistoryStore(fileURL: tempFile),
            defaults: defaults,
            startPollingAutomatically: false,
            minimumHistoryPlayDuration: 0
        )
        state.radioPlayer.setSimulatedPlaybackStateForTesting(isPlaying: true, status: .playing)

        let hostingController = NSHostingController(rootView: CompactPlayerView(appState: state))
        let window = NSWindow(
            contentRect: NSRect(x: 200, y: 400, width: ChilltraxTheme.compactWidth, height: ChilltraxTheme.compactHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.toolbar = NSToolbar(identifier: "TestToolbar")
        window.contentViewController = hostingController
        hostingController.view.layoutSubtreeIfNeeded()

        let coordinator = WindowAccessor.Coordinator(defaults: defaults)
        coordinator.configure(window: window)
        coordinator.syncSize(isExpanded: false, on: window)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        let initialTopY = window.frame.maxY
        XCTAssertEqual(window.contentLayoutRect.height, ChilltraxTheme.compactHeight, accuracy: 1.0)
        XCTAssertFalse(window.styleMask.contains(.resizable))
        XCTAssertEqual(window.minSize.width, ChilltraxTheme.compactWidth, accuracy: 0.5)
        XCTAssertEqual(window.maxSize.width, ChilltraxTheme.compactWidth, accuracy: 0.5)

        // Move window & verify position is persisted when closing and restored on a newly launched window
        window.setFrameTopLeftPoint(NSPoint(x: 345, y: 678))
        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)

        let reopenedWindow = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: ChilltraxTheme.compactWidth, height: ChilltraxTheme.compactHeight),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        let reopenedCoordinator = WindowAccessor.Coordinator(defaults: defaults)
        reopenedCoordinator.configure(window: reopenedWindow)
        XCTAssertEqual(reopenedWindow.frame.minX, 345, accuracy: 1.0)
        XCTAssertEqual(reopenedWindow.frame.maxY, 678, accuracy: 1.0)

        // Reset original test window position for expand/collapse assertions
        window.setFrameTopLeftPoint(NSPoint(x: 200, y: initialTopY))

        // Expand history with 2 results
        state.handleIncomingSongMetadata(
            SongMetadata(artist: "Air", title: "All I Need", albumOrMix: "Moon Safari"),
            sourceIsICY: false
        )
        state.handleIncomingSongMetadata(
            SongMetadata(artist: "Bonobo", title: "Cirrus", albumOrMix: "The North Borders"),
            sourceIsICY: false
        )
        state.isHistoryExpanded = true
        hostingController.view.layoutSubtreeIfNeeded()
        coordinator.syncSize(isExpanded: true, resultCount: state.filteredHistoryEntries.count, on: window)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        let twoResultsHeight = ChilltraxTheme.contentHeight(isExpanded: true, resultCount: 2)
        XCTAssertEqual(window.frame.maxY, initialTopY, accuracy: 1.0)
        XCTAssertEqual(window.contentLayoutRect.height, twoResultsHeight, accuracy: 1.0)
        XCTAssertFalse(window.styleMask.contains(.resizable))
        XCTAssertEqual(window.minSize.width, ChilltraxTheme.compactWidth, accuracy: 0.5)
        XCTAssertEqual(window.maxSize.width, ChilltraxTheme.compactWidth, accuracy: 0.5)

        // Expand history with > 6 results (capped at 6 visible rows)
        coordinator.syncSize(isExpanded: true, resultCount: 10, on: window)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertEqual(window.frame.maxY, initialTopY, accuracy: 1.0)
        XCTAssertEqual(window.contentLayoutRect.height, ChilltraxTheme.expandedHeight, accuracy: 1.0)
        XCTAssertFalse(window.styleMask.contains(.resizable))

        // Collapse history
        state.isHistoryExpanded = false
        hostingController.view.layoutSubtreeIfNeeded()
        coordinator.syncSize(isExpanded: false, resultCount: 10, on: window)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertEqual(window.frame.maxY, initialTopY, accuracy: 1.0)
        XCTAssertEqual(window.contentLayoutRect.height, ChilltraxTheme.compactHeight, accuracy: 1.0)
        XCTAssertFalse(window.styleMask.contains(.resizable))
        XCTAssertEqual(window.minSize.width, ChilltraxTheme.compactWidth, accuracy: 0.5)
        XCTAssertEqual(window.maxSize.width, ChilltraxTheme.compactWidth, accuracy: 0.5)
    }

    @MainActor
    func testBarsAndWaveformVisualizersSyncToMusicIntensity() {
        let count = RadioPlayer.visualizerBarCount
        XCTAssertEqual(count, 42)

        // 1. Verify RadioPlayer audio intensity spectrum analysis from PCM samples
        let quietSamples = (0..<2048).map { i in Float(sin(Double(i) * 0.15) * 0.02) }
        let mediumSamples = (0..<2048).map { i in Float(sin(Double(i) * 0.15) * 0.22) }
        let loudSamples = (0..<2048).map { i in Float(sin(Double(i) * 0.15) * 0.85) }

        let quietLevels = RadioPlayer.computeSpectrumLevels(fromPCM: quietSamples, count: count)
        let mediumLevels = RadioPlayer.computeSpectrumLevels(fromPCM: mediumSamples, count: count)
        let loudLevels = RadioPlayer.computeSpectrumLevels(fromPCM: loudSamples, count: count)

        let quietAvg = quietLevels.reduce(0, +) / CGFloat(count)
        let mediumAvg = mediumLevels.reduce(0, +) / CGFloat(count)
        let loudAvg = loudLevels.reduce(0, +) / CGFloat(count)

        XCTAssertLessThan(quietAvg, mediumAvg)
        XCTAssertLessThan(mediumAvg, loudAvg)

        // 2. Verify Bars visualizer height & Waveform visualizer vertical span both scale monotonically with music intensity
        let canvasSize = CGSize(width: 452, height: 68)
        let barsQuietHeight = VisualizerView.barsAverageHeight(levels: quietLevels, size: canvasSize)
        let barsMediumHeight = VisualizerView.barsAverageHeight(levels: mediumLevels, size: canvasSize)
        let barsLoudHeight = VisualizerView.barsAverageHeight(levels: loudLevels, size: canvasSize)

        XCTAssertLessThan(barsQuietHeight, barsMediumHeight)
        XCTAssertLessThan(barsMediumHeight, barsLoudHeight)

        let waveQuietSpan = VisualizerView.waveformPeakVerticalSpan(levels: quietLevels, phase: 1.2, size: canvasSize)
        let waveMediumSpan = VisualizerView.waveformPeakVerticalSpan(levels: mediumLevels, phase: 1.2, size: canvasSize)
        let waveLoudSpan = VisualizerView.waveformPeakVerticalSpan(levels: loudLevels, phase: 1.2, size: canvasSize)

        XCTAssertLessThan(waveQuietSpan, waveMediumSpan)
        XCTAssertLessThan(waveMediumSpan, waveLoudSpan)

        // 3. Verify rendered output of both .bars and .waveform visualizers increases active pixel energy with intensity
        func countActivePixels(mode: VisualizerMode, levels: [CGFloat]) -> Int {
            let view = VisualizerView(mode: mode, levels: levels, phase: 1.2, isPlaying: true)
                .environment(\.colorScheme, .light)
                .frame(width: canvasSize.width, height: canvasSize.height)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1.0
            guard let cgImage = renderer.cgImage,
                  let data = cgImage.dataProvider?.data,
                  let ptr = CFDataGetBytePtr(data) else {
                return 0
            }
            let bytesPerRow = cgImage.bytesPerRow
            let width = cgImage.width
            let height = cgImage.height
            var nonWhitePixels = 0
            for y in 4..<(height - 4) {
                for x in 4..<(width - 4) {
                    let offset = y * bytesPerRow + x * 4
                    let r = ptr[offset]
                    let g = ptr[offset + 1]
                    let b = ptr[offset + 2]
                    if r < 245 || g < 245 || b < 245 {
                        nonWhitePixels += 1
                    }
                }
            }
            return nonWhitePixels
        }

        let barsQuietPixels = countActivePixels(mode: .bars, levels: quietLevels)
        let barsMediumPixels = countActivePixels(mode: .bars, levels: mediumLevels)
        let barsLoudPixels = countActivePixels(mode: .bars, levels: loudLevels)
        XCTAssertLessThan(barsQuietPixels, barsMediumPixels)
        XCTAssertLessThan(barsMediumPixels, barsLoudPixels)

        let waveQuietPixels = countActivePixels(mode: .waveform, levels: quietLevels)
        let waveMediumPixels = countActivePixels(mode: .waveform, levels: mediumLevels)
        let waveLoudPixels = countActivePixels(mode: .waveform, levels: loudLevels)
        XCTAssertLessThan(waveQuietPixels, waveMediumPixels)
        XCTAssertLessThan(waveMediumPixels, waveLoudPixels)
    }

    @MainActor
    func testHistoryOnlyStoresSongsPlayedForMinimumDuration() async throws {
        let suiteName = "ChilltraxHistoryThresholdTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("threshold-history-\(UUID().uuidString).tsv.lzfse")
        defer { try? FileManager.default.removeItem(at: tempFile) }

        // Default minimum play duration is 10 seconds (clamped to 0...99)
        let defaultState = AppState(
            historyStore: CompressedHistoryStore(fileURL: tempFile),
            defaults: defaults,
            startPollingAutomatically: false
        )
        XCTAssertEqual(defaultState.historyCommitDelaySeconds, 10)
        XCTAssertEqual(defaultState.minimumHistoryPlayDuration, 10.0)
        defaultState.historyCommitDelaySeconds = 150
        XCTAssertEqual(defaultState.historyCommitDelaySeconds, 99)
        XCTAssertEqual(defaultState.minimumHistoryPlayDuration, 99.0)
        defaultState.historyCommitDelaySeconds = -5
        XCTAssertEqual(defaultState.historyCommitDelaySeconds, 0)
        XCTAssertEqual(defaultState.minimumHistoryPlayDuration, 0.0)
        XCTAssertEqual(defaultState.currentSong.title, "Title")
        XCTAssertEqual(defaultState.currentSong.artist, "Artist")
        XCTAssertEqual(defaultState.currentSong.albumOrMix, "Album")
        XCTAssertFalse(defaultState.currentSong.isMeaningfulTrack)

        // Use a 100ms threshold in test to verify timer scheduling, skipping, and pause/resume accumulation
        let state = AppState(
            historyStore: CompressedHistoryStore(fileURL: tempFile),
            defaults: defaults,
            startPollingAutomatically: false,
            minimumHistoryPlayDuration: 0.10
        )

        // 1. Metadata arriving while paused / not playing should NOT be stored in history
        state.radioPlayer.setSimulatedPlaybackStateForTesting(isPlaying: false, status: .paused)
        state.handleIncomingSongMetadata(
            SongMetadata(artist: "Zero 7", title: "Destiny", albumOrMix: "Simple Things"),
            sourceIsICY: false
        )
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertTrue(state.historyEntries.isEmpty)

        // 2. Starting playback and changing/pausing before the minimum duration should NOT store the song
        state.radioPlayer.setSimulatedPlaybackStateForTesting(isPlaying: true, status: .playing)
        try await Task.sleep(nanoseconds: 40_000_000)
        state.handleIncomingSongMetadata(
            SongMetadata(artist: "Moby", title: "Porcelain", albumOrMix: "Play"),
            sourceIsICY: false
        )
        XCTAssertTrue(state.historyEntries.isEmpty)

        // 3. Playing the song for at least the minimum duration stores it in history
        try await Task.sleep(nanoseconds: 140_000_000)
        XCTAssertEqual(state.historyEntries.count, 1)
        XCTAssertEqual(state.historyEntries.first?.artist, "Moby")
        XCTAssertEqual(state.historyEntries.first?.title, "Porcelain")
    }

    @MainActor
    func testProgressiveHistoryLoading50AtATimeAndFullSearch() {
        let suiteName = "ChilltraxPaginationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("paged-history-\(UUID().uuidString).tsv.lzfse")
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let store = CompressedHistoryStore(fileURL: tempFile)
        var seeded = [SongHistoryEntry]()
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        for i in 1...120 {
            seeded.append(
                SongHistoryEntry(
                    playedAt: baseDate.addingTimeInterval(Double(120 - i) * 60),
                    artist: "Artist \(i)",
                    title: "Track \(i)",
                    albumOrMix: "Album \(i)",
                    stationName: "Chilltrax",
                    stationURLString: StationStream.defaultStream.urlString
                )
            )
        }
        store.save(seeded)

        let state = AppState(
            historyStore: store,
            defaults: defaults,
            startPollingAutomatically: false,
            minimumHistoryPlayDuration: 0
        )

        // Initially loads 50 displayed entries out of 120 total
        XCTAssertEqual(state.historyEntries.count, 120)
        XCTAssertEqual(state.filteredHistoryEntries.count, 120)
        XCTAssertEqual(state.displayedHistoryEntries.count, 50)
        XCTAssertTrue(state.hasMoreHistoryEntries)

        // Searching searches across all 120 entries, even entries beyond the first 50
        state.historySearchQuery = "Track 115"
        XCTAssertEqual(state.filteredHistoryEntries.count, 1)
        XCTAssertEqual(state.displayedHistoryEntries.count, 1)
        XCTAssertEqual(state.displayedHistoryEntries.first?.title, "Track 115")

        // Clearing search resets progressive pagination to 50 and loads 50 more at a time on scroll
        state.historySearchQuery = ""
        XCTAssertEqual(state.displayedHistoryEntries.count, 50)
        state.loadMoreHistoryIfNeeded(currentEntry: state.displayedHistoryEntries.last)
        XCTAssertEqual(state.displayedHistoryEntries.count, 100)
        XCTAssertTrue(state.hasMoreHistoryEntries)
        state.loadMoreHistoryIfNeeded(currentEntry: state.displayedHistoryEntries.last)
        XCTAssertEqual(state.displayedHistoryEntries.count, 120)
        XCTAssertFalse(state.hasMoreHistoryEntries)
    }

    @MainActor
    func testAlbumCoversCachedLocallyForHistoryItemsAndDeletedOnClearHistory() async throws {
        let suiteName = "ChilltraxCoverCacheTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("cover-cache-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let historyFile = tempRoot.appendingPathComponent("history.tsv.lzfse")
        let coversDir = tempRoot.appendingPathComponent("Covers", isDirectory: true)

        guard let pngData = AppIcon.renderPlaceholderPNGData(pixelSize: 64) else {
            XCTFail("Expected placeholder PNG data")
            return
        }

        let coverURL1 = URL(string: "https://www.chilltrax.com/images/cover/track1.png")!
        let coverURL2 = URL(string: "https://www.chilltrax.com/images/cover/track2.jpg")!

        MockCoverURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url ?? coverURL1,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "image/png"]
            )!
            return (response, pngData)
        }
        defer { MockCoverURLProtocol.requestHandler = nil }

        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [MockCoverURLProtocol.self]
        let mockClient = ChilltraxClient(session: URLSession(configuration: sessionConfig))

        let store = CompressedHistoryStore(fileURL: historyFile)
        let coverCache = AlbumCoverCache(directoryURL: coversDir, client: mockClient)
        let state = AppState(
            client: mockClient,
            historyStore: store,
            coverCache: coverCache,
            defaults: defaults,
            startPollingAutomatically: false,
            minimumHistoryPlayDuration: 0
        )

        state.radioPlayer.setSimulatedPlaybackStateForTesting(isPlaying: true, status: .playing)
        state.handleIncomingSongMetadata(
            SongMetadata(
                artist: "Thievery Corporation",
                title: "Lebanese Blonde",
                albumOrMix: "The Mirror Conspiracy",
                coverURLString: coverURL1.absoluteString
            ),
            sourceIsICY: false
        )
        state.handleIncomingSongMetadata(
            SongMetadata(
                artist: "Kruder & Dorfmeister",
                title: "High Noon",
                albumOrMix: "The K&D Sessions",
                coverURLString: coverURL2.absoluteString
            ),
            sourceIsICY: false
        )

        // Wait briefly for the background cover caching tasks to finish writing to disk
        for _ in 0..<30 {
            if coverCache.isCachedOnDisk(for: coverURL1) && coverCache.isCachedOnDisk(for: coverURL2) {
                break
            }
            try await Task.sleep(nanoseconds: 25_000_000)
        }

        XCTAssertEqual(state.historyEntries.count, 2)
        XCTAssertTrue(coverCache.isCachedOnDisk(for: coverURL1))
        XCTAssertTrue(coverCache.isCachedOnDisk(for: coverURL2))
        XCTAssertEqual(coverCache.cachedFileCount, 2)
        XCTAssertGreaterThan(coverCache.cachedFilesSizeBytes, 0)
        XCTAssertNotNil(coverCache.cachedImage(for: coverURL1))
        XCTAssertNotNil(coverCache.cachedImage(for: coverURL2))

        // Verify disk persistence across a fresh AlbumCoverCache instance
        let reloadedCache = AlbumCoverCache(directoryURL: coversDir, client: mockClient)
        XCTAssertNotNil(reloadedCache.cachedImage(for: coverURL1))
        XCTAssertNotNil(reloadedCache.cachedImage(for: coverURL2))

        // Clearing history deletes all cached album covers from disk and memory
        state.clearHistory()
        XCTAssertTrue(state.historyEntries.isEmpty)
        XCTAssertFalse(coverCache.isCachedOnDisk(for: coverURL1))
        XCTAssertFalse(coverCache.isCachedOnDisk(for: coverURL2))
        XCTAssertEqual(coverCache.cachedFileCount, 0)
        XCTAssertEqual(coverCache.cachedFilesSizeBytes, 0)
        XCTAssertNil(coverCache.cachedImage(for: coverURL1))
        XCTAssertNil(coverCache.cachedImage(for: coverURL2))
    }
}

private final class MockCoverURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

