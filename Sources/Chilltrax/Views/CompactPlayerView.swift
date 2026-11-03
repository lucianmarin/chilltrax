import SwiftUI

public struct CompactPlayerView: View {
    @ObservedObject public var appState: AppState
    @Environment(\.openSettings) private var openSettings
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHoveringArtwork: Bool = false

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Main Compact Player Card
            VStack(spacing: 12) {
                HStack(alignment: .center, spacing: 14) {
                    albumArtworkView

                    // Song Metadata + Controls
                    VStack(alignment: .leading, spacing: 4) {
                        Text(displayedSongTitle)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .help("\(displayedSongArtist) — \(displayedSongTitle)")

                        Text(displayedSongArtist)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(ChilltraxTheme.accentRed)
                            .lineLimit(1)

                        Text(displayedSongAlbum)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        if let error = appState.radioPlayer.errorMessage {
                            Text(error)
                                .font(.system(size: 11))
                                .foregroundStyle(ChilltraxTheme.accentRed)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 4)

                    // Play / Pause Primary Button (#E60E30 background color, no glow)
                    Button(action: {
                        appState.togglePlayPause()
                    }) {
                        ZStack {
                            Circle()
                                .fill(ChilltraxTheme.accentRed)
                                .frame(width: 44, height: 44)

                            Image(systemName: appState.radioPlayer.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(ChilltraxTheme.visualizerBackground(for: colorScheme))
                                .offset(x: appState.radioPlayer.isPlaying ? 0 : 1.5)
                        }
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.space, modifiers: [])
                    .help(appState.radioPlayer.isPlaying ? "Pause Stream (Space)" : "Play Stream (Space)")
                }
                .frame(height: 68)

                // Full-width Visualizer (same 68pt height as album cover)
                VisualizerView(
                    mode: appState.visualizerMode,
                    levels: appState.radioPlayer.visualizerLevels,
                    phase: appState.radioPlayer.waveformPhase,
                    isPlaying: appState.radioPlayer.isPlaying,
                    onToggleMode: { appState.toggleVisualizerMode() }
                )
                .frame(maxWidth: .infinity)
                .frame(height: 68)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 12)
            .fixedSize(horizontal: false, vertical: true)

            Divider()

            // Compact Status-Bar Style History Search Bar at the bottom of the player
            historySearchBox
                .fixedSize(horizontal: false, vertical: true)

            // Expandable Searchable History Drawer
            if appState.isHistoryExpanded {
                Divider()
                HistoryListView(appState: appState)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(
            minWidth: ChilltraxTheme.compactWidth,
            idealWidth: ChilltraxTheme.compactWidth,
            maxWidth: ChilltraxTheme.compactWidth,
            minHeight: 0,
            maxHeight: .infinity,
            alignment: .top
        )
        .clipped()
        .tint(ChilltraxTheme.accentRed)
        .background(
            WindowAccessor(
                isHistoryExpanded: appState.isHistoryExpanded,
                historyCount: appState.filteredHistoryEntries.count,
                visualizerMode: appState.visualizerMode,
                playbackStatus: appState.radioPlayer.status
            )
            .frame(width: 0, height: 0)
        )
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: {
                    openSettings()
                    NSApp.activate(ignoringOtherApps: true)
                }) {
                    statusBadge
                }
                .buttonStyle(.plain)
                .help("Station Status: \(appState.radioPlayer.status.rawValue) — Click to Open Settings (⌘,)")
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Picker("Visualizer", selection: $appState.visualizerMode) {
                    ForEach(VisualizerMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.systemImage)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .help("Visualizer Mode (Waveform or Spectrum)")

                Button(action: {
                    appState.toggleHistoryExpanded()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.arrow.circlepath")
                            .symbolVariant(appState.isHistoryExpanded ? .fill : .none)
                        Text("\(appState.historyEntries.count)")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                    }
                }
                .help(appState.isHistoryExpanded ? "Collapse Song History" : "Expand Searchable Song History")
            }
        }
    }

    private var isSongPlaying: Bool {
        appState.radioPlayer.isPlaying && appState.currentSong.isMeaningfulTrack
    }

    private var displayedSongTitle: String {
        guard isSongPlaying, !appState.currentSong.title.isEmpty else {
            return "Title"
        }
        return appState.currentSong.title
    }

    private var displayedSongArtist: String {
        guard isSongPlaying, !appState.currentSong.artist.isEmpty else {
            return "Artist"
        }
        return appState.currentSong.artist
    }

    private var displayedSongAlbum: String {
        guard isSongPlaying, !appState.currentSong.albumOrMix.isEmpty else {
            return "Album"
        }
        return appState.currentSong.albumOrMix
    }

    private var appleMusicURL: URL? {
        guard isSongPlaying else {
            return URL(string: "https://music.apple.com")
        }
        if let buyURL = appState.currentSong.buyURL {
            return buyURL
        }
        let query = [appState.currentSong.artist, appState.currentSong.title]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !query.isEmpty,
              let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return URL(string: "https://music.apple.com")
        }
        return URL(string: "https://music.apple.com/us/search?term=\(encoded)")
    }

    @ViewBuilder
    private var albumArtworkView: some View {
        Button(action: {
            if let url = appleMusicURL {
                NSWorkspace.shared.open(url)
            }
        }) {
            ZStack {
                if isSongPlaying, appState.fetchAlbumCoverFromChilltrax, let coverURL = appState.currentSong.coverURL {
                    AsyncImage(url: coverURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        case .failure, .empty:
                            defaultStationArtwork
                        @unknown default:
                            defaultStationArtwork
                        }
                    }
                } else {
                    defaultStationArtwork
                }

                if isHoveringArtwork {
                    ZStack {
                        Color.black.opacity(0.55)
                        Image(systemName: "apple.logo")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(Color.white)
                    }
                    .transition(.opacity)
                }
            }
            .frame(width: 68, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHoveringArtwork = hovering
            }
        }
        .help("Open on Apple Music")
    }

    private var defaultStationArtwork: some View {
        Image(nsImage: AppIcon.renderPlaceholderArtwork(pointSize: 136))
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fill)
    }

    private var historySearchBox: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            TextField("Search played songs by title, artist, album…", text: $appState.historySearchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))

            if !appState.historySearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !appState.filteredHistoryEntries.isEmpty {
                Text("\(appState.filteredHistoryEntries.count)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            if !appState.historySearchQuery.isEmpty {
                Button(action: {
                    appState.historySearchQuery = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(height: 43)
    }

    private var statusBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            Text(appState.radioPlayer.status.rawValue.uppercased())
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .foregroundStyle(statusColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(statusColor.opacity(0.14), in: Capsule())
        .contentShape(Capsule())
    }

    private var statusColor: Color {
        switch appState.radioPlayer.status {
        case .playing:
            return .green
        case .buffering:
            return ChilltraxTheme.accentRed
        case .paused, .idle:
            return .secondary
        case .error:
            return ChilltraxTheme.accentRed
        }
    }
}
