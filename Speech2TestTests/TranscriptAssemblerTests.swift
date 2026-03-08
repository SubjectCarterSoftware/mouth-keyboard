import XCTest
@testable import Speech2Test

final class TranscriptAssemblerTests: XCTestCase {
    func testAssembleSortsOutOfOrderCompletionsIntoSpokenOrder() {
        let transcript = LongDictationAssembler.assemble([
            makeSegment(index: 2, state: .completed(text: "third")),
            makeSegment(index: 0, state: .completed(text: "first")),
            makeSegment(index: 1, state: .completed(text: "second"))
        ])

        XCTAssertEqual(
            transcript,
            AssembledTranscript(text: "first second third", successfulSegmentCount: 3, failedSegmentCount: 0)
        )
    }

    func testAssembleNormalizesWhitespaceIntoSeamlessProse() {
        let transcript = LongDictationAssembler.assemble([
            makeSegment(index: 0, state: .completed(text: "  hello\n")),
            makeSegment(index: 1, state: .completed(text: "\tworld   "))
        ])

        XCTAssertEqual(
            transcript,
            AssembledTranscript(text: "hello world", successfulSegmentCount: 2, failedSegmentCount: 0)
        )
    }

    func testAssembleCountsPartialFailuresWithoutBlockingSuccessfulOutput() {
        let transcript = LongDictationAssembler.assemble([
            makeSegment(index: 0, state: .completed(text: "alpha")),
            makeSegment(index: 1, state: .failed(message: "segment failed")),
            makeSegment(index: 2, state: .completed(text: " gamma "))
        ])

        XCTAssertEqual(
            transcript,
            AssembledTranscript(text: "alpha gamma", successfulSegmentCount: 2, failedSegmentCount: 1)
        )
    }

    func testAssembleReturnsNilWhenEverySegmentFailsOrIsWhitespaceOnly() {
        let transcript = LongDictationAssembler.assemble([
            makeSegment(index: 0, state: .failed(message: "model error")),
            makeSegment(index: 1, state: .completed(text: "   \n")),
            makeSegment(index: 2, state: .pending)
        ])

        XCTAssertNil(transcript)
    }

    private func makeSegment(index: Int, state: QueuedSegmentTranscriptionState) -> QueuedSegment {
        QueuedSegment(
            index: index,
            sealReason: .pause,
            audio: SealedAudioSegment(
                samples: [Float(index)],
                sourceFrameCount: 1,
                sourceSampleRate: SealedAudioSegment.whisperSampleRate
            ),
            transcriptionState: state
        )
    }
}
