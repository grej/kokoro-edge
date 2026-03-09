import Foundation
import Hummingbird
import NIOWebSocket

struct SynthesisRequest: Sendable {
    let model: String?
    let text: String?
    let voice: String?
    let speed: Double?
    let language: TTSEngineLanguage?
    let format: String?
}

struct SynthesisResult: Sendable {
    let wavData: Data
    let audioSeconds: Double
    let elapsedSeconds: Double
    let voice: String
    let textLength: Int
    let chunkCount: Int
}

protocol TTSServing: Sendable {
    func statusPayload() async -> HTTPStatusPayload
    func webSocketStatusResponse() async -> WebSocketStatusResponse
    func voicesResponse() async -> VoicesResponse
    func synthesize(_ request: SynthesisRequest) async throws -> SynthesisResult
}

enum ServerStartupError: LocalizedError, Equatable {
    case modelUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .modelUnavailable(let model):
            return "Model not found. Run 'kokoro-edge models pull \(model)' first."
        }
    }
}

enum ServerRequestError: LocalizedError, Equatable {
    case malformedJSON(String)
    case unknownModel(String)
    case unsupportedFormat(String)
    case emptyText
    case unknownVoice(String)
    case invalidSpeed(Double)
    case synthesisFailure(String)

    var errorDescription: String? {
        switch self {
        case .malformedJSON(let details):
            return "Malformed JSON: \(details)"
        case .unknownModel(let model):
            return "Unknown model '\(model)'."
        case .unsupportedFormat(let format):
            return "Unsupported format '\(format)'. Only wav is supported."
        case .emptyText:
            return "Input text is empty."
        case .unknownVoice(let message):
            return message
        case .invalidSpeed(let speed):
            return "Speed must be greater than 0. Received \(speed)."
        case .synthesisFailure(let message):
            return message
        }
    }

    var httpStatus: HTTPResponse.Status {
        switch self {
        case .malformedJSON, .unknownModel, .unsupportedFormat, .emptyText, .unknownVoice, .invalidSpeed:
            return .badRequest
        case .synthesisFailure:
            return .internalServerError
        }
    }

    var webSocketCloseCode: WebSocketErrorCode? {
        switch self {
        case .malformedJSON:
            return WebSocketErrorCode.unacceptableData
        case .unknownModel, .unsupportedFormat:
            return WebSocketErrorCode.policyViolation
        case .emptyText, .unknownVoice, .invalidSpeed, .synthesisFailure:
            return nil
        }
    }
}

actor TTSService: TTSServing {
    let modelName: String
    private let engine: TTSEngine
    private let startupDate: Date

    init(
        modelName: String = "kokoro-82m",
        modelManager: ModelManager = ModelManager(),
        startupDate: Date = Date()
    ) throws {
        guard modelManager.isAvailable(model: modelName) else {
            throw ServerStartupError.modelUnavailable(modelName)
        }

        let modelDirectory = try modelManager.modelPath(for: modelName)
        let engine = TTSEngine()
        try engine.initialize(modelDir: modelDirectory)

        self.modelName = modelName
        self.engine = engine
        self.startupDate = startupDate
    }

    func statusPayload() async -> HTTPStatusPayload {
        HTTPStatusPayload(
            version: KokoroEdgeVersion.current,
            model: modelName,
            modelsLoaded: [modelName],
            voicesAvailable: engine.availableVoices(),
            uptimeSeconds: max(0, Int(Date().timeIntervalSince(startupDate)))
        )
    }

    func webSocketStatusResponse() async -> WebSocketStatusResponse {
        let payload = await statusPayload()
        return WebSocketStatusResponse(
            version: payload.version,
            model: payload.model,
            modelsLoaded: payload.modelsLoaded,
            voicesAvailable: payload.voicesAvailable,
            uptimeSeconds: payload.uptimeSeconds
        )
    }

    func voicesResponse() async -> VoicesResponse {
        VoicesResponse(voices: engine.availableVoices().map(Self.voiceDescriptor(for:)))
    }

    func synthesize(_ request: SynthesisRequest) async throws -> SynthesisResult {
        if let model = request.model, model != modelName {
            throw ServerRequestError.unknownModel(model)
        }

        let format = request.format?.lowercased() ?? "wav"
        guard format == "wav" else {
            throw ServerRequestError.unsupportedFormat(format)
        }

        guard let rawText = request.text?.trimmingCharacters(in: .whitespacesAndNewlines), !rawText.isEmpty else {
            throw ServerRequestError.emptyText
        }

        let voice = request.voice ?? "af_heart"
        let speed = request.speed ?? 1.0
        guard speed > 0 else {
            throw ServerRequestError.invalidSpeed(speed)
        }

        let startTime = Date()

        do {
            let synthesis = try SynthesisPipeline.synthesize(
                text: rawText,
                voice: voice,
                speed: Float(speed),
                language: request.language,
                engine: engine
            )
            let wavData = AudioEncoder.encodeWAV(samples: synthesis.samples, sampleRate: engine.sampleRate)
            let elapsedSeconds = Date().timeIntervalSince(startTime)
            let audioSeconds = Double(synthesis.samples.count) / Double(engine.sampleRate)

            return SynthesisResult(
                wavData: wavData,
                audioSeconds: audioSeconds,
                elapsedSeconds: elapsedSeconds,
                voice: voice,
                textLength: rawText.count,
                chunkCount: max(1, synthesis.chunkCount)
            )
        } catch let error as TTSEngineError {
            switch error {
            case .unknownVoice:
                throw ServerRequestError.unknownVoice(error.localizedDescription)
            case .emptyText:
                throw ServerRequestError.emptyText
            case .invalidSpeed(let speed):
                throw ServerRequestError.invalidSpeed(Double(speed))
            default:
                throw ServerRequestError.synthesisFailure(error.localizedDescription)
            }
        } catch {
            throw ServerRequestError.synthesisFailure(error.localizedDescription)
        }
    }

    static func voiceDescriptor(for voiceName: String) -> VoiceDescriptor {
        let language = TTSEngine.inferredLanguage(forVoiceName: voiceName)
        let gender: VoiceGender

        if voiceName.hasPrefix("af_") || voiceName.hasPrefix("bf_") {
            gender = .female
        } else if voiceName.hasPrefix("am_") || voiceName.hasPrefix("bm_") {
            gender = .male
        } else {
            gender = .unknown
        }

        return VoiceDescriptor(name: voiceName, language: language, gender: gender)
    }
}
