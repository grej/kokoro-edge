import ArgumentParser
import Foundation

struct ModelsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "models",
        abstract: "Manage Kokoro model assets.",
        subcommands: [
            ModelsListCommand.self,
            ModelsPullCommand.self,
            ModelsRemoveCommand.self,
        ]
    )
}

struct ModelsListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List known models and download status."
    )

    mutating func run() async throws {
        let manager = ModelManager()
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file

        for manifest in ModelRegistry.default.allModels {
            let status = try manager.status(for: manifest.name)
            let stateLabel = status.isAvailable ? "downloaded" : "not downloaded"
            let bytesSummary = "\(status.downloadedBytes) / \(status.totalBytes) bytes"
            let readableSummary = "\(formatter.string(fromByteCount: status.downloadedBytes)) / \(formatter.string(fromByteCount: status.totalBytes))"
            let modelPath = try manager.modelPath(for: manifest.name).path

            print("\(manifest.name): \(stateLabel)")
            print("  \(bytesSummary) (\(readableSummary))")
            print("  \(modelPath)")
        }
    }
}

struct ModelsPullCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pull",
        abstract: "Download a model and its voice assets."
    )

    @Argument(help: "Model name to download.")
    var modelName: String

    mutating func run() async throws {
        let manager = ModelManager(reporter: ConsoleModelDownloadReporter())
        try await manager.pull(model: modelName)
    }
}

struct ModelsRemoveCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "remove",
        abstract: "Remove a downloaded model."
    )

    @Argument(help: "Model name to remove.")
    var modelName: String

    mutating func run() throws {
        print("models remove: not implemented yet")
    }
}
