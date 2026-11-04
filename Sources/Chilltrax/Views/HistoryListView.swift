import SwiftUI
import AppKit

public struct HistoryListView: View {
    @ObservedObject public var appState: AppState

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(spacing: 0) {
            if appState.filteredHistoryEntries.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: appState.historyEntries.isEmpty ? "clock.arrow.circlepath" : "magnifyingglass")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                    Text(appState.historyEntries.isEmpty ? "No songs recorded yet" : "No matching songs in history")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .frame(height: ChilltraxTheme.historyRowHeight)
            } else {
                ScrollView(.vertical, showsIndicators: appState.displayedHistoryEntries.count > ChilltraxTheme.maxVisibleHistoryRows) {
                    LazyVStack(spacing: 0) {
                        let displayed = appState.displayedHistoryEntries
                        ForEach(Array(displayed.enumerated()), id: \.element.id) { index, entry in
                            HistoryRowView(
                                entry: entry,
                                badgeLabel: appState.historyBadgeLabel(for: entry),
                                showCover: appState.fetchAlbumCoverFromChilltrax,
                                coverCache: appState.coverCache,
                                formattedDate: Self.timeFormatter.string(from: entry.playedAt),
                                showBottomDivider: index < displayed.count - 1 || appState.hasMoreHistoryEntries,
                                onCopySongInfo: {
                                    appState.copyHistoryEntryToClipboard(entry)
                                }
                            )
                            .frame(height: ChilltraxTheme.historyRowHeight)
                            .onAppear {
                                appState.loadMoreHistoryIfNeeded(currentEntry: entry)
                            }
                        }
                    }
                }
                .frame(height: ChilltraxTheme.historyListHeight(forResultCount: appState.displayedHistoryEntries.count))
            }
        }
    }
}

private struct HistoryRowView: View {
    let entry: SongHistoryEntry
    let badgeLabel: String
    let showCover: Bool
    let coverCache: AlbumCoverCache
    let formattedDate: String
    let showBottomDivider: Bool
    let onCopySongInfo: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if showCover {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.07))

                    if let coverURL = entry.coverURL {
                        CachedHistoryCoverView(url: coverURL, coverCache: coverCache)
                    } else {
                        Image(systemName: "music.note")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title.isEmpty ? entry.displayName : entry.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onCopySongInfo()
                    }
                    .help("Copy \"\(entry.clipboardText)\" to Clipboard")

                HStack(spacing: 5) {
                    if !entry.artist.isEmpty {
                        Text(entry.artist)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(ChilltraxTheme.accentRed)
                            .lineLimit(1)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onCopySongInfo()
                            }
                            .help("Copy \"\(entry.clipboardText)\" to Clipboard")
                    }
                    if !entry.albumOrMix.isEmpty {
                        Text("• \(entry.albumOrMix)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 3) {
                Text(formattedDate)
                    .font(.system(size: 10.5, design: .rounded))
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    if let buyURL = entry.buyURL {
                        Link(destination: buyURL) {
                            Text("Apple Music")
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(ChilltraxTheme.accentRed)
                        }
                    }

                    Button(action: {
                        onCopySongInfo()
                    }) {
                        Text(badgeLabel)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4.5)
                            .padding(.vertical, 1.5)
                            .background(
                                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                                    .fill(Color.primary.opacity(0.07))
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Copy \"\(entry.clipboardText)\" to Clipboard")
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            if showBottomDivider {
                Divider()
                    .padding(.leading, 16)
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Copy Song Name") {
                onCopySongInfo()
            }
            if let buyURL = entry.buyURL {
                Link("Open in Apple Music", destination: buyURL)
            }
        }
    }
}

private struct CachedHistoryCoverView: View {
    let url: URL
    let coverCache: AlbumCoverCache
    @State private var loadedImage: NSImage?

    var body: some View {
        Group {
            if let image = loadedImage ?? coverCache.cachedImage(for: url) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: url) {
            if let cached = coverCache.cachedImage(for: url) {
                loadedImage = cached
            } else {
                loadedImage = await coverCache.image(for: url)
            }
        }
    }
}

