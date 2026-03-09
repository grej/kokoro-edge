import XCTest
@testable import KokoroEdge

final class ProtocolTests: XCTestCase {
    func testWebSocketRequestRoundTrip() throws {
        let request = WebSocketRequestEnvelope(
            type: .tts,
            model: "kokoro-82m",
            text: "Hello",
            voice: "af_heart",
            speed: 1.0,
            language: .enUS,
            format: "wav"
        )

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(WebSocketRequestEnvelope.self, from: data)

        XCTAssertEqual(decoded, request)
    }

    func testWebSocketStatusResponseRoundTrip() throws {
        let response = WebSocketStatusResponse(
            version: "0.1.0",
            model: "kokoro-82m",
            modelsLoaded: ["kokoro-82m"],
            voicesAvailable: ["af_heart", "af_sky"],
            uptimeSeconds: 42
        )

        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(WebSocketStatusResponse.self, from: data)

        XCTAssertEqual(decoded.type, .status)
        XCTAssertEqual(decoded.model, "kokoro-82m")
        XCTAssertEqual(decoded.voicesAvailable, ["af_heart", "af_sky"])
    }

    func testWebSocketErrorResponseRoundTrip() throws {
        let response = WebSocketErrorResponse(message: "Unknown voice")

        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(WebSocketErrorResponse.self, from: data)

        XCTAssertEqual(decoded.type, .error)
        XCTAssertEqual(decoded.message, "Unknown voice")
    }

    func testHTTPSpeechRequestCodingKeys() throws {
        let json = """
        {
          "model": "kokoro-82m",
          "input": "Hello",
          "voice": "af_heart",
          "speed": 1.0,
          "response_format": "wav",
          "language": "en-us"
        }
        """

        let decoded = try JSONDecoder().decode(HTTPSpeechRequest.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.model, "kokoro-82m")
        XCTAssertEqual(decoded.input, "Hello")
        XCTAssertEqual(decoded.responseFormat, "wav")
        XCTAssertEqual(decoded.language, .enUS)
    }
}
