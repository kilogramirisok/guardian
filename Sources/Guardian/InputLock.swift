import Foundation
import CoreGraphics

// CGEventTap-based input blocker.
// Blocks all keyboard and mouse events EXCEPT the unlock shortcut.
// Requires Accessibility permission (System Settings → Privacy & Security → Accessibility).

enum InputLockError: Error {
    case tapCreationFailed(String)
    case accessibilityNotGranted
}

class InputLock {
    private var keyboardTap: CFMachPort?
    private var mouseTap: CFMachPort?
    private var keyboardRunLoopSource: CFRunLoopSource?
    private var mouseRunLoopSource: CFRunLoopSource?

    // Unlock shortcut: Cmd+Shift+L (keycode 37 = 'L')
    private let unlockKeycode: Int64 = 37
    var onUnlockShortcut: (() -> Void)?

    // Check accessibility permission
    static func isAccessibilityGranted() -> Bool {
        return AXIsProcessTrusted()
    }

    // Prompt user to grant accessibility permission
    static func promptAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func activate() throws {
        guard Self.isAccessibilityGranted() else {
            throw InputLockError.accessibilityNotGranted
        }

        // Keyboard event tap
        let keyboardMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        guard let kTap = CGEventTapCreate(
            .cgSessionEventTap,
            .headInsertEventTap,
            .defaultTap,
            CGEventMask(keyboardMask),
            keyboardCallback,
            Unmanaged.passUnretained(self).toOpaque()
        ) else {
            throw InputLockError.tapCreationFailed("Keyboard event tap creation failed. Check Accessibility permissions.")
        }

        keyboardTap = kTap
        keyboardRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, kTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), keyboardRunLoopSource, .commonModes)
        CGEventTapEnable(kTap, true)

        // Mouse event tap
        let mouseMask: CGEventMask = (1 << CGEventType.mouseMoved.rawValue)
            | (1 << CGEventType.leftMouseDragged.rawValue)
            | (1 << CGEventType.rightMouseDragged.rawValue)
            | (1 << CGEventType.otherMouseDragged.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.leftMouseUp.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)
            | (1 << CGEventType.rightMouseUp.rawValue)
            | (1 << CGEventType.otherMouseDown.rawValue)
            | (1 << CGEventType.otherMouseUp.rawValue)
            | (1 << CGEventType.scrollWheel.rawValue)

        guard let mTap = CGEventTapCreate(
            .cgSessionEventTap,
            .headInsertEventTap,
            .defaultTap,
            CGEventMask(mouseMask),
            mouseCallback,
            Unmanaged.passUnretained(self).toOpaque()
        ) else {
            // Clean up keyboard tap if mouse tap fails
            deactivate()
            throw InputLockError.tapCreationFailed("Mouse event tap creation failed.")
        }

        mouseTap = mTap
        mouseRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, mTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), mouseRunLoopSource, .commonModes)
        CGEventTapEnable(mTap, true)
    }

    func deactivate() {
        if let kTap = keyboardTap {
            CGEventTapEnable(kTap, false)
            if let source = keyboardRunLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            }
            keyboardTap = nil
            keyboardRunLoopSource = nil
        }
        if let mTap = mouseTap {
            CGEventTapEnable(mTap, false)
            if let source = mouseRunLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            }
            mouseTap = nil
            mouseRunLoopSource = nil
        }
    }

    deinit {
        deactivate()
    }
}

// MARK: - CGEvent Callbacks

private func keyboardCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon = refcon else { return nil }
    let lock = Unmanaged<InputLock>.fromOpaque(refcon).takeUnretainedValue()

    // Handle tap being disabled by the system (e.g. timeout)
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = lock.keyboardTap {
            CGEventTapEnable(tap, true)
        }
        return nil
    }

    let flags = event.flags
    let keycode = event.getIntegerValueField(.keyboardEventKeycode)

    // Allow Cmd+Shift+L through — trigger unlock
    let hasCmd = flags.contains(.maskCommand)
    let hasShift = flags.contains(.maskShift)
    if hasCmd && hasShift && keycode == lock.unlockKeycode && type == .keyDown {
        // Dispatch unlock asynchronously to avoid deadlocking in the callback
        DispatchQueue.main.async {
            lock.onUnlockShortcut?()
        }
        return nil // swallow the keystroke
    }

    // Block everything else
    return nil
}

private func mouseCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon = refcon else { return nil }
    let lock = Unmanaged<InputLock>.fromOpaque(refcon).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = lock.mouseTap {
            CGEventTapEnable(tap, true)
        }
        return nil
    }

    // Block all mouse events
    return nil
}
