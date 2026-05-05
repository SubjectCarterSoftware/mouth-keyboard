import XCTest
@testable import TypeLessBuddy

final class RealModelIntegrationTests: XCTestCase {

    override func setUp() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["RUN_MODEL_INTEGRATION_TESTS"] == "1",
            "Skipping real MLX model tests. Set RUN_MODEL_INTEGRATION_TESTS=1 to enable."
        )
    }

    func testRealQwen2BModelGeneration() async throws {
        let transcript = "1, 9, 12, 13, 14, 15. Zeus, can you please put those in ascending order for me?"
        let detection = TriggerTranscriptParser.detect(transcript: transcript, triggerNames: ["Zeus"])

        guard case .triggered(let detectedTranscript, _) = detection else {
            XCTFail("Parser failed to find valid trigger!")
            return
        }

        XCTAssertEqual(detectedTranscript, transcript)

        let service = LLMRewriteService.shared

        do {
            print("Starting model download & generation... This may take a minute.")

            let result = try await service.generate(
                prompt: detectedTranscript,
                systemPrompt: LLMRewriteService.resolveAssistantSystemPrompt(
                    assistantName: triggerName
                )
            )

            print("Successfully generated result: \(result)")
            XCTAssertFalse(result.isEmpty)
        } catch {
            print("FATAL MODEL ERROR: \(error)")
            print("FATAL MODEL ERROR DESC: \(error.localizedDescription)")
            XCTFail("Model generation failed with error: \(error)")
        }
    }
}
