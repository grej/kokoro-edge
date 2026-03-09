import Foundation

enum ServerMessageType: String, Codable, Sendable {
    case tts
    case status
    case error
}

enum VoiceGender: String, Codable, Sendable {
    case female = "F"
    case male = "M"
    case unknown
}

struct WebSocketRequestEnvelope: Codable, Equatable, Sendable {
    let type: ServerMessageType
    let model: String?
    let text: String?
    let voice: String?
    let speed: Double?
    let language: TTSEngineLanguage?
    let format: String?
}

struct WebSocketStatusResponse: Codable, Equatable, Sendable {
    var type: ServerMessageType = .status
    let version: String
    let model: String
    let modelsLoaded: [String]
    let voicesAvailable: [String]
    let uptimeSeconds: Int

    enum CodingKeys: String, CodingKey {
        case type
        case version
        case model
        case modelsLoaded = "models_loaded"
        case voicesAvailable = "voices_available"
        case uptimeSeconds = "uptime_seconds"
    }
}

struct WebSocketErrorResponse: Codable, Equatable, Sendable {
    var type: ServerMessageType = .error
    let message: String
}

struct HTTPSpeechRequest: Codable, Equatable, Sendable {
    let model: String?
    let input: String?
    let voice: String?
    let speed: Double?
    let responseFormat: String?
    let language: TTSEngineLanguage?

    enum CodingKeys: String, CodingKey {
        case model
        case input
        case voice
        case speed
        case responseFormat = "response_format"
        case language
    }
}

struct HTTPStatusPayload: Codable, Equatable, Sendable {
    let version: String
    let model: String
    let modelsLoaded: [String]
    let voicesAvailable: [String]
    let uptimeSeconds: Int

    enum CodingKeys: String, CodingKey {
        case version
        case model
        case modelsLoaded = "models_loaded"
        case voicesAvailable = "voices_available"
        case uptimeSeconds = "uptime_seconds"
    }
}

struct HTTPErrorPayload: Codable, Equatable, Sendable {
    let message: String
}

struct VoiceDescriptor: Codable, Equatable, Sendable {
    let name: String
    let language: TTSEngineLanguage
    let gender: VoiceGender
}

struct VoicesResponse: Codable, Equatable, Sendable {
    let voices: [VoiceDescriptor]
}
