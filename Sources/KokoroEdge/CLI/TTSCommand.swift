import ArgumentParser
import Foundation

struct TTSCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tts",
        abstract: "Synthesize text to speech."
    )

    @Argument(help: "Text to synthesize. If omitted, stdin will be used.")
    var text: String?

    @Option(help: "Voice identifier.")
    var voice = "af_heart"

    @Option(help: "Speech speed multiplier.")
    var speed: Double = 1.0

    @Option(help: "Language variant.")
    var language: TTSEngineLanguage?

    @Option(help: "Write output to a file instead of stdout.")
    var output: String?

    mutating func run() throws {
        let inputText = try resolvedText()
        let modelManager = ModelManager()

        guard modelManager.isAvailable(model: "kokoro-82m") else {
            throw ValidationError("Model not found. Run 'kokoro-edge models pull kokoro-82m' first.")
        }

        let modelDirectory = try modelManager.modelPath(for: "kokoro-82m")
        let engine = TTSEngine()
        try engine.initialize(modelDir: modelDirectory)

        let startTime = Date()
        let synthesis = try SynthesisPipeline.synthesize(
            text: inputText,
            voice: voice,
            speed: Float(speed),
            language: language,
            engine: engine
        )
        let wavData = AudioEncoder.encodeWAV(samples: synthesis.samples, sampleRate: engine.sampleRate)
        try writeOutput(wavData)

        let elapsed = Date().timeIntervalSince(startTime)
        let audioLength = Double(synthesis.samples.count) / Double(engine.sampleRate)
        let realtimeFactor = elapsed > 0 ? audioLength / elapsed : 0
        try writeTiming(
            "Synthesized \(String(format: "%.1f", audioLength))s of audio in \(String(format: "%.2f", elapsed))s (\(String(format: "%.1f", realtimeFactor))x realtime)\n"
        )
    }

    private func resolvedText() throws -> String {
        if let text, !text.isEmpty {
            return text
        }

        let stdinData = FileHandle.standardInput.readDataToEndOfFile()
        guard let stdinText = String(data: stdinData, encoding: .utf8) else {
            throw ValidationError("Stdin did not contain valid UTF-8 text.")
        }

        let trimmed = stdinText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ValidationError("No input text provided.")
        }

        return trimmed
    }

    private func writeOutput(_ data: Data) throws {
        if let output {
            try data.write(to: URL(fileURLWithPath: output))
            return
        }

        try FileHandle.standardOutput.write(contentsOf: data)
    }

    private func writeTiming(_ string: String) throws {
        guard let data = string.data(using: .utf8) else {
            return
        }

        try FileHandle.standardError.write(contentsOf: data)
    }
}

extension TTSEngineLanguage: ExpressibleByArgument {}
