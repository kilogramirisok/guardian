# Architecture & Technical Learnings

## How Guardian Works

Guardian is a single Swift binary that coordinates four macOS system APIs to lock your machine's input while keeping the screen visible and the system awake.

### The Lifecycle

```
guardian lock
  │
  ├─ 1. Check Accessibility permission (AXIsProcessTrusted)
  ├─ 2. Create CGEventTaps (keyboard + mouse)
  ├─ 3. Spawn caffeinate -d -i -s
  ├─ 4. Show NSPanel overlay on all displays
  ├─ 5. Enter CFRunLoop (blocks here)
  │
  │   User presses ⌘⇧L
  │   ├─ EventTap callback detects the shortcut
  │   ├─ Triggers LAContext.evaluatePolicy (Touch ID / password)
  │   ├─ Auth succeeds → tear down everything
  │   └─ Auth fails → stay locked
  │
  └─ 6. CFRunLoopStop → process exits
```

```
guardian wrap -- <command>
  │
  ├─ Steps 1-5 same as lock
  ├─ 6. Launch child process via Process
  ├─ 7. Stream stdout/stderr to terminal
  ├─ 8. waitUntilExit() in background thread
  │
  │   Child exits
  │   ├─ Show "Done (exit N)" on overlay
  │   ├─ 2 second delay
  │   └─ Auto-unlock
  │
  └─ 9. CFRunLoopStop → process exits
```

## Component Deep Dive

### InputLock (CGEventTap)

This is the core. It creates two event taps at the `cgSessionEventTap` level — one for keyboard, one for mouse. These intercept every HID event before any application receives it.

**How event taps work:**
- `CGEvent.tapCreate()` registers a callback with the OS
- The callback receives every keyboard/mouse event in the session
- Returning `nil` from the callback **drops the event** — it never reaches any app
- Returning the event passes it through normally

**The whitelist trick:**
Guardian doesn't block *everything*. The keyboard callback inspects each event for the ⌘⇧L combo. When detected, it triggers the unlock flow — but still returns `nil` (the 'L' keystroke doesn't leak to any app).

```swift
// Inside keyboardCallback:
if hasCmd && hasShift && keycode == unlockKeycode && type == .keyDown {
    DispatchQueue.main.async { lock.onUnlockShortcut?() }
    return nil  // swallow the keystroke
}
return nil  // block everything else
```

**Why two separate taps:**
Keyboard and mouse need different event masks. A single tap with combined masks hits Swift's type-checker timeout (the expression becomes too complex). Splitting into two taps also lets us handle re-enabling independently if one gets disabled by the system.

**Tap disabled recovery:**
macOS can disable event taps if the callback takes too long. The callbacks handle `.tapDisabledByTimeout` and `.tapDisabledByUserInput` by immediately re-enabling the tap.

**Permissions:**
CGEventTap creation silently returns `nil` if the calling process doesn't have Accessibility permission. This is the #1 source of "it doesn't work" bugs. Guardian checks `AXIsProcessTrusted()` before attempting tap creation and prints a helpful message with the System Settings path.

**Access level caveat:**
The callbacks are C-style free functions (required by CGEventTap's API). They can't access `private` members of the `InputLock` class. The tap and keycode properties are `internal` (no access modifier) so the callbacks in the same module can read them.

### KeepAwake (caffeinate)

Originally tried using IOKit power assertions directly (`IOPMAssertionCreateWithName`). This doesn't work in pure Swift because:

- `IOPMAssertionID`, `IOPMAssertionCreateWithName`, `kIOPMAssertPreventUserIdleSystemSleep` etc. are C functions/constants defined in `IOKit/pwr_mgmt.h`
- Swift can import `IOKit` but the power management C API is not automatically bridged
- You'd need a custom modulemap or bridging header — overkill for what amounts to "don't sleep"

The pragmatic solution: spawn `/usr/bin/caffeinate -d -i -s` as a subprocess. Same IOKit assertions under the hood, one line of Swift. Kill the process when unlocking.

**Flags:**
- `-d` — prevent display from sleeping
- `-i` — prevent system from idle sleeping
- `-s` — prevent system from sleeping (AC power only)

### Overlay (NSPanel)

Uses `NSPanel` instead of `NSWindow` because panels don't become the key window by default. This means the overlay doesn't steal focus from the terminal running the agent.

**Key properties:**
- `.borderless` style mask — no title bar, no close button
- `.statusBar + 1` level — above everything except system overlays
- `.canJoinAllSpaces` + `.fullScreenAuxiliary` — visible on all desktops and fullscreen spaces
- `ignoresMouseEvents = false` — overlay catches clicks so they don't pass through

One panel per `NSScreen.screens` entry — covers all connected displays.

**Note:** NSPanel and NSScreen require AppKit. The `DispatchQueue.main.async` calls ensure all UI work happens on the main thread, even when triggered from CGEventTap callbacks (which run on the tap's run loop thread).

### Unlock (LocalAuthentication)

Uses `LAContext` from the LocalAuthentication framework. Two paths:

1. **`.deviceOwnerAuthenticationWithBiometrics`** — Touch ID or Face ID
2. **`.deviceOwnerAuthentication`** — fallback: system password dialog

If Touch ID hardware isn't available (Mac Pro, older MacBook), falls back to password automatically.

**Important:** The biometric prompt is a system dialog that CGEventTap cannot intercept — it's rendered by the Secure Enclave UI, separate from the regular window server. This is by design.

### ProcessMonitor (Foundation.Process)

Wraps `Process` (née `NSTask`) to launch the wrapped command. Key details:

- `readabilityHandler` on the pipe's file handle streams stdout/stderr as data arrives (not buffered to completion)
- `waitUntilExit()` runs on a background `DispatchQueue` to avoid blocking the main run loop
- Exit code is captured and shown on the overlay before auto-unlock

### Daemon (CFRunLoop Coordinator)

The `CFRunLoopRun()` call is what keeps the process alive. Without it, the process would exit immediately after setting up the event taps. The run loop processes:

- CGEventTap callbacks (keyboard/mouse events)
- Timer for timeout auto-unlock
- Dispatch queues for async work

`CFRunLoopStop()` breaks out of the run loop, which allows the process to clean up and exit.

## Learnings from Development

### What bit us during CI

1. **`@main` + `main.swift` conflict:** Swift Package Manager treats any file named `main.swift` as containing top-level code. You cannot use `@main` attribute in a module that has top-level code. **Fix:** renamed to `GuardianCLI.swift`.

2. **C API names vs Swift API names:** `CGEventTapCreate` is a C function. Swift provides `CGEvent.tapCreate(tap:place:options:eventsOfInterest:callback:userInfo:)`. The C names are technically available but produce deprecation/errors. Always use the Swift-native variant.

3. **`IOKit.pwr_mgmt` is not a Swift module:** It's a C header. `import IOKit.pwr_mgmt` fails. Either use a modulemap or (our choice) shell out to `caffeinate`.

4. **`IOPMAssertionLevel.default.rawValue` vs `.defaultValue`:** The Swift bridging for IOKit PM is inconsistent across macOS versions. Not an issue with the caffeinate approach.

5. **CGEventMask type-checker timeout:** Building the mouse event mask as one big expression with `|` operators causes "the compiler is unable to type-check this expression in reasonable time". **Fix:** break into individual `let` bindings, then combine.

6. **`private` members inaccessible from free callbacks:** CGEventTap callbacks are module-level free functions, not methods on the class. They can't access `private` properties. **Fix:** use `internal` (default) access for properties the callbacks need.

### Things to watch on your Mac

1. **Accessibility permission must be granted to Terminal.app** (or whichever app runs guardian). System Settings → Privacy & Security → Accessibility. The first time you run guardian, it'll prompt. You must restart Terminal after granting.

2. **Event taps get disabled after sleep/wake or fast user switching.** The callbacks handle re-enabling, but if the process itself was suspended, recovery might not work. A timeout is your safety net.

3. **External keyboards/mice** — CGEventTap at `.cgSessionEventTap` level catches everything regardless of which device generated the event.

4. **Touch ID on MacBook Pro** works. Touch ID on external Apple keyboards may or may not work depending on macOS version. The password fallback always works.

5. **`caffeinate -s` only works on AC power.** On battery, the system may still sleep. This matches macOS behavior for all caffeinate-based tools.

## File Structure

```
Sources/Guardian/
├── GuardianCLI.swift     @main entry point, CLI arg parsing (ArgumentParser)
├── InputLock.swift       CGEventTap keyboard+mouse blocking
├── KeepAwake.swift       caffeinate subprocess wrapper
├── Overlay.swift         NSPanel fullscreen overlay
├── Unlock.swift          Touch ID / password via LocalAuthentication
├── ProcessMonitor.swift  Process launch, stdout/stderr streaming, exit detection
└── Daemon.swift          CFRunLoop coordinator, lock/wrap/status orchestration

Tests/GuardianTests/
└── GuardianTests.swift   Duration parsing, formatting, process monitor tests
```

## Dependencies

- **swift-argument-parser** (1.3.0+) — CLI arg parsing, `@main` attribute support
- **System frameworks** (no external deps):
  - `CoreGraphics` — CGEventTap
  - `ApplicationServices` — AXIsProcessTrusted
  - `AppKit` — NSPanel, NSScreen
  - `LocalAuthentication` — Touch ID
  - `Foundation` — Process, DispatchQueue, Timer

## What Cannot Be Tested on CI

- CGEventTap creation (needs Accessibility permission — CI runners can't grant it)
- Touch ID (no biometric hardware)
- NSPanel overlay (no display server)
- caffeinate (works but pointless to test — it's a system binary)

These must be tested manually on real hardware. The CI validates compilation, arg parsing, duration formatting, and process monitoring only.
