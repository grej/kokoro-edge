import Foundation

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
        engine: TTSEngine
    ) throws -> SynthesisPipelineResult {
        let prepared = TextPreprocessor.prepare(text)
        return try synthesize(chunks: prepared.chunks, voice: voice, speed: speed, language: language, engine: engine)
    }

    private static func synthesize(
        chunks: [String],
        voice: String,
        speed: Float,
        language: TTSEngineLanguage?,
        engine: TTSEngine
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
        engine: TTSEngine
    ) throws -> SynthesisPipelineResult {
        do {
            let samples = try engine.synthesize(text: text, voice: voice, speed: speed, language: language)
            return SynthesisPipelineResult(samples: samples, chunkCount: 1)
        } catch TTSEngineError.tooManyTokens {
            let refinedChunks = TextPreprocessor.refine(text)
            guard refinedChunks.count > 1 else {
                throw TTSEngineError.tooManyTokens
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
}
