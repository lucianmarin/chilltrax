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

        let fileURL = tempDir.appendingPathComponent("history.tsv.zlib")
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

        // Verify the on-disk file is compressed and smaller than or distinct from plain text header
        let rawBytes = try Data(contentsOf: fileURL)
        XCTAssertFalse(rawBytes.isEmpty)
        XCTAssertNil(String(data: rawBytes, encoding: .utf8), "File on disk should be zlib-compressed binary data, not raw uncompressed text")

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
            .appendingPathComponent("history-\(UUID().uuidString).tsv.zlib")
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let store = CompressedHistoryStore(fileURL: tempFile)
        let state = AppState(
            historyStore: store,
            defaults: defaults,
            startPollingAutomatically: false
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

        // Test song change recording & search filtering
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
            .appendingPathComponent("window-history-\(UUID().uuidString).tsv.zlib")
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let state = AppState(
            historyStore: CompressedHistoryStore(fileURL: tempFile),
            defaults: defaults,
            startPollingAutomatically: false
        )

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

        let coordinator = WindowAccessor.Coordinator()
        coordinator.configure(window: window)
        coordinator.syncSize(isExpanded: false, on: window)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        let initialTopY = window.frame.maxY
        XCTAssertEqual(window.contentLayoutRect.height, ChilltraxTheme.compactHeight, accuracy: 1.0)
        XCTAssertFalse(window.styleMask.contains(.resizable))
        XCTAssertEqual(window.minSize.width, ChilltraxTheme.compactWidth, accuracy: 0.5)
        XCTAssertEqual(window.maxSize.width, ChilltraxTheme.compactWidth, accuracy: 0.5)

        // Expand history
        state.isHistoryExpanded = true
        hostingController.view.layoutSubtreeIfNeeded()
        coordinator.syncSize(isExpanded: true, on: window)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertEqual(window.frame.maxY, initialTopY, accuracy: 1.0)
        XCTAssertEqual(window.contentLayoutRect.height, ChilltraxTheme.expandedHeight, accuracy: 1.0)
        XCTAssertTrue(window.styleMask.contains(.resizable))
        XCTAssertEqual(window.minSize.width, ChilltraxTheme.compactWidth, accuracy: 0.5)
        XCTAssertEqual(window.maxSize.width, ChilltraxTheme.compactWidth, accuracy: 0.5)

        // Collapse history
        state.isHistoryExpanded = false
        hostingController.view.layoutSubtreeIfNeeded()
        coordinator.syncSize(isExpanded: false, on: window)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertEqual(window.frame.maxY, initialTopY, accuracy: 1.0)
        XCTAssertEqual(window.contentLayoutRect.height, ChilltraxTheme.compactHeight, accuracy: 1.0)
        XCTAssertFalse(window.styleMask.contains(.resizable))
        XCTAssertEqual(window.minSize.width, ChilltraxTheme.compactWidth, accuracy: 0.5)
        XCTAssertEqual(window.maxSize.width, ChilltraxTheme.compactWidth, accuracy: 0.5)
    }
}
