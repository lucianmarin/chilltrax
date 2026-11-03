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
            // History List Content
            if appState.filteredHistoryEntries.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: appState.historyEntries.isEmpty ? "clock.arrow.circlepath" : "magnifyingglass")
                        .font(.system(size: 26))
                        .foregroundStyle(.tertiary)
                    Text(appState.historyEntries.isEmpty ? "No songs recorded yet" : "No matching songs in history")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(
                        appState.historyEntries.isEmpty
                            ? "Songs you listen to are automatically saved to a compressed local history file."
                            : "Try searching for a different artist, song title, or album."
                    )
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(appState.filteredHistoryEntries) { entry in
                    HistoryRowView(
                        entry: entry,
                        showCover: appState.fetchAlbumCoverFromChilltrax,
                        formattedDate: Self.timeFormatter.string(from: entry.playedAt)
                    )
                }
                .listStyle(.inset)
            }
        }
    }
}

private struct HistoryRowView: View {
    let entry: SongHistoryEntry
    let showCover: Bool
    let formattedDate: String

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
        .padding(.vertical, 2)
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
