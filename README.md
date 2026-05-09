# 🔒 Guardian

Lock input, prevent sleep, keep agents running.

A free, open-source macOS utility that locks all keyboard/mouse input while keeping your screen visible. Designed for developers running long AI agent sessions (Claude Code, Codex, Cursor), builds, and renders.

## Features

- **Input Locking** — Blocks all keyboard, mouse, and trackpad via CGEventTap
- **Sleep Prevention** — Keeps Mac awake via `caffeinate`
- **Touch ID Unlock** — Biometric or password authentication to unlock
- **Auto-Unlock** — `guardian wrap` unlocks automatically when your command finishes
- **Screen Overlay** — Semi-transparent overlay shows locked status on all displays
- **Multi-Display** — Covers all connected displays

## Quick Start

```bash
# Install
curl -L https://github.com/kilogramirisok/guardian/releases/latest/download/guardian -o /usr/local/bin/guardian
chmod +x /usr/local/bin/guardian

# Lock input immediately
guardian lock

# Run a command with auto-lock (unlocks when command exits)
guardian wrap -- claude --dangerously-skip-permissions
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

## Documentation

- [Architecture & Technical Learnings](docs/ARCHITECTURE.md) — how it works, CGEventTap details, CI learnings
- [Build, Publish & Install](docs/BUILD-PUBLISH-INSTALL.md) — building from source, Homebrew tap, signed releases, customer install

## Why not Warden?

[Warden](https://www.getwarden.org) is great — $3.99, polished, does the same thing. Guardian exists because:

- Free and open-source
- CLI-first (scriptable, `wrap` command for agent workflows)
- Auto-unlock on process exit
- Single binary, no dependencies

## Architecture

```
guardian (Swift single binary, ~800 lines)
├── GuardianCLI.swift    CLI entry point (ArgumentParser)
├── InputLock.swift      CGEventTap to block/whitelist HID events
├── KeepAwake.swift      caffeinate subprocess wrapper
├── Overlay.swift        NSPanel fullscreen overlay on all displays
├── Unlock.swift         LocalAuthentication (Touch ID / password)
├── ProcessMonitor.swift Process launch, stdout streaming, exit detection
└── Daemon.swift         CFRunLoop coordinator
```

## License

MIT
