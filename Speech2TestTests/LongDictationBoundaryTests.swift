import XCTest
@testable import Speech2Test

final class LongDictationBoundaryTests: XCTestCase {
    func testLongDictationThresholdThenPauseSealsSegment() {
        var tracker = LongDictationBoundaryTracker(
            configuration: LongDictationBoundaryConfiguration(
                activationThreshold: 3,
                pauseThreshold: 1,
                softCapDuration: 5
            )
        )

        var events: [LongDictationBoundaryEvent] = []
        events += tracker.ingest(normalizedLevel: 0.8, frameDuration: 1, silenceThreshold: 0.01)
        events += tracker.ingest(normalizedLevel: 0.8, frameDuration: 1, silenceThreshold: 0.01)
        events += tracker.ingest(normalizedLevel: 0.8, frameDuration: 1, silenceThreshold: 0.01)
        events += tracker.ingest(normalizedLevel: 0.0, frameDuration: 1, silenceThreshold: 0.01)

        XCTAssertEqual(
            events,
            [.thresholdReached, .segmentBoundary(reason: .pause)]
        )
    }

    func testLongDictationThresholdThenSoftCapSealsSegmentWithoutPause() {
        var tracker = LongDictationBoundaryTracker(
            configuration: LongDictationBoundaryConfiguration(
                activationThreshold: 3,
                pauseThreshold: 1,
                softCapDuration: 4
            )
        )

        var events: [LongDictationBoundaryEvent] = []
        events += tracker.ingest(normalizedLevel: 0.8, frameDuration: 1, silenceThreshold: 0.01)
        events += tracker.ingest(normalizedLevel: 0.8, frameDuration: 1, silenceThreshold: 0.01)
        events += tracker.ingest(normalizedLevel: 0.8, frameDuration: 1, silenceThreshold: 0.01)
        events += tracker.ingest(normalizedLevel: 0.8, frameDuration: 1, silenceThreshold: 0.01)

        XCTAssertEqual(
            events,
            [.thresholdReached, .segmentBoundary(reason: .softCap)]
        )
    }

    func testNoBoundaryIsEmittedBeforeLongDictationThreshold() {
        var tracker = LongDictationBoundaryTracker(
            configuration: LongDictationBoundaryConfiguration(
                activationThreshold: 5,
                pauseThreshold: 1,
                softCapDuration: 6
            )
        )

        var events: [LongDictationBoundaryEvent] = []
        events += tracker.ingest(normalizedLevel: 0.8, frameDuration: 1, silenceThreshold: 0.01)
        events += tracker.ingest(normalizedLevel: 0.8, frameDuration: 1, silenceThreshold: 0.01)
        events += tracker.ingest(normalizedLevel: 0.0, frameDuration: 1, silenceThreshold: 0.01)

        XCTAssertTrue(events.isEmpty)
    }
}
