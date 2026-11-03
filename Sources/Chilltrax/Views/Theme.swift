import SwiftUI
import AppKit

public enum ChilltraxTheme {
    /// Brand red accent color from `icon.svg` (`#E60E30`)
    public static let accentRed = Color(red: 0xE6 / 255.0, green: 0x0E / 255.0, blue: 0x30 / 255.0)
    public static let visualizerBlack = Color.black
    public static let visualizerWhite = Color.white

    public static func visualizerBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? visualizerBlack : visualizerWhite
    }

    public static func visualizerContrastColor(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? visualizerWhite : visualizerBlack
    }

    public static let compactWidth: CGFloat = 480
    public static let compactHeight: CGFloat = 216
    public static let historyRowHeight: CGFloat = 48
    public static let maxVisibleHistoryRows: Int = 6
    public static let expandedHeight: CGFloat = compactHeight + 1 + CGFloat(maxVisibleHistoryRows) * historyRowHeight

    public static func historyListHeight(forResultCount count: Int) -> CGFloat {
        let visibleRows = max(1, min(count, maxVisibleHistoryRows))
        return CGFloat(visibleRows) * historyRowHeight
    }

    public static func contentHeight(isExpanded: Bool, resultCount: Int) -> CGFloat {
        guard isExpanded else { return compactHeight }
        return compactHeight + 1 + historyListHeight(forResultCount: resultCount)
    }
}

public struct WindowAccessor: NSViewRepresentable {
    public var isHistoryExpanded: Bool
    public var historyCount: Int
    public var visualizerMode: VisualizerMode
    public var playbackStatus: RadioPlayer.PlaybackStatus

    public init(
        isHistoryExpanded: Bool,
        historyCount: Int = 0,
        visualizerMode: VisualizerMode = .spectrum,
        playbackStatus: RadioPlayer.PlaybackStatus = .idle
    ) {
        self.isHistoryExpanded = isHistoryExpanded
        self.historyCount = historyCount
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
                on: window
            )
        }
        context.coordinator.currentExpanded = isHistoryExpanded
        context.coordinator.currentResultCount = historyCount
        DispatchQueue.main.async {
            if let window = view.window {
                context.coordinator.configure(window: window)
                context.coordinator.syncSize(
                    isExpanded: isHistoryExpanded,
                    resultCount: historyCount,
                    on: window
                )
            }
        }
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.currentExpanded = isHistoryExpanded
        context.coordinator.currentResultCount = historyCount
        if let window = nsView.window {
            context.coordinator.configure(window: window)
            context.coordinator.syncSize(
                isExpanded: isHistoryExpanded,
                resultCount: historyCount,
                on: window
            )
        }
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            context.coordinator.configure(window: window)
            context.coordinator.syncSize(
                isExpanded: isHistoryExpanded,
                resultCount: historyCount,
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
            static let windowOriginX = "chilltrax.windowOriginX"
            static let windowTopY = "chilltrax.windowTopY"
        }

        let defaults: UserDefaults
        var currentExpanded: Bool = false
        var currentResultCount: Int = 0
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
                window.styleMask.insert(.fullSizeContentView)
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
            resultCount: Int = ChilltraxTheme.maxVisibleHistoryRows,
            on window: NSWindow
        ) {
            currentExpanded = isExpanded
            currentResultCount = resultCount

            let toolbarInset = max(0, window.frame.height - window.contentLayoutRect.height)
            let targetContentHeight = ChilltraxTheme.contentHeight(
                isExpanded: isExpanded,
                resultCount: resultCount
            )
            let targetWindowHeight = targetContentHeight + toolbarInset
            let fixedWidth = ChilltraxTheme.compactWidth

            let expandedChanged = (lastAppliedExpanded != isExpanded)
            let heightChanged = (lastAppliedTargetContentHeight != targetContentHeight)
            let widthDrifted = abs(window.frame.width - fixedWidth) > 0.5
            let frameHeightDrifted = abs(window.frame.height - targetWindowHeight) > 0.5

            if expandedChanged || heightChanged || widthDrifted || frameHeightDrifted {
                lastAppliedExpanded = isExpanded
                lastAppliedTargetContentHeight = targetContentHeight

                // Relax vertical min/max constraints first so setFrame never fights active window limits
                window.minSize = NSSize(
                    width: fixedWidth,
                    height: ChilltraxTheme.compactHeight + toolbarInset
                )
                window.maxSize = NSSize(
                    width: fixedWidth,
                    height: ChilltraxTheme.expandedHeight + toolbarInset
                )

                var targetFrame = window.frame
                targetFrame.size.width = fixedWidth
                targetFrame.size.height = targetWindowHeight
                // Keep top edge of the window anchored in place on screen when expanding/collapsing
                targetFrame.origin.y = window.frame.maxY - targetWindowHeight

                window.setFrame(targetFrame, display: true, animate: false)
            }

            // Disable window resizing both vertically and horizontally in all modes
            if window.styleMask.contains(.resizable) {
                window.styleMask.remove(.resizable)
            }
            window.standardWindowButton(.zoomButton)?.isEnabled = false

            window.minSize = NSSize(
                width: fixedWidth,
                height: targetWindowHeight
            )
            window.maxSize = NSSize(
                width: fixedWidth,
                height: targetWindowHeight
            )
        }
    }
}
