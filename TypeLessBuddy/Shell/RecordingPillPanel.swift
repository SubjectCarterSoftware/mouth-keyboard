import AppKit
import Combine
import SwiftUI

@MainActor
final class RecordingPillPanel: NSPanel {
    private static let recordingSize = NSSize(width: 220, height: 44)
    private static let defaultSize = NSSize(width: 220, height: 44)
    private static let recoverySize = NSSize(width: 180, height: 44)
    private static let failureSize = NSSize(width: 220, height: 44)

    private var currentSize: NSSize = RecordingPillPanel.defaultSize
    private var screenObserver: NSObjectProtocol?
    private var stateObserver: AnyCancellable?
    private var positionObserver: AnyCancellable?
    private var selectedVisibleFrame: CGRect?

    private let hostingView: NSHostingView<RecordingPillViewWrapper>
    private let containerView: NSVisualEffectView
    private let preferences: ShellPreferences

    init(levelMonitor: AudioLevelMonitor, activationStore: ActivationStore, preferences: ShellPreferences) {
        let initialSize = RecordingPillPanel.defaultSize
        self.preferences = preferences

        let wrapper = RecordingPillViewWrapper(
            levelMonitor: levelMonitor,
            activationStore: activationStore
        )
        hostingView = NSHostingView(rootView: wrapper)
        hostingView.frame = NSRect(origin: .zero, size: initialSize)
        hostingView.autoresizingMask = [.width, .height]

        containerView = NSVisualEffectView(frame: NSRect(origin: .zero, size: initialSize))
        containerView.material = .hudWindow
        containerView.blendingMode = .withinWindow
        containerView.state = .active
        containerView.appearance = NSAppearance(named: .darkAqua)
        containerView.wantsLayer = true
        containerView.layer?.cornerRadius = initialSize.height / 2
        containerView.layer?.masksToBounds = true
        containerView.layer?.borderWidth = 0
        containerView.addSubview(hostingView)

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
        hasShadow = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        contentView = containerView

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

        // Observe both lifecycle and recovery feedback so confirmation can stay
        // visible after the store has already returned to idle.
        stateObserver = Publishers.CombineLatest(
            activationStore.$state,
            activationStore.$recoveryFeedback
        )
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state, feedback in
                self?.updatePresentation(state: state, feedback: feedback)
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

    func updatePresentation(state: RecordingState, feedback: RecordingState.RecoveryFeedback?) {
        let targetSize = panelSize(for: state, feedback: feedback)
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

            if currentSize != targetSize {
                currentSize = targetSize
                containerView.layer?.cornerRadius = targetSize.height / 2
                containerView.layer?.borderWidth = 0
                updatePosition()
            }
            orderFrontRegardless()
        } else {
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
        let origin = RecordingPillPanelPositioning.origin(
            for: preferences.recordingPillPosition,
            in: visibleFrame,
            panelSize: currentSize
        )
        setFrame(NSRect(origin: origin, size: currentSize), display: true)
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
        RecordingPillView(
            levelMonitor: levelMonitor,
            recordingState: activationStore.state,
            recoveryFeedback: activationStore.recoveryFeedback,
            successDismissStartedAt: activationStore.successDismissStartedAt,
            successDismissDeadline: activationStore.successDismissDeadline,
            successNoteSaveState: activationStore.successNoteSaveState,
            silenceWarningActive: levelMonitor.silenceWarningActive,
            onFinish: { activationStore.finish() },
            onCancel: { activationStore.cancelCurrentSession() },
            onRestart: { activationStore.restartCurrentSession() },
            onSuccessClose: { activationStore.dismissCurrentSuccess() },
            onSuccessCopy: { activationStore.copyCurrentSuccessResult() },
            onSuccessAppend: { activationStore.appendFromSuccess() },
            onSuccessSaveNote: { activationStore.saveCurrentSuccessResultAsNote() }
        )
    }
}
