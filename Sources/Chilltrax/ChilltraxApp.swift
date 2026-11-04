import SwiftUI
import AppKit

@MainActor
public final class ChilltraxAppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    public weak var appState: AppState?

    public override init() {
        super.init()
    }

    public init(appState: AppState) {
        self.appState = appState
        super.init()
    }

    public func makeDockMenu() -> NSMenu? {
        guard let appState else { return nil }
        let menu = NSMenu(title: "Chilltrax")
        menu.autoenablesItems = false

        if appState.radioPlayer.isPlaying, appState.currentSong.isMeaningfulTrack {
            let title = appState.currentSong.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty {
                let titleItem = NSMenuItem(
                    title: title,
                    action: nil,
                    keyEquivalent: ""
                )
                titleItem.isEnabled = false
                menu.addItem(titleItem)
            }

            let artist = appState.currentSong.artist.trimmingCharacters(in: .whitespacesAndNewlines)
            if !artist.isEmpty {
                let artistItem = NSMenuItem(
                    title: artist,
                    action: nil,
                    keyEquivalent: ""
                )
                artistItem.isEnabled = false
                menu.addItem(artistItem)
            }
        }

        let playPauseTitle = appState.radioPlayer.isPlaying ? "Pause" : "Play"
        let playPauseItem = NSMenuItem(
            title: playPauseTitle,
            action: #selector(handleDockPlayPause(_:)),
            keyEquivalent: ""
        )
        playPauseItem.target = self
        playPauseItem.isEnabled = true
        menu.addItem(playPauseItem)

        let nextStation = appState.selectedStation.nextStation
        let switchStationItem = NSMenuItem(
            title: "Switch to \(nextStation.title)",
            action: #selector(handleDockSwitchStation(_:)),
            keyEquivalent: ""
        )
        switchStationItem.target = self
        switchStationItem.isEnabled = true
        menu.addItem(switchStationItem)

        menu.addItem(.separator())

        let canOpenAppleMusic = appState.canOpenCurrentSongOnAppleMusic
        let appleMusicItem = NSMenuItem(
            title: "Open on Apple Music",
            action: canOpenAppleMusic ? #selector(handleDockOpenAppleMusic(_:)) : nil,
            keyEquivalent: ""
        )
        appleMusicItem.target = canOpenAppleMusic ? self : nil
        appleMusicItem.isEnabled = canOpenAppleMusic
        menu.addItem(appleMusicItem)

        let canCopySong = appState.canCopyCurrentSongToClipboard
        let copyItem = NSMenuItem(
            title: "Copy to clipboard",
            action: canCopySong ? #selector(handleDockCopyToClipboard(_:)) : nil,
            keyEquivalent: ""
        )
        copyItem.target = canCopySong ? self : nil
        copyItem.isEnabled = canCopySong
        menu.addItem(copyItem)

        return menu
    }

    public func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        makeDockMenu()
    }

    @objc public func handleDockPlayPause(_ sender: Any?) {
        appState?.togglePlayPause()
    }

    @objc public func handleDockSwitchStation(_ sender: Any?) {
        appState?.toggleStation()
    }

    @objc public func handleDockOpenAppleMusic(_ sender: Any?) {
        appState?.openCurrentSongOnAppleMusic()
    }

    @objc public func handleDockCopyToClipboard(_ sender: Any?) {
        appState?.copyCurrentSongToClipboard()
    }

    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(handleDockOpenAppleMusic(_:)) {
            return appState?.canOpenCurrentSongOnAppleMusic ?? false
        }
        if menuItem.action == #selector(handleDockCopyToClipboard(_:)) {
            return appState?.canCopyCurrentSongToClipboard ?? false
        }
        return true
    }
}

@main
struct ChilltraxApp: App {
    @NSApplicationDelegateAdaptor(ChilltraxAppDelegate.self) private var appDelegate
    @StateObject private var appState: AppState

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
        let state = AppState()
        _appState = StateObject(wrappedValue: state)
        appDelegate.appState = state
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.applicationIconImage = AppIcon.generate()
    }

    var body: some Scene {
        WindowGroup("Chilltrax") {
            CompactPlayerView(appState: appState)
        }
        .defaultSize(width: ChilltraxTheme.compactWidth, height: ChilltraxTheme.compactHeight)
        .windowResizability(.contentSize)
        .commands {
            CommandMenu("Playback") {
                Button(appState.radioPlayer.isPlaying ? "Pause" : "Play") {
                    appState.togglePlayPause()
                }
                .keyboardShortcut("p", modifiers: [.command])

                Divider()

                Button("Toggle Station (Chilltrax / Radio Danz)") {
                    appState.toggleStation()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Button("Toggle Visualizer (Waveform / Spectrum)") {
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

                Divider()

                Button("Open on Apple Music") {
                    appState.openCurrentSongOnAppleMusic()
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .disabled(!appState.canOpenCurrentSongOnAppleMusic)

                Button("Copy to clipboard") {
                    appState.copyCurrentSongToClipboard()
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(!appState.canCopyCurrentSongToClipboard)
            }
        }

        Settings {
            SettingsView(appState: appState)
        }
        .windowResizability(.contentSize)
    }
}
