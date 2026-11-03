# Chilltrax — Winamp of the AI era

![screenshot](screenshot.jpg)

Chilltrax is a native macOS one-radio-station player built with SwiftUI and AVFoundation for **Chilltrax — The World's Chillout Channel** (`chilltrax.com`), with full support for custom station stream URLs.

## Specification & Requirements

1. **Native macOS Application**:
   - Built with Swift Package Manager targeting **macOS 14+ (Sonoma)** using SwiftUI and AppKit window customization (`titleVisibility = .hidden`, `.unified` toolbar, `.fullSizeContentView`), matching `macreply` and `macnews`.
2. **Station Stream Discovery & Custom Stream Configuration**:
   - **Find Broadcast from `chilltrax.com`**: Queries and parses `https://www.chilltrax.com` in Settings to discover official broadcast streams (including the firewall-friendly SSL stream and Shoutcast streams), resolving `.pls` and redirect endpoints automatically.
   - **Custom Station URL**: Allows configuring and switching to any custom radio stream URL (HTTP/HTTPS MP3, AAC+, HLS, or `.pls` playlist).
3. **Real-Time Audio Visualizer (Waveform or Bars)**:
   - Interactive visualizer supporting both **Waveform** (smooth multi-layered oscillating sine/audio wave) and **Bars** (frequency spectrum bars) modes, switchable directly from the player or Settings.
4. **Playback Controls & Current Song Display**:
   - Play / Pause toggle (plays at maximum volume `1.0` so system volume controls audio level), left-aligned toolbar station status badge (`READY` / `LIVE` / `PAUSED` / `CONNECTING…` / `ERROR`) that opens the Settings panel when clicked, current song title, artist, album/mix badge, and album cover that shows an Apple logo on mouse hover to open the song on Apple Music.
5. **Album Cover Fetching Setting**:
   - Toggleable setting to fetch and display the currently playing song's album artwork from `chilltrax.com` (`php/GetCoverImageNew.php`).
6. **macOS Notifications on Song Change**:
   - Sends native macOS notifications (`UNUserNotificationCenter`) whenever the playing track changes, displaying the new song title, artist, and album/mix (configurable in Settings).
7. **Compact Player Main UI with Expandable Searchable History**:
   - Main UI is a sleek **compact player** window with a full-width visualizer across the bottom.
   - Clicking the **History SF Symbol** (`clock.arrow.circlepath`) with the live song counter in the toolbar smoothly expands the window to reveal a **searchable history list** of all played songs (filterable by title, artist, album/mix, or station).
8. **Compressed Local Song History Persistence**:
   - Every song played is persisted locally across app restarts in an **efficiently compressed text file** (`~/Library/Application Support/Chilltrax/history.tsv.lzfse`), using tab-separated UTF-8 text compressed with Apple's native `Compression` (`LZFSE`) algorithm (matching `monochrome`).

## Implementation Tracker

- [x] Project scaffolding (`Package.swift`, `Makefile`, `icon.svg`, `AppIcon.icns`)
- [x] Models (`StationStream`, `SongMetadata`, `SongHistoryEntry`, `VisualizerMode`)
- [x] Compressed text file history persistence (`CompressedHistoryStore` using `LZFSE`-compressed TSV text)
- [x] Chilltrax website stream discovery & live metadata/cover client (`ChilltraxClient`)
- [x] Audio stream player (`AVPlayer` + ICY `AVPlayerItemMetadataOutput` + `.pls` resolver + visualizer engine + `UNUserNotificationCenter` notifications)
- [x] Compact player UI with Waveform / Bars visualizer & album cover art (`CompactPlayerView`, `VisualizerView`)
- [x] Expandable searchable song history view toggled via SF Symbol (`HistoryListView`)
- [x] Settings window for discovering `chilltrax.com` broadcasts, custom stream URLs, visualizer mode, notifications, and album cover fetching (`SettingsView`)
- [x] Unit test suite (`Tests/ChilltraxTests/ChilltraxTests.swift`)

## Building & Running

### Build & Launch `.app` Bundle

```bash
make app
make run
```

### Run via SwiftPM CLI

```bash
swift run
```

### Run Unit Tests

```bash
swift test
```
