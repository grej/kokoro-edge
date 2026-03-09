import Foundation
import Darwin

enum DaemonRuntimeError: LocalizedError {
    case unableToReadPIDFile
    case daemonNotRunning
    case daemonAlreadyRunning(pid: pid_t)
    case portInUse(host: String, port: Int)
    case spawnFailed(String)
    case shutdownTimedOut(pid: pid_t)

    var errorDescription: String? {
        switch self {
        case .unableToReadPIDFile:
            return "Unable to read daemon PID file."
        case .daemonNotRunning:
            return "kokoro-edge is not running."
        case .daemonAlreadyRunning(let pid):
            return "kokoro-edge is already running (pid \(pid))."
        case .portInUse(let host, let port):
            return "Port \(port) on \(host) is already in use."
        case .spawnFailed(let message):
            return "Failed to start daemon: \(message)"
        case .shutdownTimedOut(let pid):
            return "Timed out waiting for kokoro-edge (pid \(pid)) to stop."
        }
    }
}

enum DaemonRuntime {
    static func readPID(from fileURL: URL) throws -> pid_t {
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pid = pid_t(contents) else {
            throw DaemonRuntimeError.unableToReadPIDFile
        }
        return pid
    }

    static func writePID(_ pid: pid_t, to fileURL: URL) throws {
        try "\(pid)\n".write(to: fileURL, atomically: true, encoding: .utf8)
    }

    static func removePIDFileIfOwned(_ fileURL: URL, currentPID: pid_t = getpid()) {
        guard let pid = try? readPID(from: fileURL), pid == currentPID else {
            return
        }
        try? FileManager.default.removeItem(at: fileURL)
    }

    static func isProcessAlive(_ pid: pid_t) -> Bool {
        if kill(pid, 0) == 0 {
            return true
        }
        return errno == EPERM
    }

    static func removeStalePIDFileIfNeeded(at fileURL: URL) {
        guard let pid = try? readPID(from: fileURL) else {
            try? FileManager.default.removeItem(at: fileURL)
            return
        }
        if !isProcessAlive(pid) {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    static func ensureNoRunningDaemon(at pidFileURL: URL) throws {
        guard FileManager.default.fileExists(atPath: pidFileURL.path) else {
            return
        }

        removeStalePIDFileIfNeeded(at: pidFileURL)
        guard FileManager.default.fileExists(atPath: pidFileURL.path) else {
            return
        }

        let pid = try readPID(from: pidFileURL)
        if pid == getpid() {
            return
        }
        guard !isProcessAlive(pid) else {
            throw DaemonRuntimeError.daemonAlreadyRunning(pid: pid)
        }
        try? FileManager.default.removeItem(at: pidFileURL)
    }

    static func stopDaemon(at pidFileURL: URL, timeout: TimeInterval = 5.0) throws -> pid_t {
        removeStalePIDFileIfNeeded(at: pidFileURL)
        guard FileManager.default.fileExists(atPath: pidFileURL.path) else {
            throw DaemonRuntimeError.daemonNotRunning
        }

        let pid = try readPID(from: pidFileURL)
        guard isProcessAlive(pid) else {
            try? FileManager.default.removeItem(at: pidFileURL)
            throw DaemonRuntimeError.daemonNotRunning
        }

        guard kill(pid, SIGTERM) == 0 else {
            let posixError = POSIXErrorCode(rawValue: errno)
            if posixError == .ESRCH {
                try? FileManager.default.removeItem(at: pidFileURL)
                throw DaemonRuntimeError.daemonNotRunning
            }
            throw POSIXError(posixError ?? .EPERM)
        }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !isProcessAlive(pid) {
                try? FileManager.default.removeItem(at: pidFileURL)
                return pid
            }
            usleep(100_000)
        }

        throw DaemonRuntimeError.shutdownTimedOut(pid: pid)
    }

    static func startDetachedProcess(
        executable: String,
        arguments: [String],
        logFileURL: URL
    ) throws -> pid_t {
        let process = Process()
        let nullInput = FileHandle(forReadingAtPath: "/dev/null")
        let logHandle = try FileHandle(forWritingTo: ensureLogFile(at: logFileURL))

        try logHandle.seekToEnd()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = nullInput
        process.standardOutput = logHandle
        process.standardError = logHandle

        do {
            try process.run()
        } catch {
            throw DaemonRuntimeError.spawnFailed(error.localizedDescription)
        }

        return process.processIdentifier
    }

    private static func ensureLogFile(at fileURL: URL) throws -> URL {
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: Data())
        }
        return fileURL
    }
}

enum PortProbe {
    static func isAvailable(host: String, port: Int) -> Bool {
        let portString = String(port)
        let hostnames = host == "localhost" ? ["127.0.0.1", "::1"] : [host]

        for hostname in hostnames {
            if !canBind(host: hostname, port: portString) {
                return false
            }
        }

        return true
    }

    static func requireAvailable(host: String, port: Int) throws {
        guard isAvailable(host: host, port: port) else {
            throw DaemonRuntimeError.portInUse(host: host, port: port)
        }
    }

    private static func canBind(host: String, port: String) -> Bool {
        var hints = addrinfo(
            ai_flags: AI_PASSIVE,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: IPPROTO_TCP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )

        var addressInfo: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, port, &hints, &addressInfo) == 0, let firstInfo = addressInfo else {
            return false
        }
        defer { freeaddrinfo(addressInfo) }

        var pointer: UnsafeMutablePointer<addrinfo>? = firstInfo
        while let info = pointer {
            let fileDescriptor = socket(info.pointee.ai_family, info.pointee.ai_socktype, info.pointee.ai_protocol)
            if fileDescriptor >= 0 {
                defer { close(fileDescriptor) }
                var reuse: Int32 = 1
                setsockopt(fileDescriptor, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
                if bind(fileDescriptor, info.pointee.ai_addr, info.pointee.ai_addrlen) == 0 {
                    return true
                }
            }
            pointer = info.pointee.ai_next
        }

        return false
    }
}
