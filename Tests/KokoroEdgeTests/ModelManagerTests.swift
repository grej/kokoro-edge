import Foundation
import XCTest
@testable import KokoroEdge

final class ModelManagerTests: XCTestCase {
    func testModelPathResolvesUnderKokoroEdgeModelsDirectory() throws {
        let homeDirectory = makeTemporaryHome()
        let manager = makeManager(homeDirectory: homeDirectory)

        let path = try manager.modelPath(for: "test-model")

        XCTAssertTrue(path.path.hasPrefix(homeDirectory.path))
        XCTAssertTrue(path.path.contains("/.kokoro-edge/models/test-model"))
    }

    func testStatusReportsIncompleteWhenFilesAreMissing() throws {
        let homeDirectory = makeTemporaryHome()
        let manifest = makeManifest()
        let fileURL = homeDirectory
            .appendingPathComponent(".kokoro-edge/models/test-model")
            .appendingPathComponent("config.json")
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try manifest.files[1].remoteURL.absoluteString.data(using: .utf8)!.write(to: fileURL)

        let manager = makeManager(homeDirectory: homeDirectory)
        let status = try manager.status(for: "test-model")

        XCTAssertFalse(status.isAvailable)
        XCTAssertEqual(status.downloadedBytes, 0)
        XCTAssertEqual(status.totalBytes, manifest.totalBytes)
    }

    func testIsAvailableRequiresAllFilesAndValidChecksums() throws {
        let homeDirectory = makeTemporaryHome()
        let manifest = makeManifest()
        let manager = makeManager(homeDirectory: homeDirectory)
        let modelPath = try manager.modelPath(for: "test-model")
        try FileManager.default.createDirectory(at: modelPath, withIntermediateDirectories: true)

        for file in manifest.files {
            let destination = modelPath.appendingPathComponent(file.localPath)
            try fileData(for: file).write(to: destination)
        }

        XCTAssertTrue(manager.isAvailable(model: "test-model"))

        try "corrupt".data(using: .utf8)!.write(to: modelPath.appendingPathComponent(manifest.files[0].localPath))
        XCTAssertFalse(manager.isAvailable(model: "test-model"))
    }

    func testPullDownloadsFilesAndSkipsVerifiedOnSecondRun() async throws {
        let homeDirectory = makeTemporaryHome()
        let downloader = StubDownloader(payloads: stubPayloads())
        let manager = makeManager(homeDirectory: homeDirectory, downloader: downloader)

        try await manager.pull(model: "test-model")
        XCTAssertEqual(downloader.downloadedURLs.count, 3)

        try await manager.pull(model: "test-model")
        XCTAssertEqual(downloader.downloadedURLs.count, 3)
    }

    func testPullFailsOnChecksumMismatchAndLeavesNoPartialFile() async throws {
        let homeDirectory = makeTemporaryHome()
        let badData = "wrong".data(using: .utf8)!
        let badURL = URL(string: "https://example.com/model.bin")!
        let manifest = makeManifest()
        let registry = ModelRegistry(manifests: [
            ModelManifest(
                name: manifest.name,
                displayName: manifest.displayName,
                description: manifest.description,
                files: [
                    FileEntry(
                        localPath: "model.bin",
                        remoteURL: badURL,
                        sha256: Checksum.sha256Hex(for: "expected".data(using: .utf8)!),
                        sizeBytes: Int64(badData.count)
                    ),
                ]
            ),
        ])
        let downloader = StubDownloader(payloads: [badURL: .success(badData)])
        let manager = ModelManager(
            registry: registry,
            downloader: downloader,
            homeDirectory: homeDirectory
        )

        await XCTAssertThrowsErrorAsync(try await manager.pull(model: "test-model")) { error in
            XCTAssertEqual(
                error as? ModelManagerError,
                .checksumMismatch(
                    file: "model.bin",
                    expected: Checksum.sha256Hex(for: "expected".data(using: .utf8)!),
                    actual: Checksum.sha256Hex(for: badData)
                )
            )
        }

        let partial = homeDirectory
            .appendingPathComponent(".kokoro-edge/models/test-model/model.bin.part")
        XCTAssertFalse(FileManager.default.fileExists(atPath: partial.path))
    }

    func testPullReplacesLeftoverPartialFile() async throws {
        let homeDirectory = makeTemporaryHome()
        let manager = makeManager(homeDirectory: homeDirectory, downloader: StubDownloader(payloads: stubPayloads()))
        let modelPath = try manager.modelPath(for: "test-model")
        let partial = modelPath.appendingPathComponent("model.bin.part")
        try FileManager.default.createDirectory(at: partial.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "stale".data(using: .utf8)!.write(to: partial)

        try await manager.pull(model: "test-model")

        XCTAssertFalse(FileManager.default.fileExists(atPath: partial.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: modelPath.appendingPathComponent("model.bin").path))
    }

    private func makeManager(
        homeDirectory: URL,
        downloader: any FileDownloading = StubDownloader(payloads: [:])
    ) -> ModelManager {
        ModelManager(
            registry: ModelRegistry(manifests: [makeManifest()]),
            downloader: downloader,
            homeDirectory: homeDirectory
        )
    }

    private func makeManifest() -> ModelManifest {
        let modelData = "model-data".data(using: .utf8)!
        let configData = "config-data".data(using: .utf8)!
        let voicesData = "voices-data".data(using: .utf8)!

        return ModelManifest(
            name: "test-model",
            displayName: "Test Model",
            description: "Synthetic manifest for tests.",
            files: [
                FileEntry(
                    localPath: "model.bin",
                    remoteURL: URL(string: "https://example.com/model.bin")!,
                    sha256: Checksum.sha256Hex(for: modelData),
                    sizeBytes: Int64(modelData.count)
                ),
                FileEntry(
                    localPath: "config.json",
                    remoteURL: URL(string: "https://example.com/config.json")!,
                    sha256: Checksum.sha256Hex(for: configData),
                    sizeBytes: Int64(configData.count)
                ),
                FileEntry(
                    localPath: "voices.npz",
                    remoteURL: URL(string: "https://example.com/voices.npz")!,
                    sha256: Checksum.sha256Hex(for: voicesData),
                    sizeBytes: Int64(voicesData.count)
                ),
            ]
        )
    }

    private func stubPayloads() -> [URL: Result<Data, Error>] {
        let manifest = makeManifest()
        return Dictionary(uniqueKeysWithValues: manifest.files.map { file in
            (file.remoteURL, .success(fileData(for: file)))
        })
    }

    private func fileData(for file: FileEntry) -> Data {
        switch file.localPath {
        case "model.bin":
            return "model-data".data(using: .utf8)!
        case "config.json":
            return "config-data".data(using: .utf8)!
        default:
            return "voices-data".data(using: .utf8)!
        }
    }

    private func makeTemporaryHome() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private final class StubDownloader: FileDownloading, @unchecked Sendable {
    private(set) var downloadedURLs: [URL] = []
    private let payloads: [URL: Result<Data, Error>]

    init(payloads: [URL: Result<Data, Error>]) {
        self.payloads = payloads
    }

    func download(
        from remoteURL: URL,
        to destinationURL: URL,
        progress: @escaping @Sendable (DownloadProgress) -> Void
    ) async throws -> DownloadArtifact {
        downloadedURLs.append(remoteURL)

        guard let payload = payloads[remoteURL] else {
            throw URLError(.fileDoesNotExist)
        }

        let data = try payload.get()
        progress(DownloadProgress(bytesReceived: Int64(data.count / 2), totalBytesExpected: Int64(data.count)))
        try data.write(to: destinationURL)
        progress(DownloadProgress(bytesReceived: Int64(data.count), totalBytesExpected: Int64(data.count)))

        return DownloadArtifact(
            bytesWritten: Int64(data.count),
            sha256: Checksum.sha256Hex(for: data)
        )
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ handler: (Error) -> Void
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error to be thrown")
    } catch {
        handler(error)
    }
}
