import ArgumentParser
import Foundation

struct StopCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stop",
        abstract: "Stop a running daemon."
    )

    mutating func run() throws {
        let pid = try DaemonRuntime.stopDaemon(at: KokoroEdgePaths().pidFile)
        try Console.writeStdout("Stopped kokoro-edge (pid \(pid)).\n")
    }
}
