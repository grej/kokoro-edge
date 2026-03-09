import CryptoKit
import Foundation

final class URLSessionFileDownloader: NSObject, FileDownloading, @unchecked Sendable {
    func download(
        from remoteURL: URL,
        to destinationURL: URL,
        progress: @escaping @Sendable (DownloadProgress) -> Void
    ) async throws -> DownloadArtifact {
        let delegate = StreamingDownloadDelegate(destinationURL: destinationURL, progress: progress)
        return try await delegate.download(from: remoteURL)
    }
}

private final class StreamingDownloadDelegate: NSObject, URLSessionDataDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    private let destinationURL: URL
    private let progressHandler: @Sendable (DownloadProgress) -> Void

    private var continuation: CheckedContinuation<DownloadArtifact, Error>?
    private var session: URLSession?
    private var fileHandle: FileHandle?
    private var hasher = SHA256()
    private var bytesReceived: Int64 = 0
    private var expectedBytes: Int64?
    private var finished = false

    init(destinationURL: URL, progress: @escaping @Sendable (DownloadProgress) -> Void) {
        self.destinationURL = destinationURL
        self.progressHandler = progress
    }

    func download(from remoteURL: URL) async throws -> DownloadArtifact {
        try? FileManager.default.removeItem(at: destinationURL)
        FileManager.default.createFile(atPath: destinationURL.path, contents: nil)
        fileHandle = try FileHandle(forWritingTo: destinationURL)

        let configuration = URLSessionConfiguration.ephemeral
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let task = session.dataTask(with: remoteURL)
            task.resume()
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !finished else {
            return
        }

        do {
            try fileHandle?.write(contentsOf: data)
            hasher.update(data: data)
            bytesReceived += Int64(data.count)
            progressHandler(DownloadProgress(bytesReceived: bytesReceived, totalBytesExpected: expectedBytes))
        } catch {
            finish(with: .failure(error))
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse) async -> URLSession.ResponseDisposition {
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            finish(with: .failure(URLError(.badServerResponse)))
            return .cancel
        }

        if response.expectedContentLength > 0 {
            expectedBytes = response.expectedContentLength
        }

        progressHandler(DownloadProgress(bytesReceived: bytesReceived, totalBytesExpected: expectedBytes))
        return .allow
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            finish(with: .failure(error))
            return
        }

        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        finish(with: .success(DownloadArtifact(bytesWritten: bytesReceived, sha256: digest)))
    }

    private func finish(with result: Result<DownloadArtifact, Error>) {
        guard !finished else {
            return
        }

        finished = true
        try? fileHandle?.close()
        fileHandle = nil
        session?.finishTasksAndInvalidate()
        session = nil

        switch result {
        case .success(let artifact):
            continuation?.resume(returning: artifact)
        case .failure(let error):
            continuation?.resume(throwing: error)
        }

        continuation = nil
    }
}
