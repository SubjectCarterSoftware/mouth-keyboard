import Foundation
import WhisperKit

// MARK: - Error Types

enum TranscriptionError: LocalizedError {
    case modelLoadFailed
    case noModel
    case inferenceFailed
    case noSpeechDetected

    var errorDescription: String? {
        switch self {
        case .modelLoadFailed:
            return "Failed to load Whisper model."
        case .noModel:
            return "Whisper model is not ready. It may still be downloading."
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

    private var pipe: WhisperKit?
    private var currentModel: String?
    private var isLoading = false

    func prepare(model: String = WhisperModelChoice.baseEN.rawValue) async throws {
        guard model != currentModel || pipe == nil else { return }
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            pipe = try await WhisperKit(model: model)
            currentModel = model
        } catch {
            throw TranscriptionError.modelLoadFailed
        }
    }

    func transcribe(samples: [Float]) async throws -> String {
        guard let pipe else {
            throw TranscriptionError.noModel
        }

        let options = DecodingOptions(language: "en")
        do {
            let results = try await pipe.transcribe(audioArray: samples, decodeOptions: options)
            let text = results.map { $0.text }.joined()
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

            guard !text.isEmpty else {
                throw TranscriptionError.noSpeechDetected
            }

            return text
        } catch let error as TranscriptionError {
            throw error
        } catch {
            throw TranscriptionError.inferenceFailed
        }
    }
}
