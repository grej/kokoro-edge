import ArgumentParser
import Foundation

struct ServeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "serve",
        abstract: "Start the kokoro-edge daemon."
    )

    @Option(help: "Hostname or interface to bind.")
    var host = "localhost"

    @Option(help: "Port to listen on.")
    var port = 7777

    @Flag(name: [.short, .long], help: "Run in the background.")
    var daemon = false

    @Flag(name: [.short, .long], help: "Log requests to stderr.")
    var verbose = false

    @Flag(help: "Do not auto-download the default model if it is missing.")
    var skipDownload = false

    mutating func run() async throws {
        let host = self.host
        let port = self.port
        let paths = KokoroEdgePaths()
        try paths.createStateDirectory()
        try DaemonRuntime.ensureNoRunningDaemon(at: paths.pidFile)
        try PortProbe.requireAvailable(host: host, port: port)

        let modelName = "kokoro-82m"
        let modelManager = ModelManager(reporter: ConsoleModelDownloadReporter())
        if !modelManager.isAvailable(model: modelName) {
            guard !skipDownload else {
                throw ValidationError("Model not found. Run 'kokoro-edge serve' without --skip-download or 'kokoro-edge models pull \(modelName)' first.")
            }
            try Console.writeStdout("First run detected. Downloading \(modelName) model (~330MB)...\n")
            try await modelManager.pull(model: modelName)
        }

        if daemon {
            let executable = CommandLine.arguments[0]
            let daemonArguments = makeDaemonArguments(host: host, port: port, verbose: verbose)
            let pid = try DaemonRuntime.startDetachedProcess(
                executable: executable,
                arguments: daemonArguments,
                logFileURL: paths.logFile
            )
            try DaemonRuntime.writePID(pid, to: paths.pidFile)
            try Console.writeStdout("kokoro-edge started in background (pid \(pid)). Log: \(paths.logFile.path)\n")
            return
        }

        let service = try TTSService(modelName: modelName, modelManager: ModelManager())
        let logger = ServerVerboseLogger(enabled: verbose)
        let app = ServerAppFactory.makeApplication(
            service: service,
            host: host,
            port: port,
            verboseLogger: logger,
            onServerRunning: { boundPort in
                let status = await service.statusPayload()
                let banner = """
                kokoro-edge v\(KokoroEdgeVersion.current)
                Model: \(status.model) (loaded)
                Voices: \(status.voicesAvailable.count) available
                WebSocket: ws://\(host):\(boundPort)/ws
                HTTP API:  http://\(host):\(boundPort)/v1/
                Ready.

                """
                if let data = banner.data(using: .utf8) {
                    try? FileHandle.standardOutput.write(contentsOf: data)
                }
            }
        )
        defer {
            DaemonRuntime.removePIDFileIfOwned(paths.pidFile)
        }
        try await app.runService(gracefulShutdownSignals: [.sigterm, .sigint])
    }

    private func makeDaemonArguments(host: String, port: Int, verbose: Bool) -> [String] {
        var arguments = ["serve", "--host", host, "--port", String(port), "--skip-download"]
        if verbose {
            arguments.append("--verbose")
        }
        return arguments
    }
}
