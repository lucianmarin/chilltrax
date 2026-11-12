import SwiftUI
import AppKit

public enum MactraxTheme {
    /// Brand red accent color average of `white.svg` and `black.svg` (`#FF0000`)
    public static let accentRed = Color(red: 0xFA / 255.0, green: 0x00 / 255.0, blue: 0x00 / 255.0)
    public static let visualizerBlack = Color.black
    public static let visualizerWhite = Color.white
    /// Neutral `#808080` gray for the third waveform and third spectrum bar color
    public static let visualizerGray = Color(red: 0x80 / 255.0, green: 0x80 / 255.0, blue: 0x80 / 255.0)

    public static func visualizerBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? visualizerBlack : visualizerWhite
    }

    public static func visualizerContrastColor(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? visualizerWhite : visualizerBlack
    }

    public static func visualizerLabelBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(white: 0.22).opacity(0.72)
            : Color(white: 0.90).opacity(0.72)
    }

    public static let compactWidth: CGFloat = 480
    public static let compactHeight: CGFloat = 172
    public static let compactNoVisualizerHeight: CGFloat = 92
    public static let visualizerSectionHeight: CGFloat = compactHeight - compactNoVisualizerHeight
    public static let searchBarSectionHeight: CGFloat = 44
    public static let historyRowHeight: CGFloat = 48
    public static let maxVisibleHistoryRows: Int = 6
    public static let expandedHeight: CGFloat = compactHeight + searchBarSectionHeight + 1 + CGFloat(maxVisibleHistoryRows) * historyRowHeight

    public static func historyListHeight(forResultCount count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        let visibleRows = min(count, maxVisibleHistoryRows)
        return CGFloat(visibleRows) * historyRowHeight
    }

    public static func contentHeight(
        isExpanded: Bool,
        resultCount: Int,
        showSearchBar: Bool = false,
        showVisualizer: Bool = true
    ) -> CGFloat {
        let playerCardHeight = showVisualizer ? compactHeight : compactNoVisualizerHeight
        let baseHeight = (showSearchBar || isExpanded) ? (playerCardHeight + searchBarSectionHeight) : playerCardHeight
        guard isExpanded, resultCount > 0 else { return baseHeight }
        return baseHeight + 1 + historyListHeight(forResultCount: resultCount)
    }
}

public struct WindowAccessor: NSViewRepresentable {
    public var isHistoryExpanded: Bool
    public var historyCount: Int
    public var showSearchBar: Bool
    public var visualizerMode: VisualizerMode
    public var playbackStatus: RadioPlayer.PlaybackStatus

    public init(
        isHistoryExpanded: Bool,
        historyCount: Int = 0,
        showSearchBar: Bool = false,
        visualizerMode: VisualizerMode = .spectrum,
        playbackStatus: RadioPlayer.PlaybackStatus = .idle
    ) {
        self.isHistoryExpanded = isHistoryExpanded
        self.historyCount = historyCount
        self.showSearchBar = showSearchBar
        self.visualizerMode = visualizerMode
        self.playbackStatus = playbackStatus
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public func makeNSView(context: Context) -> NSView {
        let view = WindowObserverView()
        view.onWindowEvent = { [weak coordinator = context.coordinator] window in
            guard let coordinator else { return }
            coordinator.configure(window: window)
            coordinator.syncSize(
                isExpanded: coordinator.currentExpanded,
                resultCount: coordinator.currentResultCount,
                showSearchBar: coordinator.currentShowSearchBar,
                showVisualizer: coordinator.currentShowVisualizer,
                on: window
            )
        }
        context.coordinator.currentExpanded = isHistoryExpanded
        context.coordinator.currentResultCount = historyCount
        context.coordinator.currentShowSearchBar = showSearchBar
        context.coordinator.currentShowVisualizer = visualizerMode.isVisible
        DispatchQueue.main.async {
            if let window = view.window {
                context.coordinator.configure(window: window)
                context.coordinator.syncSize(
                    isExpanded: isHistoryExpanded,
                    resultCount: historyCount,
                    showSearchBar: showSearchBar,
                    showVisualizer: visualizerMode.isVisible,
                    on: window
                )
            }
        }
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        let showVisualizer = visualizerMode.isVisible
        let stateChanged = context.coordinator.currentExpanded != isHistoryExpanded
            || context.coordinator.currentResultCount != historyCount
            || context.coordinator.currentShowSearchBar != showSearchBar
            || context.coordinator.currentShowVisualizer != showVisualizer
            || context.coordinator.currentPlaybackStatus != playbackStatus

        context.coordinator.currentExpanded = isHistoryExpanded
        context.coordinator.currentResultCount = historyCount
        context.coordinator.currentShowSearchBar = showSearchBar
        context.coordinator.currentShowVisualizer = showVisualizer
        context.coordinator.currentPlaybackStatus = playbackStatus

        guard stateChanged else { return }

        if let window = nsView.window {
            context.coordinator.configure(window: window)
            context.coordinator.syncSize(
                isExpanded: isHistoryExpanded,
                resultCount: historyCount,
                showSearchBar: showSearchBar,
                showVisualizer: showVisualizer,
                on: window
            )
        }
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            context.coordinator.configure(window: window)
            context.coordinator.syncSize(
                isExpanded: isHistoryExpanded,
                resultCount: historyCount,
                showSearchBar: showSearchBar,
                showVisualizer: showVisualizer,
                on: window
            )
        }
    }

    public final class WindowObserverView: NSView {
        var onWindowEvent: ((NSWindow) -> Void)?
        private var isAsyncSyncScheduled = false

        public override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window {
                onWindowEvent?(window)
                schedulePostLayoutSync()
            }
        }

        public override func layout() {
            super.layout()
            if let window {
                onWindowEvent?(window)
                schedulePostLayoutSync()
            }
        }

        private func schedulePostLayoutSync() {
            guard !isAsyncSyncScheduled else { return }
            isAsyncSyncScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isAsyncSyncScheduled = false
                if let window = self.window {
                    self.onWindowEvent?(window)
                }
            }
        }
    }

    @MainActor
    public final class Coordinator {
        private enum DefaultsKeys {
            static let windowOriginX = "mactrax.windowOriginX"
            static let windowTopY = "mactrax.windowTopY"
        }

        let defaults: UserDefaults
        var currentExpanded: Bool = false
        var currentResultCount: Int = 0
        var currentShowSearchBar: Bool = false
        var currentShowVisualizer: Bool = true
        var currentPlaybackStatus: RadioPlayer.PlaybackStatus = .idle
        var lastAppliedExpanded: Bool?
        var lastAppliedTargetContentHeight: CGFloat?
        var configuredWindowNumbers = Set<Int>()
        nonisolated(unsafe) private var windowObservers = [NSObjectProtocol]()

        public init(defaults: UserDefaults = .standard) {
            self.defaults = defaults
        }

        deinit {
            for observer in windowObservers {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        @MainActor
        public func saveWindowPosition(_ window: NSWindow) {
            defaults.set(Double(window.frame.minX), forKey: DefaultsKeys.windowOriginX)
            defaults.set(Double(window.frame.maxY), forKey: DefaultsKeys.windowTopY)
        }

        @MainActor
        public func restoreWindowPositionIfSaved(_ window: NSWindow) {
            guard defaults.object(forKey: DefaultsKeys.windowOriginX) != nil,
                  defaults.object(forKey: DefaultsKeys.windowTopY) != nil else {
                return
            }
            let savedX = CGFloat(defaults.double(forKey: DefaultsKeys.windowOriginX))
            let savedTopY = CGFloat(defaults.double(forKey: DefaultsKeys.windowTopY))
            window.setFrameTopLeftPoint(NSPoint(x: savedX, y: savedTopY))
        }

        @MainActor
        func configure(window: NSWindow) {
            if !configuredWindowNumbers.contains(window.windowNumber) {
                configuredWindowNumbers.insert(window.windowNumber)

                window.titleVisibility = .hidden
                window.titlebarAppearsTransparent = false
                window.toolbarStyle = .unified
                window.styleMask.remove(.fullSizeContentView)
                window.styleMask.remove(.resizable)
                window.standardWindowButton(.zoomButton)?.isEnabled = false
                window.isMovableByWindowBackground = true

                restoreWindowPositionIfSaved(window)

                let center = NotificationCenter.default
                let moveObserver = center.addObserver(
                    forName: NSWindow.didMoveNotification,
                    object: window,
                    queue: .main
                ) { [weak self, weak window] _ in
                    MainActor.assumeIsolated {
                        guard let self, let window else { return }
                        self.saveWindowPosition(window)
                    }
                }
                let closeObserver = center.addObserver(
                    forName: NSWindow.willCloseNotification,
                    object: window,
                    queue: .main
                ) { [weak self, weak window] _ in
                    MainActor.assumeIsolated {
                        guard let self, let window else { return }
                        self.saveWindowPosition(window)
                    }
                }
                let terminateObserver = center.addObserver(
                    forName: NSApplication.willTerminateNotification,
                    object: nil,
                    queue: .main
                ) { [weak self, weak window] _ in
                    MainActor.assumeIsolated {
                        guard let self, let window else { return }
                        self.saveWindowPosition(window)
                    }
                }
                windowObservers.append(contentsOf: [moveObserver, closeObserver, terminateObserver])
            }

            if let toolbar = window.toolbar {
                toolbar.showsBaselineSeparator = false
                if toolbar.items.first?.itemIdentifier == .flexibleSpace {
                    toolbar.removeItem(at: 0)
                }
                if toolbar.items.count >= 2,
                   !toolbar.items.contains(where: { $0.itemIdentifier == .flexibleSpace }) {
                    toolbar.insertItem(withItemIdentifier: .flexibleSpace, at: 1)
                }
            }
        }

        @MainActor
        func syncSize(
            isExpanded: Bool,
            resultCount: Int = MactraxTheme.maxVisibleHistoryRows,
            showSearchBar: Bool = false,
            showVisualizer: Bool = true,
            on window: NSWindow
        ) {
            currentExpanded = isExpanded
            currentResultCount = resultCount
            currentShowSearchBar = showSearchBar
            currentShowVisualizer = showVisualizer

            let toolbarInset = max(0, window.frame.height - window.contentLayoutRect.height)
            let targetContentHeight = MactraxTheme.contentHeight(
                isExpanded: isExpanded,
                resultCount: resultCount,
                showSearchBar: showSearchBar,
                showVisualizer: showVisualizer
            )
            let targetWindowHeight = targetContentHeight + toolbarInset
            let fixedWidth = MactraxTheme.compactWidth
            let fixedSize = NSSize(width: fixedWidth, height: targetWindowHeight)

            let expandedChanged = (lastAppliedExpanded != isExpanded)
            let heightChanged = (lastAppliedTargetContentHeight != targetContentHeight)
            let widthDrifted = abs(window.frame.width - fixedWidth) > 0.5
            let frameHeightDrifted = abs(window.frame.height - targetWindowHeight) > 0.5

            if expandedChanged || heightChanged || widthDrifted || frameHeightDrifted {
                lastAppliedExpanded = isExpanded
                lastAppliedTargetContentHeight = targetContentHeight

                window.minSize = fixedSize
                window.maxSize = fixedSize

                var targetFrame = window.frame
                targetFrame.size = fixedSize
                // Keep top edge of the window anchored in place on screen when expanding/collapsing
                targetFrame.origin.y = window.frame.maxY - targetWindowHeight

                window.setFrame(targetFrame, display: true, animate: false)
                window.contentView?.layoutSubtreeIfNeeded()
            }

            if window.styleMask.contains(.resizable) {
                window.styleMask.remove(.resizable)
            }
            if window.minSize != fixedSize {
                window.minSize = fixedSize
            }
            if window.maxSize != fixedSize {
                window.maxSize = fixedSize
            }
        }
    }
}
