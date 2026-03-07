import CoreGraphics
import Foundation

// MARK: - Protocol

protocol SpacebarHandling: AnyObject {
    var isActive: Bool { get set }
    var onSpacebarPressed: (() -> Void)? { get set }
    func start()
    func stop()
}

// MARK: - Implementation

final class SpacebarInterceptor: SpacebarHandling {
    var isActive: Bool = false
    var onSpacebarPressed: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    func start() {
        guard eventTap == nil else { return }

        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: spacebarEventCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let tap else { return }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
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
        isActive = false
    }
}

// MARK: - C Callback

private func spacebarEventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passRetained(event) }
    let interceptor = Unmanaged<SpacebarInterceptor>.fromOpaque(userInfo).takeUnretainedValue()

    guard interceptor.isActive else {
        return Unmanaged.passRetained(event)
    }

    // kVK_Space = 49
    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    guard keyCode == 49 else {
        return Unmanaged.passRetained(event)
    }

    // Consume the event and notify on main queue
    DispatchQueue.main.async {
        interceptor.onSpacebarPressed?()
    }
    return nil
}
