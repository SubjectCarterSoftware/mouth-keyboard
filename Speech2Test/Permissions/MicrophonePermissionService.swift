import AVFoundation
import Foundation

struct MicrophonePermissionService {
    typealias StatusProvider = () -> PermissionGrantState
    typealias RequestHandler = () async -> PermissionGrantState

    static let live = makeLive()

    private let statusProvider: StatusProvider
    private let requestHandler: RequestHandler

    init(
        statusProvider: @escaping StatusProvider,
        requestHandler: @escaping RequestHandler
    ) {
        self.statusProvider = statusProvider
        self.requestHandler = requestHandler
    }

    func currentStatus() -> PermissionGrantState {
        statusProvider()
    }

    func requestAccess() async -> PermissionGrantState {
        await requestHandler()
    }
}

private extension MicrophonePermissionService {
    static func makeLive() -> Self {
        if let mockedStatus = LaunchArgumentOverrides.permissionStatus(for: "-mock-microphone-status") {
            return Self(
                statusProvider: { mockedStatus },
                requestHandler: { mockedStatus }
            )
        }

        return Self(
            statusProvider: readLiveStatus,
            requestHandler: requestLiveAccess
        )
    }

    static func readLiveStatus() -> PermissionGrantState {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .authorized
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .denied
        }
    }

    static func requestLiveAccess() async -> PermissionGrantState {
        let currentStatus = readLiveStatus()
        guard currentStatus == .notDetermined else {
            return currentStatus
        }

        let granted = await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }

        return granted ? .authorized : .denied
    }
}
