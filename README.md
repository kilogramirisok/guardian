# 🔒 Guardian

Lock input, prevent sleep, keep agents running.

A free, open-source macOS utility that locks all keyboard/mouse input while keeping your screen visible. Designed for developers running long AI agent sessions (Claude Code, Codex, Cursor), builds, and renders.

## Features

- **Input Locking** — Blocks all keyboard, mouse, and trackpad via CGEventTap
- **Sleep Prevention** — Keeps Mac awake using IOKit power assertions
- **Touch ID Unlock** — Biometric or password authentication to unlock
- **Auto-Unlock** — `guardian wrap` unlocks automatically when your command finishes
- **Screen Overlay** — Optional blur overlay shows locked status
- **Multi-Display** — Covers all connected displays

## Install

```bash
# Download latest binary
curl -L https://github.com/kilogramirisok/guardian/releases/latest/download/guardian -o /usr/local/bin/guardian
chmod +x /usr/local/bin/guardian
```

Or build from source:
```bash
git clone https://github.com/kilogramirisok/guardian.git
cd guardian
swift build -c release
cp .build/release/guardian /usr/local/bin/
```

## Usage

### Lock input immediately

```bash
guardian lock
```

All input blocked. Press `⌘⇧L` → Touch ID to unlock.

### Lock with screen blur

```bash
guardian lock --screen-blur --blur 7
```

### Lock with auto-timeout

```bash
guardian lock --timeout 30m
```

### Run a command with auto-lock

```bash
guardian wrap -- claude --dangerously-skip-permissions
```

Input locks, command runs, auto-unlocks when finished. Zero interaction needed.

### Check status

```bash
guardian status
```

## Unlock Methods

| Method | How |
|--------|-----|
| **Keyboard shortcut** | `⌘⇧L` → Touch ID / password prompt |
| **Auto-unlock** | `guardian wrap` unlocks when process exits |
| **Timeout** | `--timeout` auto-unlocks after duration |

**Emergency exit:** Hold power button to force shutdown (last resort).

## Requirements

- macOS 14.0+ (Sonoma / Sequoia)
- Accessibility permission (System Settings → Privacy & Security → Accessibility)
- Add Terminal.app (or your terminal) to the allowed list

## Why not Warden?

[Warden](https://www.getwarden.org) is great — $3.99, polished, does the same thing. Guardian exists because:

- Free and open-source
- CLI-first (scriptable, `wrap` command for agent workflows)
- Auto-unlock on process exit
- Single binary, no dependencies

## Architecture

```
guardian (Swift single binary)
├── InputLock.swift      — CGEventTap to block/whitelist HID events
├── KeepAwake.swift      — IOKit power assertions (caffeinate-style)
├── Overlay.swift        — NSPanel fullscreen overlay on all displays
├── Unlock.swift         — LocalAuthentication (Touch ID / password)
├── ProcessMonitor.swift — PID monitoring for wrap auto-unlock
└── Daemon.swift         — Coordinates all components via CFRunLoop
```

## Limitations

- macOS only (CGEventTap, LocalAuthentication, IOKit are Apple frameworks)
- Requires Accessibility permission (non-negotiable for input interception)
- Not code-signed — Gatekeeper may warn on first run
- `pynput` on macOS 15+ is broken — this uses raw CGEventTap instead

## License

MIT
