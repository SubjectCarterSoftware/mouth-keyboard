import Foundation
import MLXLMCommon
import MLXLLM
import MLX
import Hub
import MLX
import Hub

@main
struct TestRunner {
    static func main() async {
        print("Starting MLX LM natively...")
        
        let hub = HubApi()
        let repo = "mlx-community/Qwen3.5-2B-OptiQ-4bit"
        let modelDir: URL
        do {
            print("Downloading \(repo)...")
            modelDir = try await hub.snapshot(from: repo)
        } catch {
            print("Failed to download model: \(error)")
            return
        }
        
        print("Downloaded model to: \(modelDir.path)")
        
        var config = ModelConfiguration(directory: modelDir)
        config.eosTokenIds = [248044]
        config.extraEOSTokens = ["<|im_end|>"]
        
        do {
            print("Loading container...")
            let container = try await LLMModelFactory.shared.loadContainer(configuration: config)
            print("Container loaded!")
            
            let systemPrompt = "You are a helpful assistant. Rewrite the user's speech according to their instructions."
            let promptText = "Body: 1, 9, 12, 13, 14, 15.\n\nInstructions: can you please put those in ascending order for me?"
            
            print("Starting ChatSession...")
            var params = GenerateParameters(temperature: 0.6)
            let session = ChatSession(
                container,
                instructions: systemPrompt,
                generateParameters: params
            )
            
            print("Generating...")
            let stream = session.streamResponse(to: promptText, role: .user, images: [], videos: [])
            
            for try await text in stream {
                print("TEXT Chunk: \(text)")
            }
            print("Generation complete!")
            
        } catch {
            print("MLX EXCEPTION: \(error)")
            print("DESC: \(error.localizedDescription)")
            print("Mirror dumping error:")
            dump(error)
        }
    }
}
