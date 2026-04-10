import XCTest
@testable import Speech2Text

final class RealModelIntegrationTests: XCTestCase {

    override func setUp() async throws {
        // Optional: clear defaults or setup
    }

    func testRealQwen2BModelGeneration() async throws {
        let transcript = "1, 9, 12, 13, 14, 15. Zeus, can you please put those in ascending order for me?"
        let triggerName = "Zeus"

        let aliases = TriggerAliasNormalizer.normalize([triggerName])
        let detection = TriggerTranscriptParser.detect(transcript: transcript, activeAliases: aliases)

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
