import Foundation
import KokoroSwift
import MLX
import MLXUtilsLibrary

// Upstream integration contract:
// - KokoroTTS initializes with a URL to kokoro-v1_0.safetensors, not the model directory.
// - Voices are loaded from voices.npz using NpyzReader.read(fileFromPath:).
// - Voice dictionary keys include the .npy suffix and must be normalized for CLI use.
// - generateAudio returns ([Float], [MToken]?), and the token timing data is ignored in Step 3.

enum TTSEngineLanguage: String, CaseIterable, Codable, Sendable {
    case enUS = "en-us"
    case enGB = "en-gb"

    var kokoroLanguage: Language {
        switch self {
        case .enUS:
            return .enUS
        case .enGB:
            return .enGB
        }
    }

    static func inferred(fromVoiceName voiceName: String) -> TTSEngineLanguage {
        if voiceName.hasPrefix("bf_") || voiceName.hasPrefix("bm_") {
            return .enGB
        }

        return .enUS
    }
}

enum TTSEngineError: LocalizedError, Equatable {
    case engineNotInitialized
    case missingRequiredFile(String)
    case noVoicesFound
    case unknownVoice(requested: String, available: [String])
    case emptyText
    case invalidSpeed(Float)
    case tooManyTokens
    case alreadyInitialized(existingModelDir: String, requestedModelDir: String)

    var errorDescription: String? {
        switch self {
        case .engineNotInitialized:
            return "TTS engine is not initialized."
        case .missingRequiredFile(let path):
            return "Missing required model asset at \(path)."
        case .noVoicesFound:
            return "No voices were loaded from voices.npz."
        case .unknownVoice(let requested, let available):
            return "Unknown voice '\(requested)'. Available voices: \(available.joined(separator: ", "))"
        case .emptyText:
            return "Input text is empty."
        case .invalidSpeed(let speed):
            return "Speed must be greater than 0. Received \(speed)."
        case .tooManyTokens:
            return "Input text exceeds Kokoro's maximum token limit."
        case .alreadyInitialized(let existingModelDir, let requestedModelDir):
            return "TTS engine is already initialized for \(existingModelDir) and cannot be reinitialized for \(requestedModelDir) in the same process."
        }
    }
}

final class TTSEngine {
    private var tts: KokoroTTS?
    private var voicesByCLIName: [String: MLXArray] = [:]
    private(set) var sampleRate: Int = KokoroTTS.Constants.samplingRate
    private var initializedModelDir: URL?

    var isInitialized: Bool {
        tts != nil && !voicesByCLIName.isEmpty
    }

    func initialize(modelDir: URL) throws {
        let resolvedModelDir = resolveModelDirectory(modelDir)

        if isInitialized {
            guard let initializedModelDir else {
                throw TTSEngineError.engineNotInitialized
            }

            if initializedModelDir == resolvedModelDir {
                return
            }

            throw TTSEngineError.alreadyInitialized(
                existingModelDir: initializedModelDir.path,
                requestedModelDir: resolvedModelDir.path
            )
        }

        let modelFileURL = resolvedModelDir.appendingPathComponent("kokoro-v1_0.safetensors")
        let voicesFileURL = resolvedModelDir.appendingPathComponent("voices.npz")
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: modelFileURL.path) else {
            throw TTSEngineError.missingRequiredFile(modelFileURL.path)
        }

        guard fileManager.fileExists(atPath: voicesFileURL.path) else {
            throw TTSEngineError.missingRequiredFile(voicesFileURL.path)
        }

        let rawVoices = NpyzReader.read(fileFromPath: voicesFileURL) ?? [:]
        let normalizedVoices = Self.normalizedVoiceMap(from: rawVoices)

        guard !normalizedVoices.isEmpty else {
            throw TTSEngineError.noVoicesFound
        }

        let engine = KokoroTTS(modelPath: modelFileURL)

        tts = engine
        voicesByCLIName = normalizedVoices
        initializedModelDir = resolvedModelDir
        sampleRate = KokoroTTS.Constants.samplingRate

        do {
            let warmupVoice = voicesByCLIName.keys.contains("af_heart") ? "af_heart" : availableVoices().first!
            _ = try synthesize(text: "warmup", voice: warmupVoice, speed: 1.0)
        } catch {
            tts = nil
            voicesByCLIName = [:]
            initializedModelDir = nil
            throw error
        }
    }

    func synthesize(text: String, voice: String, speed: Float, language: TTSEngineLanguage? = nil) throws -> [Float] {
        guard let tts else {
            throw TTSEngineError.engineNotInitialized
        }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw TTSEngineError.emptyText
        }

        guard speed > 0 else {
            throw TTSEngineError.invalidSpeed(speed)
        }

        guard let voiceEmbedding = voicesByCLIName[voice] else {
            throw TTSEngineError.unknownVoice(requested: voice, available: availableVoices())
        }

        let selectedLanguage = (language ?? Self.inferredLanguage(forVoiceName: voice)).kokoroLanguage
        let audioSamples: [Float]
        let tokenTimings: [MToken]?
        do {
            (audioSamples, tokenTimings) = try tts.generateAudio(
                voice: voiceEmbedding,
                language: selectedLanguage,
                text: trimmedText,
                speed: speed
            )
        } catch KokoroTTS.KokoroTTSError.tooManyTokens {
            throw TTSEngineError.tooManyTokens
        }
        _ = tokenTimings // Intentionally ignored in Step 3; later tutor features will use timings for synchronized highlighting.

        return audioSamples
    }

    func availableVoices() -> [String] {
        voicesByCLIName.keys.sorted()
    }

    static func normalizedVoiceName(from rawKey: String) -> String {
        rawKey.hasSuffix(".npy") ? String(rawKey.dropLast(4)) : rawKey
    }

    static func normalizedVoiceMap(from rawVoices: [String: MLXArray]) -> [String: MLXArray] {
        Dictionary(uniqueKeysWithValues: rawVoices.map { key, value in
            (normalizedVoiceName(from: key), value)
        })
    }

    static func inferredLanguage(forVoiceName voiceName: String) -> TTSEngineLanguage {
        TTSEngineLanguage.inferred(fromVoiceName: voiceName)
    }

    private func resolveModelDirectory(_ modelDir: URL) -> URL {
        modelDir.resolvingSymlinksInPath().standardizedFileURL
    }
}
