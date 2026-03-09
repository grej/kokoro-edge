import Foundation

enum Console {
    static func writeStdout(_ string: String) throws {
        guard let data = string.data(using: .utf8) else { return }
        try FileHandle.standardOutput.write(contentsOf: data)
    }

    static func writeStderr(_ string: String) throws {
        guard let data = string.data(using: .utf8) else { return }
        try FileHandle.standardError.write(contentsOf: data)
    }
}
