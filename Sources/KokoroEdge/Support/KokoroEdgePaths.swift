import Foundation

struct KokoroEdgePaths {
    let homeDirectory: URL

    init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory
    }

    var stateDirectory: URL {
        homeDirectory.appendingPathComponent(".kokoro-edge", isDirectory: true)
    }

    var modelsDirectory: URL {
        stateDirectory.appendingPathComponent("models", isDirectory: true)
    }

    var pidFile: URL {
        stateDirectory.appendingPathComponent("kokoro-edge.pid", isDirectory: false)
    }

    var logFile: URL {
        stateDirectory.appendingPathComponent("kokoro-edge.log", isDirectory: false)
    }

    func createStateDirectory(fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
    }
}
