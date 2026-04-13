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
    private var selectedVisibleFrame: CGRect?

    private let hostingView: NSHostingView<RecordingPillViewWrapper>
    private let containerView: NSVisualEffectView

    init(levelMonitor: AudioLevelMonitor, activationStore: ActivationStore) {
        let initialSize = RecordingPillPanel.defaultSize

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
            let interactive = (state == .recording || state == .processing || state == .converting || state.isSuccess)
            if ignoresMouseEvents == interactive {
                ignoresMouseEvents = !interactive
            }

            if currentSize != targetSize {
                currentSize = targetSize
                containerView.layer?.cornerRadius = targetSize.height / 2
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
        case .recording, .processing, .modelDownloading, .converting:
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
        let origin = NSPoint(
            x: visibleFrame.midX - (currentSize.width / 2),
            y: visibleFrame.minY + 40
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
            silenceWarningActive: levelMonitor.silenceWarningActive,
            onFinish: { activationStore.finish() },
            onCancel: { activationStore.cancelCurrentSession() },
            onRestart: { activationStore.restartCurrentSession() },
            onSuccessClose: { activationStore.dismissCurrentSuccess() },
            onSuccessCopy: { activationStore.copyCurrentSuccessResult() }
        )
    }
}
