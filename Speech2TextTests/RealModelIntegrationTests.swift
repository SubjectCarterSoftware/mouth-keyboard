import XCTest
@testable import Speech2Text

final class RealModelIntegrationTests: XCTestCase {

    override func setUp() async throws {
        // Optional: clear defaults or setup
    }

    func testRealQwen2BModelGeneration() async throws {
        // This test actually downloads and runs the Real Qwen 3.5 2B model.
        // It mimics the exact transcript the user provided.
        
        let transcript = "1, 9, 12, 13, 14, 15. Zeus, can you please put those in ascending order for me?"
        let triggerName = "Zeus"
        
        // 1. Simulate the parser
        let aliases = TriggerAliasNormalizer.normalize([triggerName])
        let split = TriggerTranscriptParser.split(transcript: transcript, activeAliases: aliases)
        
        var body = ""
        var instructions = ""
        
        switch split {
        case .validTrigger(let content, let instruction, _):
            body = content.trimmingCharacters(in: .whitespacesAndNewlines)
            instructions = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        default:
            XCTFail("Parser failed to find valid trigger!")
            return
        }
        
        XCTAssertEqual(body, "1, 9, 12, 13, 14, 15")
        XCTAssertEqual(instructions, "can you please put those in ascending order for me?")
        
        // 2. Simulate the LLM rewrite using the 2B tier
        let service = LLMRewriteService.shared
        
        do {
            print("Starting model download & generation... This may take a minute.")
            
            // Call the rewrite overload that takes instructions
            let result = try await service.rewrite(
                body: body,
                instructions: instructions
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
