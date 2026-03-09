import Foundation
import XCTest
@testable import KokoroEdge

final class TTSEngineTests: XCTestCase {
    func testLanguageInferenceMapsAmericanAndBritishVoices() {
        XCTAssertEqual(TTSEngine.inferredLanguage(forVoiceName: "af_heart"), .enUS)
        XCTAssertEqual(TTSEngine.inferredLanguage(forVoiceName: "am_adam"), .enUS)
        XCTAssertEqual(TTSEngine.inferredLanguage(forVoiceName: "bf_emma"), .enGB)
        XCTAssertEqual(TTSEngine.inferredLanguage(forVoiceName: "bm_lewis"), .enGB)
        XCTAssertEqual(TTSEngine.inferredLanguage(forVoiceName: "unknown_voice"), .enUS)
    }

    func testNormalizedVoiceNameStripsNPYSuffix() {
        XCTAssertEqual(TTSEngine.normalizedVoiceName(from: "af_heart.npy"), "af_heart")
        XCTAssertEqual(TTSEngine.normalizedVoiceName(from: "bf_emma"), "bf_emma")
    }

    func testInitializeSameDirectoryIsNoOpAndDifferentDirectoryThrows() throws {
        try configurePackageResourceBundlesIfNeeded()
        let modelDirectory = try requireDownloadedModelDirectory()
        let engine = TTSEngine()

        try engine.initialize(modelDir: modelDirectory)
        XCTAssertTrue(engine.isInitialized)

        XCTAssertNoThrow(try engine.initialize(modelDir: modelDirectory))

        let otherDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: otherDirectory, withIntermediateDirectories: true)

        XCTAssertThrowsError(try engine.initialize(modelDir: otherDirectory)) { error in
            XCTAssertEqual(
                error as? TTSEngineError,
                .alreadyInitialized(
                    existingModelDir: modelDirectory.resolvingSymlinksInPath().standardizedFileURL.path,
                    requestedModelDir: otherDirectory.resolvingSymlinksInPath().standardizedFileURL.path
                )
            )
        }
    }

    func testAvailableVoicesAndUnknownVoiceError() throws {
        try configurePackageResourceBundlesIfNeeded()
        let modelDirectory = try requireDownloadedModelDirectory()
        let engine = TTSEngine()
        try engine.initialize(modelDir: modelDirectory)

        let voices = engine.availableVoices()
        XCTAssertTrue(voices.contains("af_heart"))
        XCTAssertFalse(voices.contains(where: { $0.hasSuffix(".npy") }))

        XCTAssertThrowsError(try engine.synthesize(text: "Hello world", voice: "missing_voice", speed: 1.0)) { error in
            guard let typedError = error as? TTSEngineError else {
                return XCTFail("Expected unknownVoice error, got \(error)")
            }

            guard case let TTSEngineError.unknownVoice(requested, available) = typedError else {
                return XCTFail("Expected unknownVoice error, got \(typedError)")
            }

            XCTAssertEqual(requested, "missing_voice")
            XCTAssertTrue(available.contains("af_heart"))
        }
    }

    func testInitializeAndSynthesizeWithDownloadedModel() throws {
        try configurePackageResourceBundlesIfNeeded()
        let modelDirectory = try requireDownloadedModelDirectory()
        let engine = TTSEngine()

        try engine.initialize(modelDir: modelDirectory)
        let samples = try engine.synthesize(text: "Hello world", voice: "af_heart", speed: 1.0)

        XCTAssertFalse(samples.isEmpty)
        XCTAssertGreaterThan(samples.count, engine.sampleRate / 2)
    }

    func testRealSynthesisEncodesToWAV() throws {
        try configurePackageResourceBundlesIfNeeded()
        let modelDirectory = try requireDownloadedModelDirectory()
        let engine = TTSEngine()

        try engine.initialize(modelDir: modelDirectory)
        let samples = try engine.synthesize(text: "Testing Kokoro Edge", voice: "af_heart", speed: 1.0)
        let wavData = AudioEncoder.encodeWAV(samples: samples, sampleRate: engine.sampleRate)

        XCTAssertEqual(String(decoding: wavData.prefix(4), as: UTF8.self), "RIFF")
    }

    private func requireDownloadedModelDirectory() throws -> URL {
        let modelDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".kokoro-edge/models/kokoro-82m", isDirectory: true)

        let modelPath = modelDirectory.appendingPathComponent("kokoro-v1_0.safetensors").path
        let voicesPath = modelDirectory.appendingPathComponent("voices.npz").path
        let fileManager = FileManager.default

        try XCTSkipUnless(
            fileManager.fileExists(atPath: modelPath) && fileManager.fileExists(atPath: voicesPath),
            "Downloaded kokoro-82m assets are required for TTSEngine integration tests."
        )

        return modelDirectory
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
            "KokoroSwift resource bundles are required for TTSEngine integration tests under the current build harness."
        )

        setenv("PACKAGE_RESOURCE_BUNDLE_PATH", bundleDirectory!.path, 1)
    }
}
