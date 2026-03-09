import ArgumentParser
import Foundation

@available(macOS 10.15, *)
public struct KokoroEdgeCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "kokoro-edge",
        abstract: "Local voice engine daemon for Apple Silicon.",
        version: KokoroEdgeVersion.current,
        subcommands: [
            ServeCommand.self,
            TTSCommand.self,
            ModelsCommand.self,
            StatusCommand.self,
            StopCommand.self,
            DoctorCommand.self,
        ],
    )

    public init() {}

    public static let welcomeMessage = """
    kokoro-edge - local voice engine for Apple Silicon

    Quick start:
      kokoro-edge serve          Start the daemon
      kokoro-edge tts "Hello"    One-shot synthesis
      kokoro-edge status         Check if running

    Run 'kokoro-edge --help' for all commands.
    """

    public mutating func run() async throws {
        try Console.writeStdout(Self.welcomeMessage + "\n")
    }
}
