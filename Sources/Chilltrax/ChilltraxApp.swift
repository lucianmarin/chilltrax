import SwiftUI
import AppKit

@main
struct ChilltraxApp: App {
    @StateObject private var appState = AppState()

    // Write iconset if invoked with --export-iconset <dir>
    static func exportIconsetIfRequested() -> Bool {
        let args = CommandLine.arguments
        if let idx = args.firstIndex(of: "--export-iconset"), idx + 1 < args.count {
            let dir = URL(fileURLWithPath: args[idx + 1])
            try? AppIcon.writeIconset(to: dir)
            return true
        }
        return false
    }

    init() {
        if Self.exportIconsetIfRequested() {
            exit(0)
        }
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.applicationIconImage = AppIcon.generate()
    }

    var body: some Scene {
        WindowGroup("Chilltrax") {
            CompactPlayerView(appState: appState)
        }
        .defaultSize(width: ChilltraxTheme.compactWidth, height: ChilltraxTheme.compactHeight)
        .commands {
            CommandMenu("Playback") {
                Button(appState.radioPlayer.isPlaying ? "Pause" : "Play") {
                    appState.togglePlayPause()
                }
                .keyboardShortcut("p", modifiers: [.command])

                Divider()

                Button("Toggle Visualizer (Waveform / Bars)") {
                    appState.toggleVisualizerMode()
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])

                Button(appState.isHistoryExpanded ? "Hide Song History" : "Show Song History") {
                    appState.toggleHistoryExpanded()
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])

                Divider()

                Button("Refresh Current Song Info") {
                    Task {
                        await appState.refreshNowPlayingMetadata()
                    }
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }

        Settings {
            SettingsView(appState: appState)
        }
    }
}
