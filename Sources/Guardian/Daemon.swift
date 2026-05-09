import Foundation

// Main daemon that coordinates input locking, keep-awake, overlay, and unlock.
// @MainActor because it owns Overlay (@MainActor) and runs on the main thread.

@MainActor
class GuardianDaemon {
    private let inputLock = InputLock()
    private let keepAwake = KeepAwake()
    private let overlay = Overlay()
    private let unlockManager = UnlockManager()
    private var processMonitor: ProcessMonitor?
    private var startTime: Date?
    private var timer: Timer?

    // MARK: - Lock

    func lock(blur: Int, timeoutSeconds: Int) throws {
        guard InputLock.isAccessibilityGranted() else {
            print("❌ Accessibility permission not granted.")
            print("   Open System Settings → Privacy & Security → Accessibility")
            print("   Add Terminal (or your terminal app) to the list.")
            InputLock.promptAccessibility()
            return
        }

        print("🔒 Locking input...")
        startTime = Date()

        do {
            try inputLock.activate()
        } catch {
            print("❌ Failed to activate input lock: \(error)")
            return
        }

        if keepAwake.activate() {
            print("☕ Sleep prevention active")
        } else {
            print("⚠️  Could not prevent sleep (running on battery?)")
        }

        overlay.show(blurLevel: blur)

        inputLock.onUnlockShortcut = { [weak self] in
            Task { @MainActor in
                self?.requestUnlock()
            }
        }

        unlockManager.onUnlock = { [weak self] in
            Task { @MainActor in
                self?.unlock()
            }
        }

        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(timeoutSeconds), repeats: false) { [weak self] _ in
            print("⏰ Timeout reached, auto-unlocking...")
            Task { @MainActor in
                self?.unlock()
            }
        }

        print("🔒 Input locked. Press ⌘⇧L to unlock.")
        print("   Timeout: \(timeoutSeconds)s")

        CFRunLoopRun()
    }

    // MARK: - Wrap

    func wrap(command: [String], blur: Int) throws {
        guard InputLock.isAccessibilityGranted() else {
            print("❌ Accessibility permission not granted.")
            print("   Open System Settings → Privacy & Security → Accessibility")
            InputLock.promptAccessibility()
            return
        }

        print("🔒 Locking input for: \(command.joined(separator: " "))")
        startTime = Date()

        do {
            try inputLock.activate()
        } catch {
            print("❌ Failed to activate input lock: \(error)")
            return
        }

        keepAwake.activate()
        overlay.show(message: "🔒 Running: \(command.last ?? "command")", blurLevel: blur)

        inputLock.onUnlockShortcut = { [weak self] in
            Task { @MainActor in
                self?.requestUnlock()
            }
        }

        unlockManager.onUnlock = { [weak self] in
            Task { @MainActor in
                self?.unlock()
            }
        }

        let monitor = ProcessMonitor()
        processMonitor = monitor

        monitor.onOutput = { output in
            print(output, terminator: "")
        }

        monitor.onExit = { [weak self] exitCode in
            print("\n✅ Command exited with code \(exitCode)")
            Task { @MainActor in
                self?.overlay.update(message: "Done (exit \(exitCode))")
                try? await Task.sleep(for: .seconds(2))
                self?.unlock()
            }
        }

        do {
            let pid = try monitor.launch(command: command)
            print("🚀 Process started (PID: \(pid))")
        } catch {
            print("❌ Failed to launch command: \(error)")
            unlock()
            return
        }

        CFRunLoopRun()
    }

    // MARK: - Status

    func status() throws {
        let socketPath = "/tmp/guardian.sock"
        if FileManager.default.fileExists(atPath: socketPath) {
            print("🔒 Guardian is running")
        } else {
            print("⚪ Guardian is not running")
        }
    }

    // MARK: - Private

    private func requestUnlock() {
        print("🔑 Unlock requested — authenticating...")
        unlockManager.requestUnlock()
    }

    private func unlock() {
        print("🔓 Unlocking...")

        timer?.invalidate()
        timer = nil
        overlay.hide()
        inputLock.deactivate()
        keepAwake.deactivate()
        processMonitor?.terminate()

        if let start = startTime {
            let elapsed = Date().timeIntervalSince(start)
            print("   Session duration: \(GuardianCLI.formatDuration(elapsed))")
        }

        CFRunLoopStop(CFRunLoopGetCurrent())
    }
}
