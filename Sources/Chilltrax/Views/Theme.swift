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
    public static let expandedHeight: CGFloat = 520
}

public struct WindowAccessor: NSViewRepresentable {
    public var isHistoryExpanded: Bool
    public var historyCount: Int
    public var visualizerMode: VisualizerMode
    public var playbackStatus: RadioPlayer.PlaybackStatus

    public init(
        isHistoryExpanded: Bool,
        historyCount: Int = 0,
        visualizerMode: VisualizerMode = .bars,
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
            coordinator.syncSize(isExpanded: coordinator.currentExpanded, on: window)
        }
        context.coordinator.currentExpanded = isHistoryExpanded
        DispatchQueue.main.async {
            if let window = view.window {
                context.coordinator.configure(window: window)
                context.coordinator.syncSize(isExpanded: isHistoryExpanded, on: window)
            }
        }
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.currentExpanded = isHistoryExpanded
        if let window = nsView.window {
            context.coordinator.configure(window: window)
            context.coordinator.syncSize(isExpanded: isHistoryExpanded, on: window)
        }
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            context.coordinator.configure(window: window)
            context.coordinator.syncSize(isExpanded: isHistoryExpanded, on: window)
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

    public final class Coordinator {
        var currentExpanded: Bool = false
        var lastAppliedExpanded: Bool?
        var configuredWindowNumbers = Set<Int>()

        @MainActor
        func configure(window: NSWindow) {
            if !configuredWindowNumbers.contains(window.windowNumber) {
                configuredWindowNumbers.insert(window.windowNumber)

                window.titleVisibility = .hidden
                window.titlebarAppearsTransparent = false
                window.toolbarStyle = .unified
                window.styleMask.insert(.fullSizeContentView)
                window.isMovableByWindowBackground = true
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
        func syncSize(isExpanded: Bool, on window: NSWindow) {
            currentExpanded = isExpanded
            let toolbarInset = max(0, window.frame.height - window.contentLayoutRect.height)
            let targetContentHeight = isExpanded ? ChilltraxTheme.expandedHeight : ChilltraxTheme.compactHeight
            let targetWindowHeight = targetContentHeight + toolbarInset
            let fixedWidth = ChilltraxTheme.compactWidth
            let minContentHeight: CGFloat = isExpanded ? 320 : ChilltraxTheme.compactHeight
            let maxContentHeight: CGFloat = isExpanded ? 900 : ChilltraxTheme.compactHeight

            let expandedChanged = (lastAppliedExpanded != isExpanded)
            let widthDrifted = abs(window.frame.width - fixedWidth) > 0.5
            let compactHeightDrifted = !isExpanded && abs(window.frame.height - targetWindowHeight) > 0.5

            if expandedChanged || widthDrifted || compactHeightDrifted {
                lastAppliedExpanded = isExpanded

                // Relax vertical min/max constraints first so setFrame never fights active window limits
                window.minSize = NSSize(
                    width: fixedWidth,
                    height: ChilltraxTheme.compactHeight + toolbarInset
                )
                window.maxSize = NSSize(
                    width: fixedWidth,
                    height: 900 + toolbarInset
                )

                var targetFrame = window.frame
                targetFrame.size.width = fixedWidth
                if expandedChanged || !isExpanded {
                    targetFrame.size.height = targetWindowHeight
                    // Keep top edge of the window anchored in place on screen when expanding/collapsing
                    targetFrame.origin.y = window.frame.maxY - targetWindowHeight
                }

                window.setFrame(targetFrame, display: true, animate: false)
            }

            // Always enforce styleMask and horizontal/vertical size locks after NSHostingView layout passes
            if isExpanded {
                if !window.styleMask.contains(.resizable) {
                    window.styleMask.insert(.resizable)
                }
                window.standardWindowButton(.zoomButton)?.isEnabled = true
            } else {
                if window.styleMask.contains(.resizable) {
                    window.styleMask.remove(.resizable)
                }
                window.standardWindowButton(.zoomButton)?.isEnabled = false
            }

            window.minSize = NSSize(
                width: fixedWidth,
                height: minContentHeight + toolbarInset
            )
            window.maxSize = NSSize(
                width: fixedWidth,
                height: maxContentHeight + toolbarInset
            )
        }
    }
}
