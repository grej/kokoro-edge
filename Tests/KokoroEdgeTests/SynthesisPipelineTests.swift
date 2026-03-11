import XCTest
@testable import KokoroEdge

private let pipelineFailingPassagePart1 =
    "At the end of January, the US department of justice released its biggest drop yet of documents related to Jeffrey Epstein, the convicted paedophile and erstwhile friend of Trump who died in prison."

private let pipelineFailingPassagePart2 =
    "Lurid headlines based on the documents followed, about foreign women allegedly buried on Epstein's New Mexico ranch, about Epstein's purchase of 330 gallons of sulphuric acid, and a woman who claimed Trump raped her when she was aged 13. The Wall Street Journal reported the government took 47,635 files offline \"for further review\"."

private let pipelineFailingCombinedPassage = "\(pipelineFailingPassagePart1) \(pipelineFailingPassagePart2)"

private struct StubGenerationFailure: Error {}

private final class StubSynthesizer: SpeechSynthesizing {
    private let failureTexts: Set<String>
    private(set) var inputs: [String] = []

    init(failureTexts: Set<String>) {
        self.failureTexts = failureTexts
    }

    func synthesize(text: String, voice: String, speed: Float, language: TTSEngineLanguage?) throws -> [Float] {
        inputs.append(text)
        if failureTexts.contains(text) {
            throw StubGenerationFailure()
        }
        return Array(repeating: 0.1, count: 32)
    }
}

final class SynthesisPipelineTests: XCTestCase {
    func testSynthesisPipelineRefinesRecoverableCombinedPassageFailure() throws {
        let engine = StubSynthesizer(failureTexts: [pipelineFailingCombinedPassage])

        let result = try SynthesisPipeline.synthesize(
            text: pipelineFailingCombinedPassage,
            voice: "af_heart",
            speed: 1.0,
            language: .enUS,
            engine: engine
        )

        XCTAssertEqual(engine.inputs.prefix(1), [pipelineFailingCombinedPassage])
        XCTAssertTrue(engine.inputs.contains(pipelineFailingPassagePart1))
        XCTAssertTrue(engine.inputs.contains(pipelineFailingPassagePart2))
        XCTAssertGreaterThan(result.chunkCount, 1)
        XCTAssertFalse(result.samples.isEmpty)
    }

    func testSynthesisPipelineDoesNotRefineFatalUnknownVoiceError() {
        XCTAssertThrowsError(
            try SynthesisPipeline.synthesize(
                text: pipelineFailingCombinedPassage,
                voice: "missing_voice",
                speed: 1.0,
                language: .enUS,
                engine: FailingVoiceSynthesizer()
            )
        ) { error in
            guard let typedError = error as? TTSEngineError else {
                return XCTFail("Expected TTSEngineError, got \(error)")
            }
            guard case TTSEngineError.unknownVoice = typedError else {
                return XCTFail("Expected unknownVoice error, got \(error)")
            }
        }
    }
}

private final class FailingVoiceSynthesizer: SpeechSynthesizing {
    func synthesize(text: String, voice: String, speed: Float, language: TTSEngineLanguage?) throws -> [Float] {
        throw TTSEngineError.unknownVoice(requested: voice, available: ["af_heart"])
    }
}
