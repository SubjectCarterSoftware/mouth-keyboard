import Foundation

@main
struct TestRunner {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        let command = args.first ?? "assistant-benchmark"

        switch command {
        case "assistant-benchmark":
            await AssistantBenchmarkCommand().run(arguments: Array(args.dropFirst()))
        default:
            fputs("Unknown command: \(command)\n", stderr)
            fputs("Available commands: assistant-benchmark\n", stderr)
            Foundation.exit(1)
        }
    }
}
