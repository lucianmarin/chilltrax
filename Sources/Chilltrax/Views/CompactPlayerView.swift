import SwiftUI

public struct CompactPlayerView: View {
    @ObservedObject public var appState: AppState
    @Environment(\.openSettings) private var openSettings
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHoveringArtwork: Bool = false
    @FocusState private var isSearchFieldFocused: Bool

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
                    VStack(alignment: .leading, spacing: 3) {
                        Text(displayedSongTitle)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                appState.copyCurrentSongToClipboard()
                            }
                            .help(songCopyHelpText)

                        songInfoSeparator

                        Text(displayedSongArtist)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(ChilltraxTheme.accentRed)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                appState.copyCurrentSongToClipboard()
                            }
                            .help(songCopyHelpText)

                        songInfoSeparator

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
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Play / Pause Primary Button (#FA0000 background color, no glow)
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
                    trailLevels: appState.radioPlayer.visualizerTrailLevels,
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

            if appState.isSearchBarVisible {
                Divider()

                // Compact Status-Bar Style History Search Bar at the bottom of the player
                historySearchBox
                    .fixedSize(horizontal: false, vertical: true)
                    .onAppear {
                        DispatchQueue.main.async {
                            isSearchFieldFocused = true
                        }
                    }
            }

            // Expandable Searchable History Drawer
            if appState.isHistoryExpanded && !appState.filteredHistoryEntries.isEmpty {
                Divider()
                HistoryListView(appState: appState)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(
            width: ChilltraxTheme.compactWidth,
            height: currentContentHeight,
            alignment: .top
        )
        .clipped()
        .tint(ChilltraxTheme.accentRed)
        .onChange(of: appState.isHistoryExpanded) { _, isExpanded in
            if isExpanded {
                DispatchQueue.main.async {
                    isSearchFieldFocused = true
                }
            } else {
                isSearchFieldFocused = false
            }
        }
        .background(
            WindowAccessor(
                isHistoryExpanded: appState.isHistoryExpanded,
                historyCount: appState.filteredHistoryEntries.count,
                showSearchBar: appState.isSearchBarVisible,
                visualizerMode: appState.visualizerMode,
                playbackStatus: appState.radioPlayer.status
            )
            .frame(width: 0, height: 0)
        )
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: {
                    appState.handleToolbarStatusTap {
                        openSettings()
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }) {
                    statusBadge
                }
                .buttonStyle(.plain)
                .help(statusBadgeHelpText)
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

                Toggle(isOn: Binding(
                    get: { appState.isHistoryButtonHighlighted },
                    set: { _ in appState.toggleHistoryExpanded() }
                )) {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.arrow.circlepath")
                        Text("\(appState.historyEntries.count)")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                    }
                }
                .toggleStyle(.button)
                .tint(nil)
                .help(appState.isHistoryExpanded ? "Collapse Song History" : "Expand Searchable Song History")
            }
        }
    }

    private var isSongPlaying: Bool {
        appState.radioPlayer.isPlaying && appState.currentSong.isMeaningfulTrack
    }

    private var currentContentHeight: CGFloat {
        ChilltraxTheme.contentHeight(
            isExpanded: appState.isHistoryExpanded,
            resultCount: appState.filteredHistoryEntries.count,
            showSearchBar: appState.isSearchBarVisible
        )
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

    private var songInfoSeparator: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
    }

    private var appleMusicURL: URL? {
        appState.currentSongAppleMusicURL
    }

    private var songCopyHelpText: String {
        guard let formatted = appState.currentSongFormattedTitle else {
            return ""
        }
        return "Copy \"\(formatted)\" to Clipboard"
    }

    @ViewBuilder
    private var albumArtworkView: some View {
        Button(action: {
            if isSongPlaying, let url = appleMusicURL {
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

                if isSongPlaying && isHoveringArtwork {
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
                isHoveringArtwork = hovering && isSongPlaying
            }
        }
        .help(isSongPlaying ? "Open on Apple Music" : "")
    }

    private var defaultStationArtwork: some View {
        ZStack {
            ChilltraxTheme.visualizerBackground(for: colorScheme)
            Image(systemName: "apple.logo")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(ChilltraxTheme.visualizerContrastColor(for: colorScheme))
        }
    }

    private var historySearchBox: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            TextField("Search played songs by title, artist, album…", text: $appState.historySearchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .focused($isSearchFieldFocused)

            if !appState.historySearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
            Text(appState.toolbarStatusLabel)
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .foregroundStyle(statusColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(statusColor.opacity(0.14), in: Capsule())
        .contentShape(Capsule())
    }

    private var statusBadgeHelpText: String {
        if appState.canSwitchStationFromToolbarStatus {
            return "Station Status: \(appState.toolbarStatusLabel) — Click to Switch to \(appState.selectedStation.nextStation.title)"
        }
        return "Station Status: \(appState.toolbarStatusLabel) — Click to Open Settings (⌘,)"
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
