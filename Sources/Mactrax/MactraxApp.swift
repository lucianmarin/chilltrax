import SwiftUI
import AppKit

@MainActor
public final class MactraxAppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    public weak var appState: AppState?
    private var appearanceObservation: NSKeyValueObservation?

    public override init() {
        super.init()
    }

    public init(appState: AppState) {
        self.appState = appState
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        startObservingAppearance()
    }

    public func startObservingAppearance() {
        updateApplicationIcon(for: NSApplication.shared.effectiveAppearance)
        appearanceObservation = NSApplication.shared.observe(\.effectiveAppearance, options: [.new]) { [weak self] app, _ in
            Task { @MainActor [weak self] in
                self?.updateApplicationIcon(for: app.effectiveAppearance)
            }
        }
    }

    public func updateApplicationIcon(for nsAppearance: NSAppearance?) {
        let iconAppearance = AppIcon.appearance(for: nsAppearance)
        NSApplication.shared.applicationIconImage = AppIcon.generate(appearance: iconAppearance)
    }

    public func makeDockMenu() -> NSMenu? {
        guard let appState else { return nil }
        let menu = NSMenu(title: "Mactrax")
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

        let playPauseTitle = appState.radioPlayer.isPlaying ? "Stop" : "Play"
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
            title: "Copy to Clipboard",
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
struct MactraxApp: App {
    @NSApplicationDelegateAdaptor(MactraxAppDelegate.self) private var appDelegate
    @StateObject private var appState: AppState

    // Write iconset or Icon Composer bundle if invoked with --export-iconset <dir> or --export-icon-bundle <dir>
    static func exportIconsetIfRequested() -> Bool {
        let args = CommandLine.arguments
        if let idx = args.firstIndex(of: "--export-icon-bundle"), idx + 1 < args.count {
            let dir = URL(fileURLWithPath: args[idx + 1])
            try? AppIcon.writeIconComposerBundle(to: dir)
            return true
        }
        if let idx = args.firstIndex(of: "--export-iconset"), idx + 1 < args.count {
            let dir = URL(fileURLWithPath: args[idx + 1])
            let appearance: AppIcon.Appearance = args.contains("--dark") ? .dark : .light
            try? AppIcon.writeIconset(to: dir, appearance: appearance)
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
        appDelegate.startObservingAppearance()
    }

    var body: some Scene {
        WindowGroup("Mactrax") {
            CompactPlayerView(appState: appState)
        }
        .defaultSize(width: MactraxTheme.compactWidth, height: MactraxTheme.compactHeight)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .toolbar) {
                Button(appState.fetchAlbumCoverFromMactrax ? "Hide Album Covers" : "Show Album Covers") {
                    appState.toggleAlbumCovers()
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])

                Button(appState.isVisualizerVisible ? "Hide Visualizer" : "Show Visualizer") {
                    appState.toggleVisualizerVisibility()
                }
                .keyboardShortcut("v", modifiers: [.command, .option])

                Button(appState.isHistoryExpanded ? "Hide Song History" : "Show Song History") {
                    appState.toggleHistoryExpanded()
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])
            }

            CommandMenu("Playback") {
                Button(appState.radioPlayer.isPlaying ? "Stop" : "Play") {
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
                .disabled(!appState.isVisualizerVisible)

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

                Button("Copy to Clipboard") {
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
