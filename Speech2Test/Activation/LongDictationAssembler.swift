import Foundation

struct AssembledTranscript: Equatable, Sendable {
    let text: String
    let successfulSegmentCount: Int
    let failedSegmentCount: Int
}

enum LongDictationAssembler {
    static func assemble(_ segments: [QueuedSegment]) -> AssembledTranscript? {
        let orderedSegments = segments.sorted { $0.index < $1.index }

        var successfulSegments: [String] = []
        var failedSegmentCount = 0

        for segment in orderedSegments {
            switch segment.transcriptionState {
            case .completed(let text):
                let normalizedText = normalizeWhitespace(in: text)
                if normalizedText.isEmpty {
                    failedSegmentCount += 1
                } else {
                    successfulSegments.append(normalizedText)
                }
            case .failed, .pending, .transcribing:
                failedSegmentCount += 1
            }
        }

        guard !successfulSegments.isEmpty else {
            return nil
        }

        let combinedText = normalizeWhitespace(in: successfulSegments.joined(separator: " "))
        guard !combinedText.isEmpty else {
            return nil
        }

        return AssembledTranscript(
            text: combinedText,
            successfulSegmentCount: successfulSegments.count,
            failedSegmentCount: failedSegmentCount
        )
    }

    private static func normalizeWhitespace(in text: String) -> String {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
