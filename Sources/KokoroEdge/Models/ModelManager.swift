import Foundation

struct ModelStatus: Equatable, Sendable {
    let modelName: String
    let isAvailable: Bool
    let downloadedBytes: Int64
    let totalBytes: Int64
}

struct DownloadProgress: Sendable {
    let bytesReceived: Int64
    let totalBytesExpected: Int64?
}

struct DownloadArtifact: Sendable {
    let bytesWritten: Int64
    let sha256: String
}

protocol FileDownloading {
    func download(
        from remoteURL: URL,
        to destinationURL: URL,
        progress: @escaping @Sendable (DownloadProgress) -> Void
    ) async throws -> DownloadArtifact
}

protocol ModelDownloadReporting: Sendable {
    func didStart(file: FileEntry)
    func didUpdate(file: FileEntry, bytesReceived: Int64, totalBytesExpected: Int64?)
    func didSkip(file: FileEntry)
    func didFinish(file: FileEntry)
    func didFinishModel(manifest: ModelManifest, bytesDownloaded: Int64, modelDirectory: URL)
}

struct NullModelDownloadReporter: ModelDownloadReporting {
    func didStart(file: FileEntry) {}
    func didUpdate(file: FileEntry, bytesReceived: Int64, totalBytesExpected: Int64?) {}
    func didSkip(file: FileEntry) {}
    func didFinish(file: FileEntry) {}
    func didFinishModel(manifest: ModelManifest, bytesDownloaded: Int64, modelDirectory: URL) {}
}

enum ModelManagerError: LocalizedError, Equatable {
    case unknownModel(String)
    case checksumMismatch(file: String, expected: String, actual: String)
    case fileSizeMismatch(file: String, expected: Int64, actual: Int64)

    var errorDescription: String? {
        switch self {
        case .unknownModel(let name):
            return "Unknown model '\(name)'."
        case .checksumMismatch(let file, let expected, let actual):
            return "Checksum mismatch for \(file). Expected \(expected), got \(actual)."
        case .fileSizeMismatch(let file, let expected, let actual):
            return "Unexpected size for \(file). Expected \(expected) bytes, got \(actual) bytes."
        }
    }
}

final class ModelManager {
    private let registry: ModelRegistry
    private let fileManager: FileManager
    private let downloader: any FileDownloading
    private let reporter: any ModelDownloadReporting
    private let homeDirectory: URL

    init(
        registry: ModelRegistry = .default,
        fileManager: FileManager = .default,
        downloader: any FileDownloading = URLSessionFileDownloader(),
        reporter: any ModelDownloadReporting = NullModelDownloadReporter(),
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.registry = registry
        self.fileManager = fileManager
        self.downloader = downloader
        self.reporter = reporter
        self.homeDirectory = homeDirectory
    }

    var modelsDirectory: URL {
        homeDirectory
            .appendingPathComponent(".kokoro-edge", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
    }

    func modelPath(for name: String) throws -> URL {
        guard registry.manifest(named: name) != nil else {
            throw ModelManagerError.unknownModel(name)
        }

        return modelsDirectory.appendingPathComponent(name, isDirectory: true)
    }

    func isAvailable(model name: String) -> Bool {
        (try? status(for: name).isAvailable) ?? false
    }

    func status(for name: String) throws -> ModelStatus {
        let manifest = try manifest(named: name)
        let modelDirectory = try modelPath(for: name)

        var downloadedBytes: Int64 = 0
        var allFilesValid = true

        for file in manifest.files {
            let destinationURL = modelDirectory.appendingPathComponent(file.localPath, isDirectory: false)
            guard fileManager.fileExists(atPath: destinationURL.path) else {
                allFilesValid = false
                continue
            }

            if try isValid(file: file, at: destinationURL) {
                downloadedBytes += file.sizeBytes
            } else {
                allFilesValid = false
            }
        }

        return ModelStatus(
            modelName: manifest.name,
            isAvailable: allFilesValid,
            downloadedBytes: downloadedBytes,
            totalBytes: manifest.totalBytes
        )
    }

    func pull(model name: String) async throws {
        let manifest = try manifest(named: name)
        let modelDirectory = try modelPath(for: name)

        try fileManager.createDirectory(at: modelDirectory, withIntermediateDirectories: true)

        var bytesDownloadedThisRun: Int64 = 0

        for file in manifest.files {
            let destinationURL = modelDirectory.appendingPathComponent(file.localPath, isDirectory: false)
            let parentDirectory = destinationURL.deletingLastPathComponent()

            try fileManager.createDirectory(at: parentDirectory, withIntermediateDirectories: true)

            if fileManager.fileExists(atPath: destinationURL.path), try isValid(file: file, at: destinationURL) {
                reporter.didSkip(file: file)
                continue
            }

            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }

            let partialURL = destinationURL.appendingPathExtension("part")
            if fileManager.fileExists(atPath: partialURL.path) {
                try fileManager.removeItem(at: partialURL)
            }

            reporter.didStart(file: file)
            let artifact = try await downloader.download(from: file.remoteURL, to: partialURL) { [reporter] progress in
                reporter.didUpdate(
                    file: file,
                    bytesReceived: progress.bytesReceived,
                    totalBytesExpected: progress.totalBytesExpected ?? file.sizeBytes
                )
            }

            let actualChecksum = artifact.sha256.lowercased()
            let expectedChecksum = file.sha256.lowercased()
            guard actualChecksum == expectedChecksum else {
                try? fileManager.removeItem(at: partialURL)
                throw ModelManagerError.checksumMismatch(
                    file: file.localPath,
                    expected: expectedChecksum,
                    actual: actualChecksum
                )
            }

            guard artifact.bytesWritten == file.sizeBytes else {
                try? fileManager.removeItem(at: partialURL)
                throw ModelManagerError.fileSizeMismatch(
                    file: file.localPath,
                    expected: file.sizeBytes,
                    actual: artifact.bytesWritten
                )
            }

            try fileManager.moveItem(at: partialURL, to: destinationURL)
            reporter.didFinish(file: file)
            bytesDownloadedThisRun += artifact.bytesWritten
        }

        reporter.didFinishModel(
            manifest: manifest,
            bytesDownloaded: bytesDownloadedThisRun,
            modelDirectory: modelDirectory
        )
    }

    private func manifest(named name: String) throws -> ModelManifest {
        guard let manifest = registry.manifest(named: name) else {
            throw ModelManagerError.unknownModel(name)
        }

        return manifest
    }

    private func isValid(file: FileEntry, at fileURL: URL) throws -> Bool {
        let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
        let byteSize = (attributes[.size] as? NSNumber)?.int64Value ?? -1
        guard byteSize == file.sizeBytes else {
            return false
        }

        return try Checksum.sha256Hex(forFileAt: fileURL).lowercased() == file.sha256.lowercased()
    }
}

final class ConsoleModelDownloadReporter: ModelDownloadReporting, @unchecked Sendable {
    private let output = FileHandle.standardOutput
    private let byteFormatter: ByteCountFormatter
    private var activeProgressFile: String?
    private var lastRenderedPercent: Int?

    init() {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        self.byteFormatter = formatter
    }

    func didStart(file: FileEntry) {
        lastRenderedPercent = nil
        writeLine("Downloading \(file.localPath)...")
    }

    func didUpdate(file: FileEntry, bytesReceived: Int64, totalBytesExpected: Int64?) {
        let totalBytes = totalBytesExpected ?? 0
        let formattedReceived = byteFormatter.string(fromByteCount: bytesReceived)
        let formattedTotal = totalBytes > 0 ? byteFormatter.string(fromByteCount: totalBytes) : "unknown"
        let percentValue: Int?
        let percent: String

        if totalBytes > 0 {
            let value = (Double(bytesReceived) / Double(totalBytes)) * 100
            let rounded = Int(min(max(value.rounded(), 0), 100))
            percentValue = rounded
            percent = "\(rounded)%"
        } else {
            percentValue = nil
            percent = "--"
        }

        if bytesReceived > 0, bytesReceived < totalBytes, percentValue == lastRenderedPercent {
            return
        }

        activeProgressFile = file.localPath
        lastRenderedPercent = percentValue
        write("\rDownloading \(file.localPath)... \(formattedReceived)/\(formattedTotal) (\(percent))")
    }

    func didSkip(file: FileEntry) {
        endProgressIfNeeded(for: file)
        writeLine("Skipping \(file.localPath) (already verified).")
    }

    func didFinish(file: FileEntry) {
        endProgressIfNeeded(for: file)
        writeLine("Finished \(file.localPath).")
    }

    func didFinishModel(manifest: ModelManifest, bytesDownloaded: Int64, modelDirectory: URL) {
        if let file = activeProgressFile {
            endProgressIfNeeded(for: FileEntry(localPath: file, remoteURL: modelDirectory, sha256: "", sizeBytes: 0))
        }

        let formattedBytes = byteFormatter.string(fromByteCount: bytesDownloaded)
        writeLine("Model ready: \(manifest.name) (\(formattedBytes) downloaded) at \(modelDirectory.path)")
    }

    private func endProgressIfNeeded(for file: FileEntry) {
        guard activeProgressFile == file.localPath else {
            return
        }

        writeLine("")
        activeProgressFile = nil
        lastRenderedPercent = nil
    }

    private func write(_ string: String) {
        guard let data = string.data(using: .utf8) else {
            return
        }

        try? output.write(contentsOf: data)
    }

    private func writeLine(_ string: String) {
        write(string + "\n")
    }
}
