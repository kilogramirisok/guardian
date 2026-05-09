import Foundation

// Main daemon that coordinates input locking, keep-awake, overlay, and unlock.
// Runs a CFRunLoop to keep CGEventTap callbacks alive.

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
        // Pre-flight checks
        guard InputLock.isAccessibilityGranted() else {
            print("❌ Accessibility permission not granted.")
            print("   Open System Settings → Privacy & Security → Accessibility")
            print("   Add Terminal (or your terminal app) to the list.")
            InputLock.promptAccessibility()
            return
        }

        print("🔒 Locking input...")
        startTime = Date()

        // Activate components
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

        // Set up unlock handler
        inputLock.onUnlockShortcut = { [weak self] in
            self?.requestUnlock()
        }

        unlockManager.onUnlock = { [weak self] in
            self?.unlock()
        }

        // Timeout timer
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(timeoutSeconds), repeats: false) { [weak self] _ in
            print("⏰ Timeout reached, auto-unlocking...")
            self?.unlock()
        }

        print("🔒 Input locked. Press ⌘⇧L to unlock.")
        print("   Timeout: \(timeoutSeconds)s")

        // Run the run loop (blocks here until unlock)
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
            self?.requestUnlock()
        }

        unlockManager.onUnlock = { [weak self] in
            self?.unlock()
        }

        // Launch the wrapped process
        let monitor = ProcessMonitor()
        processMonitor = monitor

        monitor.onOutput = { output in
            print(output, terminator: "")
        }

        monitor.onExit = { [weak self] exitCode in
            print("\n✅ Command exited with code \(exitCode)")
            self?.overlay.update(message: "Done (exit \(exitCode))")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
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

        // Run the run loop
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
            print("   Session duration: \(formatDuration(elapsed))")
        }

        CFRunLoopStop(CFRunLoopGetCurrent())
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
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
