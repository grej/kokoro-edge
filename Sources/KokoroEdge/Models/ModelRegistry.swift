import Foundation

struct FileEntry: Equatable, Sendable {
    let localPath: String
    let remoteURL: URL
    let sha256: String
    let sizeBytes: Int64

    var fileName: String {
        URL(fileURLWithPath: localPath).lastPathComponent
    }
}

struct ModelManifest: Equatable, Sendable {
    let name: String
    let displayName: String
    let description: String
    let files: [FileEntry]

    var totalBytes: Int64 {
        files.reduce(0) { $0 + $1.sizeBytes }
    }
}

struct ModelRegistry {
    let manifests: [String: ModelManifest]

    init(manifests: [ModelManifest]) {
        self.manifests = Dictionary(uniqueKeysWithValues: manifests.map { ($0.name, $0) })
    }

    var allModels: [ModelManifest] {
        manifests.values.sorted { $0.name < $1.name }
    }

    func manifest(named name: String) -> ModelManifest? {
        manifests[name]
    }
}

extension ModelRegistry {
    static let `default`: ModelRegistry = {
        let modelCommit = "a71e4d38b236d968966a2002c4c895dbd12b1c3c"
        let voicesCommit = "729e56de3b069953b58ac2389b9a27fbc52289cc"

        return ModelRegistry(manifests: [
            ModelManifest(
                name: "kokoro-82m",
                displayName: "Kokoro 82M BF16",
                description: "Pinned MLX Kokoro model bundle for Apple Silicon.",
                files: [
                    FileEntry(
                        localPath: "kokoro-v1_0.safetensors",
                        remoteURL: URL(string: "https://huggingface.co/mlx-community/Kokoro-82M-bf16/resolve/\(modelCommit)/kokoro-v1_0.safetensors")!,
                        sha256: "4e9ecdf03b8b6cf906070390237feda473dc13327cb8d56a43deaa374c02acd8",
                        sizeBytes: 327_115_152
                    ),
                    FileEntry(
                        localPath: "config.json",
                        remoteURL: URL(string: "https://huggingface.co/mlx-community/Kokoro-82M-bf16/resolve/\(modelCommit)/config.json")!,
                        sha256: "5abb01e2403b072bf03d04fde160443e209d7a0dad49a423be15196b9b43c17f",
                        sizeBytes: 2_351
                    ),
                    FileEntry(
                        localPath: "voices.npz",
                        remoteURL: URL(string: "https://raw.githubusercontent.com/mlalma/KokoroTestApp/\(voicesCommit)/Resources/voices.npz")!,
                        sha256: "56dbfa2f2970af2e395397020393d368c5f441d09b3de4e9b77f6222e790f10f",
                        sizeBytes: 14_629_684
                    ),
                ]
            ),
        ])
    }()
}
