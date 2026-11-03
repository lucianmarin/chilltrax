import SwiftUI
import AppKit

public struct SettingsView: View {
    @ObservedObject public var appState: AppState
    @State private var customStationName: String = ""
    @State private var customStationURL: String = ""
    @State private var customStreamValidationMessage: String?

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
            Section("Active Broadcast Stream") {
                Picker("Current Station", selection: Binding(
                    get: { appState.selectedStream },
                    set: { appState.selectStream($0) }
                )) {
                    ForEach(appState.allAvailableStreams) { stream in
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
            }

            Section("Find Broadcast from chilltrax.com") {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Discover Official Chilltrax Streams")
                            .font(.subheadline.weight(.medium))
                        Text("Scans https://www.chilltrax.com for live MP3, AAC+, and SSL broadcast stream links.")
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

            Section("Configure Custom Station URL Stream") {
                TextField("Station Name (optional)", text: $customStationName, prompt: Text("e.g. SomaFM Groove Salad"))
                TextField("Stream URL (http:// or https://)", text: $customStationURL, prompt: Text("https://ice1.somafm.com/groovesalad-128-mp3"))

                HStack {
                    if let validation = customStreamValidationMessage {
                        Text(validation)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    Spacer()
                    Button("Use Custom Stream") {
                        let ok = appState.addAndSelectCustomStream(
                            name: customStationName,
                            urlString: customStationURL
                        )
                        if ok {
                            customStationName = ""
                            customStationURL = ""
                            customStreamValidationMessage = nil
                        } else {
                            customStreamValidationMessage = "Please enter a valid http:// or https:// stream URL."
                        }
                    }
                    .disabled(customStationURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if !appState.customStreams.isEmpty {
                    ForEach(appState.customStreams) { custom in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(custom.name)
                                    .font(.caption.weight(.semibold))
                                Text(custom.urlString)
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Select") {
                                appState.selectStream(custom)
                            }
                            .controlSize(.small)

                            Button(role: .destructive) {
                                appState.removeCustomStream(custom)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
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
                    "Fetch current playing song album cover from chilltrax.com",
                    isOn: $appState.fetchAlbumCoverFromChilltrax
                )

                Toggle(
                    "Send macOS notification on song change",
                    isOn: $appState.notifyOnSongChange
                )
            }

            Section("Compressed Song History File") {
                LabeledContent("Recorded Songs") {
                    Text("\(appState.historyEntries.count)")
                        .font(.system(.body, design: .rounded).weight(.semibold))
                }

                LabeledContent("Compressed File Size") {
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
                    Button("Clear Song History", role: .destructive) {
                        appState.clearHistory()
                    }
                    .disabled(appState.historyEntries.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
    }
}
