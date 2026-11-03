import SwiftUI
import AppKit

public enum ChilltraxTheme {
    /// Brand red accent color from `icon.svg` (`#E60E30`)
    public static let accentRed = Color(red: 0xE6 / 255.0, green: 0x0E / 255.0, blue: 0x30 / 255.0)
    public static let visualizerBlack = Color.black
    public static let visualizerWhite = Color.white

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
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                context.coordinator.configure(window: window)
                context.coordinator.syncSize(isExpanded: isHistoryExpanded, on: window)
            }
        }
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
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

    public final class Coordinator {
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
            guard lastAppliedExpanded != isExpanded else { return }
            lastAppliedExpanded = isExpanded

            let toolbarInset = max(0, window.frame.height - window.contentLayoutRect.height)
            let targetContentHeight = isExpanded ? ChilltraxTheme.expandedHeight : ChilltraxTheme.compactHeight
            let targetWindowHeight = targetContentHeight + toolbarInset
            let fixedWidth = ChilltraxTheme.compactWidth

            if isExpanded {
                window.styleMask.insert(.resizable)
                window.standardWindowButton(.zoomButton)?.isEnabled = true
            } else {
                window.styleMask.remove(.resizable)
                window.standardWindowButton(.zoomButton)?.isEnabled = false
            }

            // Relax vertical min/max constraints first so setFrame never fights active window limits
            let minContentHeight: CGFloat = isExpanded ? 320 : ChilltraxTheme.compactHeight
            let maxContentHeight: CGFloat = isExpanded ? 900 : ChilltraxTheme.compactHeight
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
            targetFrame.size.height = targetWindowHeight
            // Keep top edge of the window anchored in place on screen when expanding/collapsing
            targetFrame.origin.y = window.frame.maxY - targetWindowHeight

            window.setFrame(targetFrame, display: true, animate: false)

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
