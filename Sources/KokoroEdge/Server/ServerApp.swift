import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdWebSocket
import NIOCore
import NIOWebSocket

extension HTTPField.Name {
    static let xRequestId = HTTPField.Name("X-Request-Id")!
}

actor ServerVerboseLogger {
    private let enabled: Bool
    private let output = FileHandle.standardError

    init(enabled: Bool) {
        self.enabled = enabled
    }

    func logTTS(voice: String, textLength: Int, chunkCount: Int, audioSeconds: Double, elapsedSeconds: Double) async {
        guard enabled else { return }
        await write(
            "[TTS] voice=\(voice) text=\(textLength)chars chunks=\(chunkCount) synthesized=\(Self.oneDecimal(audioSeconds))s elapsed=\(Self.twoDecimals(elapsedSeconds))s\n"
        )
    }

    func logHTTPStatus(_ code: Int) async {
        guard enabled else { return }
        await write("[STATUS] \(code)\n")
    }

    func logWebSocketStatus() async {
        guard enabled else { return }
        await write("[STATUS] ws\n")
    }

    func logVoices(count: Int) async {
        guard enabled else { return }
        await write("[VOICES] \(count)\n")
    }

    func logParseFailure(source: String, message: String) async {
        guard enabled else { return }
        await write("[ERROR] \(source) \(message)\n")
    }

    private func write(_ string: String) async {
        guard let data = string.data(using: .utf8) else { return }
        try? output.write(contentsOf: data)
    }

    private static func oneDecimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private static func twoDecimals(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

enum ServerAppFactory {
    static func makeApplication(
        service: any TTSServing,
        host: String,
        port: Int,
        verboseLogger: ServerVerboseLogger = ServerVerboseLogger(enabled: false),
        onServerRunning: (@Sendable (Int) async -> Void)? = nil
    ) -> some ApplicationProtocol {
        let router = Router(context: BasicWebSocketRequestContext.self)

        router.get("/v1/status") { _, _ -> Response in
            let payload = await service.statusPayload()
            await verboseLogger.logHTTPStatus(200)
            return Self.jsonResponse(payload)
        }

        router.get("/v1/voices") { _, _ -> Response in
            let response = await service.voicesResponse()
            await verboseLogger.logVoices(count: response.voices.count)
            return Self.jsonResponse(response)
        }

        router.post("/v1/audio/speech") { request, context -> Response in
            do {
                let speechRequest = try await Self.decodeJSON(HTTPSpeechRequest.self, from: request, context: context)
                let requestId = UUID().uuidString
                let synthesis = try await service.synthesize(
                    SynthesisRequest(
                        model: speechRequest.model,
                        text: speechRequest.input,
                        voice: speechRequest.voice,
                        speed: speechRequest.speed,
                        language: speechRequest.language,
                        format: speechRequest.responseFormat
                    )
                )
                await verboseLogger.logTTS(
                    voice: synthesis.voice,
                    textLength: synthesis.textLength,
                    chunkCount: synthesis.chunkCount,
                    audioSeconds: synthesis.audioSeconds,
                    elapsedSeconds: synthesis.elapsedSeconds
                )
                return Self.wavResponse(synthesis.wavData, requestId: requestId)
            } catch let error as ServerRequestError {
                await verboseLogger.logParseFailure(source: "http:/v1/audio/speech", message: error.localizedDescription)
                return Self.errorResponse(error.localizedDescription, status: error.httpStatus)
            } catch {
                await verboseLogger.logParseFailure(source: "http:/v1/audio/speech", message: error.localizedDescription)
                return Self.errorResponse(error.localizedDescription, status: .internalServerError)
            }
        }

        router.on("/v1/status", method: .options) { _, _ -> Response in
            Self.preflightResponse()
        }
        router.on("/v1/voices", method: .options) { _, _ -> Response in
            Self.preflightResponse()
        }
        router.on("/v1/audio/speech", method: .options) { _, _ -> Response in
            Self.preflightResponse()
        }

        router.ws("/ws") { _, _ in
            .upgrade()
        } onUpgrade: { inbound, outbound, _ in
            let encoder = JSONEncoder()
            let decoder = JSONDecoder()

            do {
                for try await message in inbound.messages(maxSize: .max) {
                    switch message {
                    case .text(let text):
                        let envelope: WebSocketRequestEnvelope
                        do {
                            guard let data = text.data(using: .utf8) else {
                                throw ServerRequestError.malformedJSON("Request was not valid UTF-8.")
                            }
                            envelope = try decoder.decode(WebSocketRequestEnvelope.self, from: data)
                        } catch let error as ServerRequestError {
                            try await Self.sendWebSocketError(
                                error.localizedDescription,
                                closeCode: error.webSocketCloseCode,
                                outbound: outbound,
                                encoder: encoder
                            )
                            await verboseLogger.logParseFailure(source: "ws", message: error.localizedDescription)
                            if error.webSocketCloseCode != nil {
                                return
                            }
                            continue
                        } catch {
                            let parseError = ServerRequestError.malformedJSON(error.localizedDescription)
                            try await Self.sendWebSocketError(
                                parseError.localizedDescription,
                                closeCode: parseError.webSocketCloseCode,
                                outbound: outbound,
                                encoder: encoder
                            )
                            await verboseLogger.logParseFailure(source: "ws", message: parseError.localizedDescription)
                            return
                        }

                        switch envelope.type {
                        case .status:
                            let response = await service.webSocketStatusResponse()
                            await verboseLogger.logWebSocketStatus()
                            try await outbound.write(.text(try Self.encodeJSONString(response, encoder: encoder)))
                        case .tts:
                            do {
                                let synthesis = try await service.synthesize(
                                    SynthesisRequest(
                                        model: envelope.model,
                                        text: envelope.text,
                                        voice: envelope.voice,
                                        speed: envelope.speed,
                                        language: envelope.language,
                                        format: envelope.format
                                    )
                                )
                                await verboseLogger.logTTS(
                                    voice: synthesis.voice,
                                    textLength: synthesis.textLength,
                                    chunkCount: synthesis.chunkCount,
                                    audioSeconds: synthesis.audioSeconds,
                                    elapsedSeconds: synthesis.elapsedSeconds
                                )
                                try await outbound.write(.binary(ByteBuffer(bytes: synthesis.wavData)))
                            } catch let error as ServerRequestError {
                                try await Self.sendWebSocketError(
                                    error.localizedDescription,
                                    closeCode: error.webSocketCloseCode,
                                    outbound: outbound,
                                    encoder: encoder
                                )
                                await verboseLogger.logParseFailure(source: "ws", message: error.localizedDescription)
                                if error.webSocketCloseCode != nil {
                                    return
                                }
                            } catch {
                                try await Self.sendWebSocketError(
                                    error.localizedDescription,
                                    closeCode: nil,
                                    outbound: outbound,
                                    encoder: encoder
                                )
                                await verboseLogger.logParseFailure(source: "ws", message: error.localizedDescription)
                            }
                        case .error:
                            let error = ServerRequestError.malformedJSON("Clients may not send type=error.")
                            try await Self.sendWebSocketError(
                                error.localizedDescription,
                                closeCode: error.webSocketCloseCode,
                                outbound: outbound,
                                encoder: encoder
                            )
                            return
                        }

                    case .binary:
                        let error = ServerRequestError.malformedJSON("WebSocket requests must use JSON text frames.")
                        try await Self.sendWebSocketError(
                            error.localizedDescription,
                            closeCode: error.webSocketCloseCode,
                            outbound: outbound,
                            encoder: encoder
                        )
                        await verboseLogger.logParseFailure(source: "ws", message: error.localizedDescription)
                        return
                    }
                }
            } catch {
                await verboseLogger.logParseFailure(source: "ws", message: error.localizedDescription)
            }
        }

        return Application(
            router: router,
            server: .http1WebSocketUpgrade(webSocketRouter: router),
            configuration: .init(
                address: .hostname(host, port: port),
                serverName: "kokoro-edge"
            ),
            onServerRunning: { channel in
                await onServerRunning?(channel.localAddress?.port ?? port)
            }
        )
    }

    private static func decodeJSON<Body: Decodable>(
        _ type: Body.Type,
        from request: Request,
        context: some RequestContext
    ) async throws -> Body {
        do {
            return try await JSONDecoder().decode(type, from: request, context: context)
        } catch {
            throw ServerRequestError.malformedJSON(error.localizedDescription)
        }
    }

    private static func encodeJSONString(_ value: some Encodable, encoder: JSONEncoder) throws -> String {
        let data = try encoder.encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw ServerRequestError.synthesisFailure("Failed to encode JSON response.")
        }
        return string
    }

    private static func sendWebSocketError(
        _ message: String,
        closeCode: WebSocketErrorCode?,
        outbound: WebSocketOutboundWriter,
        encoder: JSONEncoder
    ) async throws {
        try await outbound.write(.text(try encodeJSONString(WebSocketErrorResponse(message: message), encoder: encoder)))
        if let closeCode {
            try await outbound.close(closeCode, reason: nil)
        }
    }

    private static func preflightResponse() -> Response {
        Response(status: .noContent, headers: corsHeaders())
    }

    private static func jsonResponse(_ payload: some Encodable, status: HTTPResponse.Status = .ok) -> Response {
        do {
            let data = try JSONEncoder().encode(payload)
            var headers = corsHeaders()
            headers[.contentType] = "application/json; charset=utf-8"
            headers[.contentLength] = "\(data.count)"
            return Response(
                status: status,
                headers: headers,
                body: .init(byteBuffer: ByteBuffer(bytes: data))
            )
        } catch {
            return errorResponse("Failed to encode JSON response.", status: .internalServerError)
        }
    }

    private static func errorResponse(_ message: String, status: HTTPResponse.Status) -> Response {
        jsonResponse(HTTPErrorPayload(message: message), status: status)
    }

    private static func wavResponse(_ wavData: Data, requestId: String) -> Response {
        var headers = corsHeaders()
        headers[.contentType] = "audio/wav"
        headers[.contentLength] = "\(wavData.count)"
        headers[HTTPField.Name.xRequestId] = requestId
        return Response(
            status: .ok,
            headers: headers,
            body: .init(byteBuffer: ByteBuffer(bytes: wavData))
        )
    }

    private static func corsHeaders() -> HTTPFields {
        var headers = HTTPFields()
        headers[.accessControlAllowOrigin] = "*"
        headers[.accessControlAllowMethods] = "GET, POST, OPTIONS"
        headers[.accessControlAllowHeaders] = "Content-Type"
        headers[.accessControlExposeHeaders] = "X-Request-Id"
        return headers
    }
}
