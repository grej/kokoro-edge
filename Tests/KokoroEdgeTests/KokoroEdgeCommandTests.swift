import XCTest
@testable import KokoroEdge

final class KokoroEdgeCommandTests: XCTestCase {
    func testServeCommandDefaults() throws {
        let command = try ServeCommand.parse(["--host", "127.0.0.1"])

        XCTAssertEqual(command.host, "127.0.0.1")
        XCTAssertEqual(command.port, 7777)
        XCTAssertFalse(command.daemon)
        XCTAssertFalse(command.verbose)
        XCTAssertFalse(command.skipDownload)
    }

    func testServeCommandParsesVerboseFlag() throws {
        let command = try ServeCommand.parse(["--verbose"])

        XCTAssertTrue(command.verbose)
    }

    func testServeCommandParsesSkipDownloadFlag() throws {
        let command = try ServeCommand.parse(["--skip-download"])

        XCTAssertTrue(command.skipDownload)
    }

    func testTTSCommandParsesArguments() throws {
        let command = try TTSCommand.parse([
            "Hello world",
            "--voice",
            "af_sky",
            "--speed",
            "1.2",
            "--output",
            "out.wav",
        ])

        XCTAssertEqual(command.text, "Hello world")
        XCTAssertEqual(command.voice, "af_sky")
        XCTAssertEqual(command.speed, 1.2, accuracy: 0.0001)
        XCTAssertEqual(command.language, nil)
        XCTAssertEqual(command.output, "out.wav")
    }

    func testTTSCommandParsesLanguageOption() throws {
        let command = try TTSCommand.parse([
            "Hello world",
            "--language",
            "en-gb",
        ])

        XCTAssertEqual(command.language, .enGB)
    }

    func testModelsPullRequiresModelName() throws {
        let command = try ModelsPullCommand.parse(["kokoro-82m"])

        XCTAssertEqual(command.modelName, "kokoro-82m")
    }

    func testModelsListParsesWithoutArguments() throws {
        _ = try ModelsListCommand.parse([])
    }

    func testStatusCommandDefaults() throws {
        let command = try StatusCommand.parse([])

        XCTAssertEqual(command.host, "localhost")
        XCTAssertEqual(command.port, 7777)
    }

    func testDoctorCommandDefaults() throws {
        let command = try DoctorCommand.parse([])

        XCTAssertEqual(command.host, "localhost")
        XCTAssertEqual(command.port, 7777)
    }

    func testRootWelcomeMessageMentionsQuickStartCommands() {
        XCTAssertTrue(KokoroEdgeCommand.welcomeMessage.contains("kokoro-edge serve"))
        XCTAssertTrue(KokoroEdgeCommand.welcomeMessage.contains("kokoro-edge tts"))
        XCTAssertTrue(KokoroEdgeCommand.welcomeMessage.contains("kokoro-edge status"))
    }
}
