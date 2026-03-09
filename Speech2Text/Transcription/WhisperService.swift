import Foundation
import whisper

// MARK: - Error Types

enum TranscriptionError: LocalizedError {
    case modelLoadFailed
    case noModel
    case inferenceFailed
    case noSpeechDetected

    var errorDescription: String? {
        switch self {
        case .modelLoadFailed:
            return "Failed to load Whisper model from the specified path."
        case .noModel:
            return "No Whisper model has been loaded. Call loadModel(at:) first."
        case .inferenceFailed:
            return "Whisper inference failed during transcription."
        case .noSpeechDetected:
            return "No speech was detected in the audio samples."
        }
    }
}

// MARK: - Protocol

protocol WhisperTranscribing: Sendable {
    func transcribe(samples: [Float]) async throws -> String
}

// MARK: - Actor

actor WhisperService: WhisperTranscribing {
    static let shared = WhisperService()

    private var context: OpaquePointer?

    deinit {
        if let ctx = context {
            whisper_free(ctx)
        }
    }

    func loadModel(at path: String) throws {
        var params = whisper_context_default_params()
        params.flash_attn = true
        guard let ctx = whisper_init_from_file_with_params(path, params) else {
            throw TranscriptionError.modelLoadFailed
        }
        if let existing = context {
            whisper_free(existing)
        }
        context = ctx
    }

    func ensureModelLoaded(at path: String) throws {
        guard context == nil else { return }
        try loadModel(at: path)
    }

    func transcribe(samples: [Float]) async throws -> String {
        guard let ctx = context else {
            throw TranscriptionError.noModel
        }

        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        let threadCount = max(1, min(8, ProcessInfo.processInfo.processorCount - 2))
        params.n_threads = Int32(threadCount)
        params.language = ("en" as NSString).utf8String
        params.no_context = true
        params.print_progress = false
        params.print_realtime = false
        params.print_special = false
        params.print_timestamps = false
        params.no_timestamps = true

        let result = samples.withUnsafeBufferPointer { ptr in
            whisper_full(ctx, params, ptr.baseAddress, Int32(samples.count))
        }

        guard result == 0 else {
            throw TranscriptionError.inferenceFailed
        }

        let segmentCount = whisper_full_n_segments(ctx)
        var text = ""
        for i in 0..<segmentCount {
            if let segment = whisper_full_get_segment_text(ctx, i) {
                text += String(cString: segment)
            }
        }

        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            throw TranscriptionError.noSpeechDetected
        }

        return trimmed
    }
}
