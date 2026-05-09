import Foundation

// Monitors a child process PID for exit.
// Used by `guardian wrap` to auto-unlock when the wrapped command finishes.

class ProcessMonitor {
    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    var onOutput: ((String) -> Void)?
    var onExit: ((Int32) -> Void)?

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
        stdoutPipe = outPipe
        stderrPipe = errPipe

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty, let output = String(data: data, encoding: .utf8) {
                self?.onOutput?(output)
            }
        }

        errPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty, let output = String(data: data, encoding: .utf8) {
                self?.onOutput?(output)
            }
        }

        try proc.run()

        DispatchQueue.global(qos: .utility).async { [weak self] in
            proc.waitUntilExit()
            let exitCode = proc.terminationStatus
            DispatchQueue.main.async {
                self?.onExit?(exitCode)
            }
        }

        return proc.processIdentifier
    }

    func terminate() {
        process?.terminate()
    }

    var isRunning: Bool {
        return process?.isRunning ?? false
    }

    var pid: pid_t? {
        return process?.processIdentifier
    }
}
