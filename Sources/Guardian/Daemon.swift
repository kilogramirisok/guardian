import Foundation

// Main daemon that coordinates input locking, keep-awake, overlay, and unlock.
// @MainActor because it owns Overlay (@MainActor) and runs on the main thread.
//
// Safety invariants:
// 1. unlock() is guarded by isUnlocked — safe to call multiple times
// 2. Signal handlers clean up caffeinate/process on SIGTERM/SIGINT
// 3. Emergency unlock fires if CGEventTap re-enable fails
// 4. Watchdog re-checks accessibility permission every 30s

@MainActor
class GuardianDaemon {
    private let inputLock = InputLock()
    private let keepAwake = KeepAwake()
    private let overlay = Overlay()
    private let unlockManager = UnlockManager()
    private var processMonitor: ProcessMonitor?
    private var startTime: Date?
    private var timer: Timer?
    private var watchdogTimer: Timer?
    private var isUnlocked = false
    private var childExitCode: Int32?

    // MARK: - Lock

    func lock(blur: Int, timeoutSeconds: Int) throws {
        guard InputLock.isAccessibilityGranted() else {
            throw GuardianError.accessibilityNotGranted
        }

        print("🔒 Locking input...")
        startTime = Date()
        installSignalHandlers()

        do {
            try inputLock.activate()
        } catch {
            print("❌ Failed to activate input lock: \(error)")
            throw error
        }

        if keepAwake.activate() {
            print("☕ Sleep prevention active")
        } else {
            print("⚠️  Could not prevent sleep (running on battery?)")
        }

        overlay.show(blurLevel: blur)
        startWatchdog()
        setupUnlockCallbacks()

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
            throw GuardianError.accessibilityNotGranted
        }

        print("🔒 Locking input for: \(command.joined(separator: " "))")
        startTime = Date()
        installSignalHandlers()

        do {
            try inputLock.activate()
        } catch {
            print("❌ Failed to activate input lock: \(error)")
            throw error
        }

        if !keepAwake.activate() {
            print("⚠️  Could not prevent sleep (running on battery?)")
        }

        overlay.show(message: "🔒 Running: \(command.last ?? "command")", blurLevel: blur)
        startWatchdog()
        setupUnlockCallbacks()

        let monitor = ProcessMonitor()
        processMonitor = monitor

        monitor.onOutput = { output in
            print(output, terminator: "")
        }

        monitor.onExit = { [weak self] exitCode in
            print("\n✅ Command exited with code \(exitCode)")
            Task { @MainActor in
                self?.childExitCode = exitCode
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
            throw error
        }

        CFRunLoopRun()
    }

    // MARK: - Status

    func status() throws {
        // Check PID file written by lock/wrap
        let pidPath = "/tmp/guardian.pid"
        if let data = FileManager.default.contents(atPath: pidPath),
           let pidStr = String(data: data, encoding: .utf8),
           let pid = Int32(pidStr.trimmingCharacters(in: .whitespacesAndNewlines)) {
            // Check if process is still alive
            if kill(pid, 0) == 0 {
                print("🔒 Guardian is running (PID: \(pid))")
            } else {
                print("⚪ Guardian is not running (stale PID file)")
                try? FileManager.default.removeItem(atPath: pidPath)
            }
        } else {
            print("⚪ Guardian is not running")
        }
    }

    // MARK: - Private

    private func setupUnlockCallbacks() {
        inputLock.onUnlockShortcut = { [weak self] in
            Task { @MainActor in
                self?.requestUnlock()
            }
        }

        inputLock.onEmergencyUnlock = { [weak self] in
            Task { @MainActor in
                print("⚠️  Emergency unlock — event tap recovery failed")
                self?.unlock()
            }
        }

        unlockManager.onUnlock = { [weak self] in
            Task { @MainActor in
                self?.unlock()
            }
        }
    }

    private func startWatchdog() {
        // Periodically verify accessibility permission is still granted
        watchdogTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                if !InputLock.isAccessibilityGranted() {
                    print("⚠️  Accessibility permission lost — emergency unlock")
                    self?.unlock()
                }
            }
        }
    }

    private func requestUnlock() {
        print("🔑 Unlock requested — authenticating...")
        unlockManager.requestUnlock()
    }

    private func unlock() {
        guard !isUnlocked else { return }
        isUnlocked = true

        print("🔓 Unlocking...")

        timer?.invalidate()
        timer = nil
        watchdogTimer?.invalidate()
        watchdogTimer = nil
        overlay.hide()
        inputLock.deactivate()
        keepAwake.deactivate()
        processMonitor?.terminate()

        // Clean up PID file
        try? FileManager.default.removeItem(atPath: "/tmp/guardian.pid")

        if let start = startTime {
            let elapsed = Date().timeIntervalSince(start)
            print("   Session duration: \(GuardianCLI.formatDuration(elapsed))")
        }

        CFRunLoopStop(CFRunLoopGetCurrent())
    }

    private func installSignalHandlers() {
        // Write PID file for `guardian status`
        let pid = ProcessInfo.processInfo.processIdentifier
        try? "\(pid)".write(toFile: "/tmp/guardian.pid", atomically: true, encoding: .utf8)

        // SIGTERM — clean exit (kill, system shutdown)
        signal(SIGTERM) { _ in
            Task { @MainActor in
                // Force cleanup without auth — the process is being killed
                CFRunLoopStop(CFRunLoopGetCurrent())
            }
        }

        // SIGINT — Ctrl+C from another terminal
        signal(SIGINT) { _ in
            Task { @MainActor in
                CFRunLoopStop(CFRunLoopGetCurrent())
            }
        }
    }
}

// MARK: - Errors

enum GuardianError: Error, LocalizedError {
    case accessibilityNotGranted

    var errorDescription: String? {
        switch self {
        case .accessibilityNotGranted:
            return "Accessibility permission not granted. Open System Settings → Privacy & Security → Accessibility"
        }
    }
}
