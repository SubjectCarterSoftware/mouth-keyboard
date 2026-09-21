import AppKit
import Combine
import SwiftUI

@MainActor
final class RecordingPillPanel: NSPanel {
    private static let recordingSize = NSSize(width: 220, height: 44)
    private static let defaultSize = NSSize(width: 220, height: 44)
    private static let recoverySize = NSSize(width: 180, height: 44)
    private static let failureSize = NSSize(width: 220, height: 44)

    /// Extra transparent height reserved above the capsule so the screenshot
    /// badge tab isn't clipped. Only added to the window's frame while the
    /// badge is actually visible, so normal recordings never grow a click-
    /// swallowing strip above the pill.
    private static let screenshotBadgeTopMargin: CGFloat = 12

    /// How long the badge's exit transition takes (`RecordingPillView`'s
    /// removal transition). The window keeps reserving the badge's top
    /// margin for this long after the badge stops being visible, so the
    /// shrink doesn't clip the badge mid-animation.
    private static let screenshotBadgeExitDuration: TimeInterval = 0.22

    /// The capsule's own size (used for corner radius and for computing the
    /// on-screen origin). Distinct from `currentTotalSize`, which may be
    /// taller to make room for the screenshot badge.
    private var currentCapsuleSize: NSSize = RecordingPillPanel.defaultSize
    private var currentTotalSize: NSSize = RecordingPillPanel.defaultSize
    private var badgeWasVisible = false
    private var pendingBadgeShrinkTask: Task<Void, Never>?
    private var screenObserver: NSObjectProtocol?
    private var stateObserver: AnyCancellable?
    private var positionObserver: AnyCancellable?
    private var selectedVisibleFrame: CGRect?

    private let hostingView: NSHostingView<RecordingPillViewWrapper>
    private let containerView: NSVisualEffectView
    private let rootView: NSView
    private let preferences: ShellPreferences

    init(levelMonitor: AudioLevelMonitor, activationStore: ActivationStore, preferences: ShellPreferences) {
        let initialCapsuleSize = RecordingPillPanel.defaultSize
        self.preferences = preferences

        let wrapper = RecordingPillViewWrapper(
            levelMonitor: levelMonitor,
            activationStore: activationStore
        )
        hostingView = NSHostingView(rootView: wrapper)
        hostingView.frame = NSRect(origin: .zero, size: initialCapsuleSize)
        hostingView.autoresizingMask = [.width, .height]
        // NSHostingView is opaque by default on macOS; without this the
        // transparent strip above the capsule (reserved for the badge) would
        // paint as an opaque rectangle instead of letting the desktop show
        // through.
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor

        containerView = NSVisualEffectView(frame: NSRect(origin: .zero, size: initialCapsuleSize))
        containerView.material = .hudWindow
        containerView.blendingMode = .withinWindow
        containerView.state = .active
        containerView.appearance = NSAppearance(named: .darkAqua)
        containerView.wantsLayer = true
        containerView.layer?.cornerRadius = initialCapsuleSize.height / 2
        containerView.layer?.masksToBounds = true
        containerView.layer?.borderWidth = 0
        // Pinned to the bottom edge, full width, fixed (capsule) height: the
        // top margin absorbs any extra window height added for the badge.
        containerView.autoresizingMask = [.width, .maxYMargin]

        rootView = NSView(frame: NSRect(origin: .zero, size: initialCapsuleSize))
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = NSColor.clear.cgColor
        rootView.autoresizesSubviews = true
        rootView.addSubview(containerView)
        rootView.addSubview(hostingView)

        super.init(
            contentRect: NSRect(origin: .zero, size: initialCapsuleSize),
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
        // Non-activating panels don't accept mouse-moved events by default,
        // which SwiftUI's `.onHover` (used by the screenshot badge) relies on
        // to track entered/exited state while the cursor moves within it.
        acceptsMouseMovedEvents = true
        contentView = rootView

        updatePosition()

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.selectedVisibleFrame = nil
                self?.updatePosition()
            }
        }

        // Observe lifecycle, recovery feedback, and the screenshot count so
        // confirmation can stay visible after the store has returned to
        // idle, and so the badge's extra height is added/removed promptly.
        stateObserver = Publishers.CombineLatest3(
            activationStore.$state,
            activationStore.$recoveryFeedback,
            activationStore.$sessionScreenshotCount
        )
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state, feedback, screenshotCount in
                self?.updatePresentation(state: state, feedback: feedback, screenshotCount: screenshotCount)
            }

        positionObserver = preferences.$recordingPillPosition
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updatePosition()
            }
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // MARK: - State-driven updates

    func updatePresentation(
        state: RecordingState,
        feedback: RecordingState.RecoveryFeedback?,
        screenshotCount: Int
    ) {
        let targetCapsuleSize = panelSize(for: state, feedback: feedback)
        let badgeVisible = RecordingPillView.screenshotBadgeVisible(
            state: state,
            feedback: feedback,
            screenshotCount: screenshotCount
        )

        if badgeVisible {
            pendingBadgeShrinkTask?.cancel()
            pendingBadgeShrinkTask = nil
        } else if badgeWasVisible && pendingBadgeShrinkTask == nil {
            // The badge just stopped being visible (e.g. the state left
            // processing for success). Let its exit transition finish before
            // shrinking the window back down, so it isn't clipped mid-animation.
            pendingBadgeShrinkTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(Self.screenshotBadgeExitDuration * 1_000_000_000))
                guard let self, !Task.isCancelled else { return }
                self.pendingBadgeShrinkTask = nil
                let shrunkSize = self.currentCapsuleSize
                if self.currentTotalSize != shrunkSize {
                    self.currentTotalSize = shrunkSize
                    self.updatePosition()
                }
            }
        }
        badgeWasVisible = badgeVisible

        // Keep reserving the badge's top margin while it's visible, and for
        // as long as a shrink is still pending (i.e. its exit animation is
        // still playing).
        let reservesBadgeMargin = badgeVisible || pendingBadgeShrinkTask != nil
        let targetTotalSize = reservesBadgeMargin
            ? NSSize(width: targetCapsuleSize.width, height: targetCapsuleSize.height + Self.screenshotBadgeTopMargin)
            : targetCapsuleSize
        let shouldShow = feedback != nil || state != .idle

        if shouldShow {
            if selectedVisibleFrame == nil {
                selectedVisibleFrame = chooseVisibleFrame()
            }
            // Enable mouse events during interactive states so the finish/cancel buttons work.
            let interactive = (state == .recording || state == .processing || state == .rewriting || state.isSuccess)
            if ignoresMouseEvents == interactive {
                ignoresMouseEvents = !interactive
            }

            if currentCapsuleSize != targetCapsuleSize || currentTotalSize != targetTotalSize {
                currentCapsuleSize = targetCapsuleSize
                currentTotalSize = targetTotalSize
                containerView.layer?.cornerRadius = targetCapsuleSize.height / 2
                containerView.layer?.borderWidth = 0
                updatePosition()
            }
            orderFrontRegardless()
        } else {
            pendingBadgeShrinkTask?.cancel()
            pendingBadgeShrinkTask = nil
            ignoresMouseEvents = true
            orderOut(nil)
            selectedVisibleFrame = nil
        }
    }

    private func panelSize(for state: RecordingState, feedback: RecordingState.RecoveryFeedback?) -> NSSize {
        if feedback != nil {
            return RecordingPillPanel.recoverySize
        }

        switch state {
        case .recording, .processing, .modelDownloading, .rewriting:
            return RecordingPillPanel.recordingSize
        case .success:
            return RecordingPillPanel.defaultSize
        case .failure:
            return RecordingPillPanel.failureSize
        default:
            return RecordingPillPanel.defaultSize
        }
    }

    // MARK: - Positioning

    func updatePosition() {
        guard let visibleFrame = selectedVisibleFrame ?? chooseVisibleFrame() else {
            return
        }
        selectedVisibleFrame = visibleFrame
        let frame = RecordingPillPanelPositioning.frame(
            for: preferences.recordingPillPosition,
            in: visibleFrame,
            capsuleSize: currentCapsuleSize,
            topMargin: currentTotalSize.height - currentCapsuleSize.height
        )
        setFrame(frame, display: true)
        // With transparent regions, `hasShadow` follows the drawn content
        // rather than the full frame rect. Without an explicit invalidation
        // AppKit can keep showing the shadow computed for the previous
        // (differently-sized) frame, which reads as a rectangular shadow
        // around the capsule.
        invalidateShadow()
    }

    private func chooseVisibleFrame() -> CGRect? {
        let mouseLocation = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.visibleFrame.contains(mouseLocation) }) {
            return screen.visibleFrame
        }
        return NSScreen.main?.visibleFrame
    }
}

enum RecordingPillPanelPositioning {
    private static let horizontalInset: CGFloat = 24
    private static let topInset: CGFloat = 28
    private static let bottomInset: CGFloat = 40

    static func origin(
        for position: RecordingPillPosition,
        in visibleFrame: CGRect,
        panelSize: NSSize
    ) -> CGPoint {
        let centeredX = visibleFrame.midX - (panelSize.width / 2)
        let leftX = visibleFrame.minX + horizontalInset
        let rightX = visibleFrame.maxX - horizontalInset - panelSize.width

        let centeredY = visibleFrame.midY - (panelSize.height / 2)
        let topY = visibleFrame.maxY - topInset - panelSize.height
        let bottomY = visibleFrame.minY + bottomInset

        let x: CGFloat
        switch position {
        case .topLeft, .centerLeft, .bottomLeft:
            x = leftX
        case .topCenter, .bottomCenter:
            x = centeredX
        case .topRight, .centerRight, .bottomRight:
            x = rightX
        }

        let y: CGFloat
        switch position {
        case .topLeft, .topCenter, .topRight:
            y = topY
        case .centerLeft, .centerRight:
            y = centeredY
        case .bottomLeft, .bottomCenter, .bottomRight:
            y = bottomY
        }

        let minX = visibleFrame.minX
        let maxX = visibleFrame.maxX - panelSize.width
        let minY = visibleFrame.minY
        let maxY = visibleFrame.maxY - panelSize.height

        return CGPoint(
            x: min(max(x, minX), maxX),
            y: min(max(y, minY), maxY)
        )
    }

    /// The panel's on-screen frame when it may need extra height above the
    /// capsule (e.g. for the screenshot badge). The origin is always derived
    /// from the capsule's own size — never the grown size — so the capsule's
    /// bottom-left corner never moves: growth is purely additional height
    /// stacked upward from that fixed point. For the top-anchored positions
    /// this eats into `topInset` rather than pushing the capsule down.
    static func frame(
        for position: RecordingPillPosition,
        in visibleFrame: CGRect,
        capsuleSize: NSSize,
        topMargin: CGFloat
    ) -> CGRect {
        let capsuleOrigin = origin(for: position, in: visibleFrame, panelSize: capsuleSize)
        let totalSize = NSSize(width: capsuleSize.width, height: capsuleSize.height + topMargin)
        return CGRect(origin: capsuleOrigin, size: totalSize)
    }
}

@MainActor
final class RecordingPillPreviewPanel: NSPanel {
    private static let previewSize = NSSize(width: 220, height: 44)

    private var screenObserver: NSObjectProtocol?
    private var stateObserver: AnyCancellable?
    private var requestedPosition: RecordingPillPosition?

    private let activationStore: ActivationStore
    private let containerView: NSVisualEffectView

    init(activationStore: ActivationStore) {
        self.activationStore = activationStore
        let initialSize = Self.previewSize

        containerView = NSVisualEffectView(frame: NSRect(origin: .zero, size: initialSize))
        containerView.material = .hudWindow
        containerView.blendingMode = .withinWindow
        containerView.state = .active
        containerView.appearance = NSAppearance(named: .darkAqua)
        containerView.wantsLayer = true
        containerView.layer?.cornerRadius = initialSize.height / 2
        containerView.layer?.masksToBounds = true
        containerView.layer?.borderWidth = 1
        containerView.layer?.borderColor = NSColor.systemBlue.withAlphaComponent(0.45).cgColor
        containerView.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.14).cgColor

        super.init(
            contentRect: NSRect(origin: .zero, size: initialSize),
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
        hasShadow = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        contentView = containerView

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshPresentation()
            }
        }

        stateObserver = activationStore.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshPresentation()
            }
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func updatePreview(position: RecordingPillPosition?) {
        requestedPosition = position
        refreshPresentation()
    }

    private func refreshPresentation() {
        guard let requestedPosition, activationStore.state == .idle else {
            orderOut(nil)
            return
        }

        guard let visibleFrame = chooseVisibleFrame() else {
            orderOut(nil)
            return
        }

        let origin = RecordingPillPanelPositioning.origin(
            for: requestedPosition,
            in: visibleFrame,
            panelSize: Self.previewSize
        )
        setFrame(NSRect(origin: origin, size: Self.previewSize), display: true)
        orderFrontRegardless()
    }

    private func chooseVisibleFrame() -> CGRect? {
        let mouseLocation = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.visibleFrame.contains(mouseLocation) }) {
            return screen.visibleFrame
        }
        return NSScreen.main?.visibleFrame
    }
}

// MARK: - Wrapper view for reactive state observation

private struct RecordingPillViewWrapper: View {
    @ObservedObject var levelMonitor: AudioLevelMonitor
    @ObservedObject var activationStore: ActivationStore

    var body: some View {
        // The hosting view fills the whole (possibly taller) content view,
        // with the pill itself bottom-aligned so the capsule stays put and
        // any extra height reserved for the screenshot badge sits above it.
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            RecordingPillView(
                levelMonitor: levelMonitor,
                recordingState: activationStore.state,
                recoveryFeedback: activationStore.recoveryFeedback,
                successDismissStartedAt: activationStore.successDismissStartedAt,
                successDismissDeadline: activationStore.successDismissDeadline,
                successNoteSaveState: activationStore.successNoteSaveState,
                silenceWarningActive: levelMonitor.silenceWarningActive,
                screenshotCount: activationStore.sessionScreenshotCount,
                screenshotsFull: activationStore.sessionScreenshotsFull,
                screenshotDuplicateTick: activationStore.screenshotDuplicateTick,
                screenshotsIncludeFiles: activationStore.sessionAttachmentsIncludeFiles,
                screenshotsIncludeImages: activationStore.sessionAttachmentsIncludeImages,
                onFinish: { activationStore.finish() },
                onCancel: { activationStore.cancelCurrentSession() },
                onNoteAction: { activationStore.requestCurrentSessionResultAsNote() },
                onSuccessClose: { activationStore.dismissCurrentSuccess() },
                onSuccessCopy: { activationStore.copyCurrentSuccessResult() },
                onSuccessAppend: { activationStore.appendFromSuccess() },
                onScreenshotRemoveLast: { activationStore.removeLastCollectedAttachment() },
                onScreenshotClearAll: { activationStore.clearCollectedAttachments() }
            )
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
    }
}
