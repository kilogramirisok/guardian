import Foundation

// Prevents system and display sleep by spawning `caffeinate`.
// Same effect as IOKit power assertions, but works in pure Swift
// without needing C bridging headers.

class KeepAwake {
    private var caffeinateProcess: Process?

    @discardableResult
    func activate() -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        proc.arguments = ["-d", "-i", "-s"]  // prevent display sleep, idle sleep, system sleep

        do {
            try proc.run()
            caffeinateProcess = proc
            return true
        } catch {
            return false
        }
    }

    func deactivate() {
        caffeinateProcess?.terminate()
        caffeinateProcess = nil
    }

    deinit {
        deactivate()
    }
}
