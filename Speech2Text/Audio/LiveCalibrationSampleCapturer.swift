import Foundation

@MainActor
final class LiveCalibrationSampleCapturer {
    private let capture: AudioCaptureService
    private let whisper: any WhisperTranscribing

    init(
        capture: AudioCaptureService = .shared,
        whisper: any WhisperTranscribing = WhisperService.shared
    ) {
        self.capture = capture
        self.whisper = whisper
    }

    func captureTranscript() async throws -> String? {
        let accumulator = AudioBufferAccumulator()
        let levelMonitor = AudioLevelMonitor()

        do {
            try capture.start(levelMonitor: levelMonitor, bufferReceiver: accumulator)
        } catch AudioCaptureError.captureBusy {
            throw AudioCaptureError.captureBusy
        } catch {
            return nil
        }

        var manuallyStopped = false
        do {
            try await Task.sleep(for: .seconds(3))
        } catch is CancellationError {
            manuallyStopped = true
        }

        capture.stop()

        let samples: [Float]
        do {
            samples = try accumulator.convertToWhisperFormat()
        } catch AudioBufferAccumulatorError.emptyBuffers {
            return nil
        } catch {
            return nil
        }

        if manuallyStopped {
            let whisperRef = whisper
            return await Task.detached {
                try? await whisperRef.transcribe(samples: samples)
            }.value
        }

        do {
            return try await whisper.transcribe(samples: samples)
        } catch TranscriptionError.noSpeechDetected {
            return nil
        } catch {
            return nil
        }
    }
}
