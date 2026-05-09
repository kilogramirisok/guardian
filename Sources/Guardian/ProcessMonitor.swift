import Foundation

// Monitors a child process for exit.
// Used by `guardian wrap` to auto-unlock when the wrapped command finishes.
// Thread-safe via NSLock for Swift 6 Sendable compliance.

final class ProcessMonitor: @unchecked Sendable {
    private let lock = NSLock()
    private var _process: Process?
    private var _stdoutPipe: Pipe?
    private var _stderrPipe: Pipe?
    private var process: Process? {
        get { lock.withLock { _process } }
        set { lock.withLock { _process = newValue } }
    }

    var onOutput: (@Sendable (String) -> Void)?
    var onExit: (@Sendable (Int32) -> Void)?

    func launch(command: [String]) throws -> pid_t {
        let proc = Process()
        process = proc

        if command.count > 1 {
            proc.executableURL = URL(fileURLWithPath: command[0])
            proc.arguments = Array(command[1...])
        } else if command.count == 1 {
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            proc.arguments = command
        }

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        lock.withLock {
            _stdoutPipe = outPipe
            _stderrPipe = errPipe
        }

        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty, let output = String(data: data, encoding: .utf8) {
                self.onOutput?(output)
            }
        }

        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty, let output = String(data: data, encoding: .utf8) {
                self.onOutput?(output)
            }
        }

        try proc.run()

        let pid = proc.processIdentifier

        DispatchQueue.global(qos: .utility).async {
            proc.waitUntilExit()
            let exitCode = proc.terminationStatus

            // Break retain cycle: clear handlers so Pipe → FileHandle → closure → self is released
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil

            self.onExit?(exitCode)
        }

        return pid
    }

    func terminate() {
        // Clear handlers before terminating to break retain cycle
        lock.withLock {
            _stdoutPipe?.fileHandleForReading.readabilityHandler = nil
            _stderrPipe?.fileHandleForReading.readabilityHandler = nil
            _stdoutPipe = nil
            _stderrPipe = nil
        }
        process?.terminate()
    }

    var isRunning: Bool {
        return process?.isRunning ?? false
    }
}
