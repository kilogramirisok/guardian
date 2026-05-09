import Foundation
import CoreGraphics
import ApplicationServices

// CGEventTap-based input blocker.
// Blocks all keyboard and mouse events EXCEPT the unlock shortcut.
// Requires Accessibility permission (System Settings → Privacy & Security → Accessibility).

enum InputLockError: Error {
    case tapCreationFailed(String)
    case accessibilityNotGranted
}

class InputLock {
    var keyboardTap: CFMachPort?
    var mouseTap: CFMachPort?
    private var keyboardRunLoopSource: CFRunLoopSource?
    private var mouseRunLoopSource: CFRunLoopSource?

    // Unlock shortcut: Cmd+Shift+L (keycode 37)
    let unlockKeycode: Int64 = 37
    var onUnlockShortcut: (() -> Void)?

    static func isAccessibilityGranted() -> Bool {
        return AXIsProcessTrusted()
    }

    static func promptAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func activate() throws {
        guard Self.isAccessibilityGranted() else {
            throw InputLockError.accessibilityNotGranted
        }

        // Keyboard event tap using Swift-native API
        let keyDown = CGEventType.keyDown.rawValue
        let keyUp = CGEventType.keyUp.rawValue
        let flagsChanged = CGEventType.flagsChanged.rawValue
        let keyboardMask = CGEventMask(1 << keyDown) | CGEventMask(1 << keyUp) | CGEventMask(1 << flagsChanged)

        guard let kTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: keyboardMask,
            callback: keyboardCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            throw InputLockError.tapCreationFailed("Keyboard event tap creation failed. Check Accessibility permissions.")
        }

        keyboardTap = kTap
        keyboardRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, kTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), keyboardRunLoopSource, .commonModes)
        CGEvent.tapEnable(tap: kTap, enable: true)

        // Mouse event tap — broken into sub-masks to avoid type-checker timeout
        let mouseMoved = CGEventMask(1 << CGEventType.mouseMoved.rawValue)
        let leftDrag = CGEventMask(1 << CGEventType.leftMouseDragged.rawValue)
        let rightDrag = CGEventMask(1 << CGEventType.rightMouseDragged.rawValue)
        let otherDrag = CGEventMask(1 << CGEventType.otherMouseDragged.rawValue)
        let leftDown = CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
        let leftUp = CGEventMask(1 << CGEventType.leftMouseUp.rawValue)
        let rightDown = CGEventMask(1 << CGEventType.rightMouseDown.rawValue)
        let rightUp = CGEventMask(1 << CGEventType.rightMouseUp.rawValue)
        let otherDown = CGEventMask(1 << CGEventType.otherMouseDown.rawValue)
        let otherUp = CGEventMask(1 << CGEventType.otherMouseUp.rawValue)
        let scroll = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        let mouseMask = mouseMoved | leftDrag | rightDrag | otherDrag
            | leftDown | leftUp | rightDown | rightUp
            | otherDown | otherUp | scroll

        guard let mTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mouseMask,
            callback: mouseCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            deactivate()
            throw InputLockError.tapCreationFailed("Mouse event tap creation failed.")
        }

        mouseTap = mTap
        mouseRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, mTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), mouseRunLoopSource, .commonModes)
        CGEvent.tapEnable(tap: mTap, enable: true)
    }

    func deactivate() {
        if let kTap = keyboardTap {
            CGEvent.tapEnable(tap: kTap, enable: false)
            if let source = keyboardRunLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            }
            keyboardTap = nil
            keyboardRunLoopSource = nil
        }
        if let mTap = mouseTap {
            CGEvent.tapEnable(tap: mTap, enable: false)
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
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo = userInfo else { return nil }
    let lock = Unmanaged<InputLock>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = lock.keyboardTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return nil
    }

    let flags = event.flags
    let keycode = event.getIntegerValueField(.keyboardEventKeycode)

    let hasCmd = flags.contains(.maskCommand)
    let hasShift = flags.contains(.maskShift)
    if hasCmd && hasShift && keycode == lock.unlockKeycode && type == .keyDown {
        DispatchQueue.main.async {
            lock.onUnlockShortcut?()
        }
        return nil
    }

    return nil
}

private func mouseCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo = userInfo else { return nil }
    let lock = Unmanaged<InputLock>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = lock.mouseTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return nil
    }

    return nil
}
