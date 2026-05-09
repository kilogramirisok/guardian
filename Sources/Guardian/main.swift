import ArgumentParser
import Foundation

@main
struct Guardian: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "guardian",
        abstract: "Lock input, prevent sleep, keep agents running.",
        subcommands: [Lock.self, Wrap.self, Status.self],
        defaultSubcommand: nil
    )
}

struct Lock: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Lock all input devices and prevent sleep."
    )

    @Option(name: .shortAndLong, help: "Blur level for screen overlay (0-10).")
    var blur: Int = 5

    @Option(name: .shortAndLong, help: "Auto-unlock timeout (e.g. 30m, 2h).")
    var timeout: String = "8h"

    @Flag(name: .shortAndLong, help: "Show overlay with blur effect.")
    var screenBlur = false

    func run() throws {
        let daemon = GuardianDaemon()
        let seconds = try parseDuration(timeout)
        try daemon.lock(blur: screenBlur ? blur : 0, timeoutSeconds: seconds)
    }

    private func parseDuration(_ input: String) throws -> Int {
        let scanner = Scanner(string: input)
        guard let value = scanner.scanInt() else {
            throw ValidationError("Invalid timeout format: \(input). Use e.g. 30m, 2h.")
        }
        let remaining = String(input[scanner.currentIndex...]).lowercased()
        switch remaining {
        case "s", "": return value
        case "m": return value * 60
        case "h": return value * 3600
        default: throw ValidationError("Unknown time unit: \(remaining). Use s, m, or h.")
        }
    }
}

struct Wrap: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Lock input, run a command, auto-unlock when it exits."
    )

    @Argument(parsing: .remaining, help: "Command to run.")
    var command: [String]

    @Option(name: .shortAndLong, help: "Blur level for screen overlay (0-10).")
    var blur: Int = 0

    func run() throws {
        guard !command.isEmpty else {
            throw ValidationError("No command provided. Usage: guardian wrap -- <command>")
        }
        let daemon = GuardianDaemon()
        try daemon.wrap(command: command, blur: blur)
    }
}

struct Status: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Query guardian daemon status."
    )

    func run() throws {
        let daemon = GuardianDaemon()
        try daemon.status()
    }
}
