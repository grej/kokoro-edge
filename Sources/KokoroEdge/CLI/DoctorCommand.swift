import ArgumentParser
import Foundation
import Metal

struct DoctorCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Run environment and runtime diagnostics."
    )

    @Option(help: "Daemon host.")
    var host = "localhost"

    @Option(help: "Daemon port.")
    var port = 7777

    mutating func run() async throws {
        let report = await DoctorReport.build(host: host, port: port)
        try Console.writeStdout(report.rendered)
        if !report.allPassed {
            throw ExitCode(1)
        }
    }
}

private struct DoctorCheck {
    let name: String
    let passed: Bool
    let detail: String

    var rendered: String {
        "[\(passed ? "PASS" : "FAIL")] \(name): \(detail)"
    }
}

private struct DoctorReport {
    let checks: [DoctorCheck]

    var allPassed: Bool {
        checks.allSatisfy(\.passed)
    }

    var rendered: String {
        checks.map(\.rendered).joined(separator: "\n") + "\n"
    }

    static func build(host: String, port: Int) async -> DoctorReport {
        let paths = KokoroEdgePaths()
        let modelManager = ModelManager()
        let daemonStatus = await fetchStatus(host: host, port: port)

        var checks: [DoctorCheck] = []
        checks.append(
            DoctorCheck(
                name: "macOS",
                passed: true,
                detail: ProcessInfo.processInfo.operatingSystemVersionString
            )
        )
        checks.append(
            DoctorCheck(
                name: "Apple Silicon",
                passed: isAppleSilicon,
                detail: isAppleSilicon ? "arm64 detected" : "arm64 is required"
            )
        )
        checks.append(versionCheck(command: "/usr/bin/swift", args: ["--version"], name: "Swift"))
        checks.append(versionCheck(command: "/usr/bin/xcodebuild", args: ["-version"], name: "Xcode"))

        if let status = try? modelManager.status(for: "kokoro-82m") {
            let detail = status.isAvailable
                ? "kokoro-82m available (\(status.downloadedBytes)/\(status.totalBytes) bytes)"
                : "kokoro-82m missing or incomplete (\(status.downloadedBytes)/\(status.totalBytes) bytes)"
            checks.append(DoctorCheck(name: "Model bundle", passed: status.isAvailable, detail: detail))
        } else {
            checks.append(DoctorCheck(name: "Model bundle", passed: false, detail: "Unable to inspect model cache."))
        }

        if let payload = daemonStatus {
            checks.append(
                DoctorCheck(
                    name: "Daemon",
                    passed: true,
                    detail: "running at http://\(host):\(port) (uptime: \(payload.uptimeSeconds)s)"
                )
            )
            checks.append(
                DoctorCheck(
                    name: "Port \(port)",
                    passed: true,
                    detail: "reachable on \(host)"
                )
            )
        } else {
            checks.append(DoctorCheck(name: "Daemon", passed: false, detail: "not running"))
            checks.append(
                DoctorCheck(
                    name: "Port \(port)",
                    passed: PortProbe.isAvailable(host: host, port: port),
                    detail: PortProbe.isAvailable(host: host, port: port)
                        ? "available on \(host)"
                        : "already in use on \(host)"
                )
            )
        }

        let metalDevice = MTLCreateSystemDefaultDevice()
        checks.append(
            DoctorCheck(
                name: "Metal GPU",
                passed: metalDevice != nil,
                detail: metalDevice?.name ?? "No Metal device available"
            )
        )
        checks.append(
            DoctorCheck(
                name: "Runtime paths",
                passed: FileManager.default.fileExists(atPath: paths.stateDirectory.path),
                detail: paths.stateDirectory.path
            )
        )

        return DoctorReport(checks: checks)
    }

    private static func fetchStatus(host: String, port: Int) async -> HTTPStatusPayload? {
        let url = URL(string: "http://\(host):\(port)/v1/status")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.0

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }
            return try JSONDecoder().decode(HTTPStatusPayload.self, from: data)
        } catch {
            return nil
        }
    }

    private static var isAppleSilicon: Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = sysctlbyname("hw.optional.arm64", &value, &size, nil, 0)
        return result == 0 && value == 1
    }

    private static func versionCheck(command: String, args: [String], name: String) -> DoctorCheck {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = args
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
            let output = (String(data: data, encoding: .utf8) ?? String(data: errorData, encoding: .utf8) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n", with: " | ")

            return DoctorCheck(
                name: name,
                passed: process.terminationStatus == 0,
                detail: output.isEmpty ? "No output" : output
            )
        } catch {
            return DoctorCheck(name: name, passed: false, detail: error.localizedDescription)
        }
    }
}
