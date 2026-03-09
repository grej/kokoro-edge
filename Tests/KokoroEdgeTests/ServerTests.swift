import Foundation
import HTTPTypes
import NIOCore
import XCTest
import HummingbirdTesting
@testable import KokoroEdge

final class ServerTests: XCTestCase {
    func testHTTPStatusRouteReturnsExpectedPayloadAndCORSHeaders() async throws {
        let service = StubService()
        let app = ServerAppFactory.makeApplication(service: service, host: "127.0.0.1", port: 0)

        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/status", method: .get) { response in
                XCTAssertEqual(response.status, .ok)
                XCTAssertEqual(response.headers[.accessControlAllowOrigin], "*")
                XCTAssertEqual(response.headers[.accessControlAllowMethods], "GET, POST, OPTIONS")
                let payload = try JSONDecoder().decode(HTTPStatusPayload.self, from: Data(buffer: response.body))
                XCTAssertEqual(payload.model, "kokoro-82m")
                XCTAssertEqual(payload.voicesAvailable.count, 2)
            }
        }
    }

    func testHTTPVoicesRouteReturnsMetadata() async throws {
        let service = StubService()
        let app = ServerAppFactory.makeApplication(service: service, host: "127.0.0.1", port: 0)

        try await app.test(.router) { client in
            try await client.execute(uri: "/v1/voices", method: .get) { response in
                XCTAssertEqual(response.status, .ok)
                let payload = try JSONDecoder().decode(VoicesResponse.self, from: Data(buffer: response.body))
                XCTAssertEqual(payload.voices.first?.name, "af_heart")
                XCTAssertEqual(payload.voices.first?.language, .enUS)
                XCTAssertEqual(payload.voices.first?.gender, .female)
            }
        }
    }

    func testHTTPSpeechRejectsInvalidModel() async throws {
        let service = StubService()
        let app = ServerAppFactory.makeApplication(service: service, host: "127.0.0.1", port: 0)
        let body = #"{"model":"wrong-model","input":"Hello"}"#

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/v1/audio/speech",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: body)
            ) { response in
                XCTAssertEqual(response.status, .badRequest)
                let payload = try JSONDecoder().decode(HTTPErrorPayload.self, from: Data(buffer: response.body))
                XCTAssertTrue(payload.message.contains("Unknown model"))
            }
        }
    }

    func testHTTPSpeechRejectsUnsupportedFormat() async throws {
        let service = StubService()
        let app = ServerAppFactory.makeApplication(service: service, host: "127.0.0.1", port: 0)
        let body = #"{"input":"Hello","response_format":"mp3"}"#

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/v1/audio/speech",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: body)
            ) { response in
                XCTAssertEqual(response.status, .badRequest)
                let payload = try JSONDecoder().decode(HTTPErrorPayload.self, from: Data(buffer: response.body))
                XCTAssertTrue(payload.message.contains("Unsupported format"))
            }
        }
    }

    func testHTTPSpeechSuccessIncludesRequestIDAndWAV() async throws {
        let service = StubService()
        let app = ServerAppFactory.makeApplication(service: service, host: "127.0.0.1", port: 0)
        let body = #"{"input":"Hello","voice":"af_heart"}"#

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/v1/audio/speech",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(string: body)
            ) { response in
                XCTAssertEqual(response.status, .ok)
                XCTAssertEqual(response.headers[HTTPField.Name("X-Request-Id")!]?.isEmpty, false)
                XCTAssertEqual(response.headers[.contentType], "audio/wav")
                let data = Data(buffer: response.body)
                XCTAssertEqual(String(decoding: data.prefix(4), as: UTF8.self), "RIFF")
            }
        }
    }

    func testStatusCommandRenderStatus() {
        let payload = HTTPStatusPayload(
            version: "0.1.0",
            model: "kokoro-82m",
            modelsLoaded: ["kokoro-82m"],
            voicesAvailable: ["af_heart", "af_sky"],
            uptimeSeconds: 12
        )

        let rendered = StatusCommand.renderStatus(payload, host: "localhost", port: 7777)
        XCTAssertTrue(rendered.contains("http://localhost:7777"))
        XCTAssertTrue(rendered.contains("voices: 2"))
    }

    func testModelBackedHTTPAndWebSocketFlows() async throws {
        try configurePackageResourceBundlesIfNeeded()
        try XCTSkipUnless(ModelManager().isAvailable(model: "kokoro-82m"), "Local model bundle is required for integration tests.")

        let service = try TTSService()
        try await withRunningServer(service: service) { [self] port in
            let status = try await self.httpStatus(port: port)
            XCTAssertEqual(status.model, "kokoro-82m")

            let voices = try await self.httpVoices(port: port)
            XCTAssertFalse(voices.voices.isEmpty)

            let speech = try await self.httpSpeech(port: port, body: #"{"input":"Hello from HTTP","voice":"af_sky"}"#)
            XCTAssertEqual(String(decoding: speech.data.prefix(4), as: UTF8.self), "RIFF")
            XCTAssertFalse((speech.requestID ?? "").isEmpty)

            let wsStatus = try await self.webSocketTextExchange(
                port: port,
                message: #"{"type":"status"}"#
            )
            let statusPayload = try JSONDecoder().decode(WebSocketStatusResponse.self, from: Data(wsStatus.utf8))
            XCTAssertEqual(statusPayload.type, .status)

            let wsAudio = try await self.webSocketBinaryExchange(
                port: port,
                message: #"{"type":"tts","text":"Hello world","voice":"af_heart","format":"wav"}"#
            )
            XCTAssertEqual(String(decoding: wsAudio.prefix(4), as: UTF8.self), "RIFF")

            let malformed = try await self.webSocketExchangeExpectingClose(
                port: port,
                message: "{bad json"
            )
            XCTAssertEqual(malformed.error.type, .error)
            XCTAssertEqual(malformed.closeCode, .unsupportedData)

            let policy = try await self.webSocketExchangeExpectingClose(
                port: port,
                message: #"{"type":"tts","text":"Hello","model":"wrong-model","format":"wav"}"#
            )
            XCTAssertEqual(policy.error.type, .error)
            XCTAssertEqual(policy.closeCode, .policyViolation)

            let wsAudioSecond = try await self.webSocketBinaryExchange(
                port: port,
                message: #"{"type":"tts","text":"Second request","voice":"af_heart"}"#
            )
            XCTAssertEqual(String(decoding: wsAudioSecond.prefix(4), as: UTF8.self), "RIFF")
        }
    }

    private func configurePackageResourceBundlesIfNeeded() throws {
        let environment = ProcessInfo.processInfo.environment
        if environment["PACKAGE_RESOURCE_BUNDLE_PATH"] != nil || environment["PACKAGE_RESOURCE_BUNDLE_URL"] != nil {
            return
        }

        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let candidateDirectories = [
            repoRoot.appendingPathComponent(".build-xcode/DerivedData/Build/Products/Debug", isDirectory: true),
            repoRoot.appendingPathComponent(".build/arm64-apple-macosx/debug", isDirectory: true),
        ]

        let fileManager = FileManager.default
        let bundleDirectory = candidateDirectories.first { directory in
            let kokoroBundle = directory.appendingPathComponent("KokoroSwift_KokoroSwift.bundle").path
            let misakiBundle = directory.appendingPathComponent("MisakiSwift_MisakiSwift.bundle").path
            return fileManager.fileExists(atPath: kokoroBundle) && fileManager.fileExists(atPath: misakiBundle)
        }

        try XCTSkipUnless(
            bundleDirectory != nil,
            "KokoroSwift resource bundles are required for model-backed server integration tests under the current build harness."
        )

        setenv("PACKAGE_RESOURCE_BUNDLE_PATH", bundleDirectory!.path, 1)
    }
}

private actor StubService: TTSServing {
    func statusPayload() async -> HTTPStatusPayload {
        HTTPStatusPayload(
            version: "0.1.0",
            model: "kokoro-82m",
            modelsLoaded: ["kokoro-82m"],
            voicesAvailable: ["af_heart", "bf_emma"],
            uptimeSeconds: 99
        )
    }

    func webSocketStatusResponse() async -> WebSocketStatusResponse {
        WebSocketStatusResponse(
            version: "0.1.0",
            model: "kokoro-82m",
            modelsLoaded: ["kokoro-82m"],
            voicesAvailable: ["af_heart", "bf_emma"],
            uptimeSeconds: 99
        )
    }

    func voicesResponse() async -> VoicesResponse {
        VoicesResponse(
            voices: [
                VoiceDescriptor(name: "af_heart", language: .enUS, gender: .female),
                VoiceDescriptor(name: "bf_emma", language: .enGB, gender: .female),
            ]
        )
    }

    func synthesize(_ request: SynthesisRequest) async throws -> SynthesisResult {
        if let model = request.model, model != "kokoro-82m" {
            throw ServerRequestError.unknownModel(model)
        }
        if let format = request.format?.lowercased(), format != "wav" {
            throw ServerRequestError.unsupportedFormat(format)
        }
        guard let text = request.text, !text.isEmpty else {
            throw ServerRequestError.emptyText
        }
        let samples = [Float](repeating: 0.1, count: 2_400)
        return SynthesisResult(
            wavData: AudioEncoder.encodeWAV(samples: samples, sampleRate: 24_000),
            audioSeconds: 0.1,
            elapsedSeconds: 0.01,
            voice: request.voice ?? "af_heart",
            textLength: text.count,
            chunkCount: 1
        )
    }
}

private extension ServerTests {
    func withRunningServer(
        service: any TTSServing,
        operation: @escaping (Int) async throws -> Void
    ) async throws {
        let stream = AsyncStream.makeStream(of: Int.self)
        let app = ServerAppFactory.makeApplication(
            service: service,
            host: "127.0.0.1",
            port: 0,
            onServerRunning: { port in
                stream.continuation.yield(port)
                stream.continuation.finish()
            }
        )

        let serverTask = Task {
            do {
                try await app.runService(gracefulShutdownSignals: [])
            } catch is CancellationError {
            } catch {
                let description = String(describing: error)
                if Task.isCancelled || description.contains("ServiceGroupError") {
                    return
                }
                XCTFail("Server task failed: \(error)")
            }
        }

        guard let port = await stream.stream.first(where: { _ in true }) else {
            serverTask.cancel()
            XCTFail("Server did not start.")
            return
        }

        defer {
            serverTask.cancel()
        }

        try await operation(port)
        serverTask.cancel()
        _ = await serverTask.result
    }

    func httpStatus(port: Int) async throws -> HTTPStatusPayload {
        let (data, _) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/v1/status")!)
        return try JSONDecoder().decode(HTTPStatusPayload.self, from: data)
    }

    func httpVoices(port: Int) async throws -> VoicesResponse {
        let (data, _) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/v1/voices")!)
        return try JSONDecoder().decode(VoicesResponse.self, from: data)
    }

    func httpSpeech(port: Int, body: String) async throws -> (data: Data, requestID: String?) {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/v1/audio/speech")!)
        request.httpMethod = "POST"
        request.httpBody = Data(body.utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.data(for: request)
        let requestID = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "X-Request-Id")
        return (data, requestID)
    }

    func webSocketTextExchange(port: Int, message: String) async throws -> String {
        let socket = URLSession.shared.webSocketTask(with: URL(string: "ws://127.0.0.1:\(port)/ws")!)
        socket.resume()
        defer { socket.cancel(with: .normalClosure, reason: nil) }

        try await socket.send(.string(message))
        let response = try await socket.receive()
        switch response {
        case .string(let text):
            return text
        case .data:
            XCTFail("Expected text frame.")
            return ""
        @unknown default:
            XCTFail("Unexpected WebSocket response.")
            return ""
        }
    }

    func webSocketBinaryExchange(port: Int, message: String) async throws -> Data {
        let socket = URLSession.shared.webSocketTask(with: URL(string: "ws://127.0.0.1:\(port)/ws")!)
        socket.resume()
        defer { socket.cancel(with: .normalClosure, reason: nil) }

        try await socket.send(.string(message))
        let response = try await socket.receive()
        switch response {
        case .data(let data):
            return data
        case .string:
            XCTFail("Expected binary frame.")
            return Data()
        @unknown default:
            XCTFail("Unexpected WebSocket response.")
            return Data()
        }
    }

    func webSocketExchangeExpectingClose(
        port: Int,
        message: String
    ) async throws -> (error: WebSocketErrorResponse, closeCode: URLSessionWebSocketTask.CloseCode) {
        let socket = URLSession.shared.webSocketTask(with: URL(string: "ws://127.0.0.1:\(port)/ws")!)
        socket.resume()

        try await socket.send(.string(message))
        let first = try await socket.receive()
        let payload: WebSocketErrorResponse

        switch first {
        case .string(let text):
            payload = try JSONDecoder().decode(WebSocketErrorResponse.self, from: Data(text.utf8))
        case .data:
            XCTFail("Expected JSON error frame.")
            payload = WebSocketErrorResponse(message: "unexpected binary")
        @unknown default:
            XCTFail("Unexpected WebSocket response.")
            payload = WebSocketErrorResponse(message: "unexpected response")
        }

        let closeCode = try await waitForCloseCode(of: socket)
        return (payload, closeCode)
    }

    func waitForCloseCode(of socket: URLSessionWebSocketTask) async throws -> URLSessionWebSocketTask.CloseCode {
        for _ in 0..<20 {
            if socket.closeCode != .invalid {
                return socket.closeCode
            }
            do {
                _ = try await socket.receive()
            } catch {
                if socket.closeCode != .invalid {
                    return socket.closeCode
                }
            }
            try await Task.sleep(for: .milliseconds(50))
        }

        XCTFail("WebSocket did not close in time.")
        return socket.closeCode
    }
}

private extension Data {
    init(buffer: ByteBuffer) {
        var buffer = buffer
        self = buffer.readData(length: buffer.readableBytes) ?? Data()
    }
}
