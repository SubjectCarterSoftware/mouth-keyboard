import AppKit
import SwiftUI

@MainActor
final class RecordingPillPanel: NSPanel {
    private let panelSize = NSSize(width: 160, height: 44)
    private var screenObserver: NSObjectProtocol?

    init(levelMonitor: AudioLevelMonitor) {
        super.init(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.nonactivatingPanel, .hudWindow, .utilityWindow],
            backing: .buffered,
            defer: false
        )

        isReleasedWhenClosed = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        isMovableByWindowBackground = false
        hasShadow = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        hidesOnDeactivate = false
        ignoresMouseEvents = true

        let containerView = NSVisualEffectView(frame: NSRect(origin: .zero, size: panelSize))
        containerView.material = .hudWindow
        containerView.blendingMode = .withinWindow
        containerView.state = .active
        containerView.appearance = NSAppearance(named: .darkAqua)
        containerView.wantsLayer = true
        containerView.layer?.cornerRadius = panelSize.height / 2
        containerView.layer?.masksToBounds = true

        let hostingView = NSHostingView(rootView: RecordingPillView(levelMonitor: levelMonitor))
        hostingView.frame = containerView.bounds
        hostingView.autoresizingMask = [.width, .height]
        containerView.addSubview(hostingView)

        contentView = containerView

        updatePosition()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updatePosition()
        }
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }

    func updatePosition() {
        guard let screen = NSScreen.main else {
            return
        }

        let visibleFrame = screen.visibleFrame
        let origin = NSPoint(
            x: visibleFrame.midX - (panelSize.width / 2),
            y: visibleFrame.minY + 40
        )

        setFrame(NSRect(origin: origin, size: panelSize), display: false)
    }
}
