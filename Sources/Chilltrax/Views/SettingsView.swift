import SwiftUI
import AppKit

public struct SettingsView: View {
    @ObservedObject public var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        TabView {
            broadcastSettingsTab
                .tabItem {
                    Label("Broadcast & Station", systemImage: "antenna.radiowaves.left.and.right")
                }

            preferencesTab
                .tabItem {
                    Label("Player & Storage", systemImage: "slider.horizontal.3")
                }
        }
        .frame(width: 540, height: 430)
        .padding(12)
        .tint(ChilltraxTheme.accentRed)
    }

    private var broadcastSettingsTab: some View {
        Form {
            Section("Radio Station") {
                Picker("Station", selection: Binding(
                    get: { appState.selectedStation },
                    set: { appState.selectStation($0) }
                )) {
                    ForEach(RadioStation.allCases) { station in
                        Text(station.title)
                            .tag(station)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Active Broadcast Stream") {
                Picker("Broadcast Stream", selection: Binding(
                    get: { appState.selectedStream },
                    set: { appState.selectStream($0) }
                )) {
                    ForEach(appState.streamsForSelectedStation) { stream in
                        Text("\(stream.name) (\(stream.urlString))")
                            .tag(stream)
                    }
                }

                HStack {
                    Text("Stream URL:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(appState.selectedStream.urlString)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                }

                HStack {
                    Text("Song Info API:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(appState.currentStationAPIEndpoints.songInfoURLString)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }

            Section("Find Broadcasts from chilltrax.com & radiodanz.com") {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Discover Official Broadcasts & API URLs")
                            .font(.subheadline.weight(.medium))
                        Text("Scans chilltrax.com and radiodanz.com for live broadcast stream links and API URL changes.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(action: {
                        Task {
                            await appState.discoverBroadcastsFromChilltraxWebsite()
                        }
                    }) {
                        HStack(spacing: 6) {
                            if appState.isDiscoveringBroadcasts {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "dot.radiowaves.left.and.right")
                            }
                            Text(appState.isDiscoveringBroadcasts ? "Scanning…" : "Find Broadcasts")
                        }
                    }
                    .disabled(appState.isDiscoveringBroadcasts)
                }

                if let status = appState.discoveryStatusMessage {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(ChilltraxTheme.accentRed)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var preferencesTab: some View {
        Form {
            Section("Audio Visualizer") {
                Picker("Visualizer Style", selection: $appState.visualizerMode) {
                    ForEach(VisualizerMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.systemImage)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Metadata, Artwork & Notifications") {
                Toggle(
                    "Fetch current playing song album cover",
                    isOn: $appState.fetchAlbumCoverFromChilltrax
                )

                Toggle(
                    "Send macOS notification on song change",
                    isOn: $appState.notifyOnSongChange
                )
            }

            Section("Covers Cache & History File") {
                LabeledContent("Commit Song After Playing") {
                    HStack(spacing: 8) {
                        TextField(
                            "",
                            value: $appState.historyCommitDelaySeconds,
                            format: .number
                        )
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 52)
                        .multilineTextAlignment(.trailing)

                        Stepper(
                            "",
                            value: $appState.historyCommitDelaySeconds,
                            in: 0...99,
                            step: 1
                        )
                        .labelsHidden()

                        Text("seconds")
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                }

                LabeledContent("Recorded Songs") {
                    Text("\(appState.historyEntries.count)")
                        .font(.system(.body, design: .rounded).weight(.semibold))
                }

                LabeledContent("Album Covers Cache Size") {
                    Text(ByteCountFormatter.string(fromByteCount: appState.coverCache.cachedFilesSizeBytes, countStyle: .file))
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Compressed History Size") {
                    Text(ByteCountFormatter.string(fromByteCount: appState.historyStore.compressedFileSizeBytes, countStyle: .file))
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Storage Path") {
                    Text(appState.historyStore.fileURL.path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(appState.historyStore.fileURL.path)
                }

                HStack {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([appState.historyStore.fileURL])
                    }
                    Spacer()
                    Button("Clear Cache & History", role: .destructive) {
                        appState.clearHistory()
                    }
                    .disabled(appState.historyEntries.isEmpty && appState.coverCache.cachedFileCount == 0)
                }
            }
        }
        .formStyle(.grouped)
    }
}
