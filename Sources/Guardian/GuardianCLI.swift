import ArgumentParser
import Foundation

@main
struct GuardianCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "guardian",
        abstract: "Lock input, prevent sleep, keep agents running.",
        subcommands: [LockCommand.self, WrapCommand.self, StatusCommand.self],
        defaultSubcommand: nil
    )
}

struct LockCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "lock",
        abstract: "Lock all input devices and prevent sleep."
    )

    @Option(name: .shortAndLong, help: "Blur level for screen overlay (0-10).")
    var blur: Int = 5

    @Option(name: .shortAndLong, help: "Auto-unlock timeout (e.g. 30m, 2h). Max 24h.")
    var timeout: String = "8h"

    @Flag(name: .shortAndLong, help: "Show overlay with blur effect.")
    var screenBlur = false

    func run() async throws {
        let daemon = await GuardianDaemon()
        let seconds = try GuardianCLI.parseDuration(timeout)
        try await daemon.lock(blur: screenBlur ? blur : 0, timeoutSeconds: seconds)
    }
}

struct WrapCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "wrap",
        abstract: "Lock input, run a command, auto-unlock when it exits."
    )

    @Argument(parsing: .remaining, help: "Command to run.")
    var command: [String]

    @Option(name: .shortAndLong, help: "Blur level for screen overlay (0-10).")
    var blur: Int = 0

    func run() async throws {
        guard !command.isEmpty else {
            throw ValidationError("No command provided. Usage: guardian wrap -- <command>")
        }
        let daemon = await GuardianDaemon()
        try await daemon.wrap(command: command, blur: blur)
    }
}

struct StatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Query guardian daemon status."
    )

    func run() async throws {
        let daemon = await GuardianDaemon()
        try await daemon.status()
    }
}

// MARK: - Shared Utilities

extension GuardianCLI {
    static func parseDuration(_ input: String) throws -> Int {
        let scanner = Scanner(string: input)
        guard let value = scanner.scanInt() else {
            throw ValidationError("Invalid timeout format: \(input). Use e.g. 30m, 2h.")
        }
        guard value > 0 else {
            throw ValidationError("Timeout must be positive, got: \(input)")
        }
        let maxSeconds = 86400 // 24h
        let remaining = String(input[scanner.currentIndex...]).lowercased()
        let seconds: Int
        switch remaining {
        case "s", "": seconds = value
        case "m": seconds = value * 60
        case "h": seconds = value * 3600
        default: throw ValidationError("Unknown time unit: \(remaining). Use s, m, or h.")
        }
        guard seconds <= maxSeconds else {
            throw ValidationError("Timeout exceeds maximum of 24h")
        }
        return seconds
    }

    static func formatDuration(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = Int(interval) % 3600 / 60
        let seconds = Int(interval) % 60
        if hours > 0 {
            return String(format: "%dh %dm %ds", hours, minutes, seconds)
        } else if minutes > 0 {
            return String(format: "%dm %ds", minutes, seconds)
        } else {
            return String(format: "%ds", seconds)
        }
    }
}
