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
                                showCover: appState.fetchAlbumCoverFromChilltrax,
                                formattedDate: Self.timeFormatter.string(from: entry.playedAt),
                                showBottomDivider: index < displayed.count - 1 || appState.hasMoreHistoryEntries
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
    let showCover: Bool
    let formattedDate: String
    let showBottomDivider: Bool

    var body: some View {
        HStack(spacing: 10) {
            if showCover {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.07))

                    if let coverURL = entry.coverURL {
                        AsyncImage(url: coverURL) { phase in
                            if case .success(let image) = phase {
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } else {
                                Image(systemName: "music.note")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        }
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

                HStack(spacing: 5) {
                    if !entry.artist.isEmpty {
                        Text(entry.artist)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(ChilltraxTheme.accentRed)
                            .lineLimit(1)
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

                if let buyURL = entry.buyURL {
                    Link(destination: buyURL) {
                        Text("Apple Music")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(ChilltraxTheme.accentRed)
                    }
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
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.displayName, forType: .string)
            }
            if let buyURL = entry.buyURL {
                Link("Open in Apple Music", destination: buyURL)
            }
        }
    }
}
