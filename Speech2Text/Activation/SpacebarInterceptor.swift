import CoreGraphics
import Foundation

// MARK: - Protocol

protocol SessionKeyHandling: AnyObject {
    var finishKeyActive: Bool { get set }
    var cancelKeyActive: Bool { get set }
    var onFinishKeyPressed: (() -> Void)? { get set }
    var onCancelKeyPressed: (() -> Void)? { get set }
    @discardableResult
    func start() -> Bool
    func stop()
}

typealias SpacebarHandling = SessionKeyHandling

enum SessionKey: Int64 {
    case finish = 49
    case cancel = 53
}

// MARK: - Implementation

class SessionKeyInterceptor: SessionKeyHandling {
    var finishKeyActive: Bool = false
    var cancelKeyActive: Bool = false
    var onFinishKeyPressed: (() -> Void)?
    var onCancelKeyPressed: (() -> Void)?
    private(set) var isRunning = false

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else { return true }

        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: spacebarEventCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let tap else {
            isRunning = false
            return false
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true
        return true
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
                runLoopSource = nil
            }
            eventTap = nil
        }
        finishKeyActive = false
        cancelKeyActive = false
        isRunning = false
    }

    @discardableResult
    func handle(keyCode: Int64) -> Bool {
        guard let key = SessionKey(rawValue: keyCode) else {
            return false
        }

        switch key {
        case .finish:
            guard finishKeyActive else { return false }
            DispatchQueue.main.async { [weak self] in
                self?.onFinishKeyPressed?()
            }
            return true
        case .cancel:
            guard cancelKeyActive else { return false }
            DispatchQueue.main.async { [weak self] in
                self?.onCancelKeyPressed?()
            }
            return true
        }
    }
}

final class SpacebarInterceptor: SessionKeyInterceptor {}

// MARK: - C Callback

private func spacebarEventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passRetained(event) }
    let interceptor = Unmanaged<SessionKeyInterceptor>.fromOpaque(userInfo).takeUnretainedValue()

    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    guard interceptor.handle(keyCode: keyCode) else {
        return Unmanaged.passRetained(event)
    }

    return nil
}
