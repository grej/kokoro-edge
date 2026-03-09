import ArgumentParser
import Foundation

struct StatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Check daemon status."
    )

    @Option(help: "Daemon host.")
    var host = "localhost"

    @Option(help: "Daemon port.")
    var port = 7777

    mutating func run() async throws {
        let url = URL(string: "http://\(host):\(port)/v1/status")!
        let request = URLRequest(url: url)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ValidationError("Unexpected response from kokoro-edge.")
            }

            guard httpResponse.statusCode == 200 else {
                let message = String(data: data, encoding: .utf8) ?? "status \(httpResponse.statusCode)"
                throw ValidationError("Failed to query kokoro-edge status: \(message)")
            }

            let payload = try JSONDecoder().decode(HTTPStatusPayload.self, from: data)
            try Console.writeStdout(Self.renderStatus(payload, host: host, port: port) + "\n")
        } catch let error as DecodingError {
            throw ValidationError("Failed to decode kokoro-edge status: \(error.localizedDescription)")
        } catch let error as URLError where error.code == .cannotConnectToHost || error.code == .timedOut || error.code == .networkConnectionLost || error.code == .cannotFindHost {
            try? Console.writeStdout("kokoro-edge is not running\n")
            throw ExitCode(1)
        } catch let error as ValidationError {
            throw error
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSPOSIXErrorDomain {
                let code = POSIXErrorCode(rawValue: Int32(nsError.code))
                if code == .ECONNREFUSED || code == .ETIMEDOUT || code == .EHOSTUNREACH {
                    try? Console.writeStdout("kokoro-edge is not running\n")
                    throw ExitCode(1)
                }
            }
            throw error
        }
    }

    static func renderStatus(_ payload: HTTPStatusPayload, host: String, port: Int) -> String {
        "kokoro-edge v\(payload.version) is running at http://\(host):\(port) (model: \(payload.model), voices: \(payload.voicesAvailable.count), uptime: \(payload.uptimeSeconds)s)"
    }
}
