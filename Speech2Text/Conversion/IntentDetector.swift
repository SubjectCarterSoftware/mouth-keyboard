import Foundation

enum IntentDetector {
    static func detect(transcript: String, modes: [ConvertMode]) -> ConvertIntent {
        // TODO: implement in Plan 02
        return ConvertIntent(mode: .passthrough, strippedBody: transcript, originalTranscript: transcript)
    }
}
