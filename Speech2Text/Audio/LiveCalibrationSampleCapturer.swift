import Foundation

// MARK: - Live Production Capturer

/// Production conformer of CalibrationSampleCapturing.
/// Records a 3-second audio window via AudioCaptureService + AudioBufferAccumulator,
/// then transcribes via WhisperService and returns a CalibrationSample.
@MainActor
final class LiveCalibrationSampleCapturer: CalibrationSampleCapturing {
    private let capture: AudioCaptureService
    private let whisper: any WhisperTranscribing

    init(
        capture: AudioCaptureService = .shared,
        whisper: any WhisperTranscribing = WhisperService.shared
    ) {
        self.capture = capture
        self.whisper = whisper
    }

    func captureSample(for primaryName: String) async throws -> CalibrationSample? {
        let accumulator = AudioBufferAccumulator()
        let levelMonitor = AudioLevelMonitor()

        do {
            try capture.start(levelMonitor: levelMonitor, bufferReceiver: accumulator)
        } catch AudioCaptureError.microphonePermissionDenied {
            // No permission — signal the runner to exit cleanly.
            throw CalibrationCapturingDone.exhausted
        } catch {
            // Other start errors (no device, engine failure) — trigger a retry.
            return nil
        }

        // Record for ~3 seconds.
        try await Task.sleep(for: .seconds(3))

        capture.stop()

        let samples: [Float]
        do {
            samples = try accumulator.convertToWhisperFormat()
        } catch AudioBufferAccumulatorError.emptyBuffers {
            return nil
        } catch {
            return nil
        }

        let text: String
        do {
            text = try await whisper.transcribe(samples: samples)
        } catch TranscriptionError.noSpeechDetected {
            return nil
        } catch {
            return nil
        }

        return CalibrationSample(rawTranscript: text)
    }
}
