import Foundation

protocol SpeechSynthesizing {
    func synthesize(text: String, voice: String, speed: Float, language: TTSEngineLanguage?) throws -> [Float]
}

extension TTSEngine: SpeechSynthesizing {}

struct SynthesisPipelineResult {
    let samples: [Float]
    let chunkCount: Int
}

enum SynthesisPipeline {
    static func synthesize(
        text: String,
        voice: String,
        speed: Float,
        language: TTSEngineLanguage?,
        engine: any SpeechSynthesizing
    ) throws -> SynthesisPipelineResult {
        let prepared = TextPreprocessor.prepare(text)
        return try synthesize(chunks: prepared.chunks, voice: voice, speed: speed, language: language, engine: engine)
    }

    private static func synthesize(
        chunks: [String],
        voice: String,
        speed: Float,
        language: TTSEngineLanguage?,
        engine: any SpeechSynthesizing
    ) throws -> SynthesisPipelineResult {
        var allSamples: [Float] = []
        var totalChunkCount = 0

        for chunk in chunks {
            let chunkResult = try synthesizeChunk(
                chunk,
                voice: voice,
                speed: speed,
                language: language,
                engine: engine
            )
            allSamples.append(contentsOf: chunkResult.samples)
            totalChunkCount += chunkResult.chunkCount
        }

        return SynthesisPipelineResult(samples: allSamples, chunkCount: totalChunkCount)
    }

    private static func synthesizeChunk(
        _ text: String,
        voice: String,
        speed: Float,
        language: TTSEngineLanguage?,
        engine: any SpeechSynthesizing
    ) throws -> SynthesisPipelineResult {
        do {
            let samples = try engine.synthesize(text: text, voice: voice, speed: speed, language: language)
            return SynthesisPipelineResult(samples: samples, chunkCount: 1)
        } catch {
            guard shouldRefine(after: error) else {
                throw error
            }
            let refinedChunks = TextPreprocessor.refine(text)
            guard refinedChunks.count > 1 else {
                throw error
            }
            return try synthesize(
                chunks: refinedChunks,
                voice: voice,
                speed: speed,
                language: language,
                engine: engine
            )
        }
    }

    private static func shouldRefine(after error: Error) -> Bool {
        guard let typedError = error as? TTSEngineError else {
            return true
        }

        switch typedError {
        case .tooManyTokens:
            return true
        case .engineNotInitialized,
             .missingRequiredFile,
             .noVoicesFound,
             .unknownVoice,
             .emptyText,
             .invalidSpeed,
             .alreadyInitialized:
            return false
        }
    }
}
