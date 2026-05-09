# Build, Publish & Install

## Prerequisites

- macOS 14.0+ (Sonoma or Sequoia)
- Xcode 15+ with Command Line Tools (`xcode-select --install`)
- Apple Developer account (only for signed releases — optional for personal use)

## Building from Source

### Quick Build

```bash
git clone https://github.com/kilogramirisok/guardian.git
cd guardian
swift build -c release
```

The binary lands at `.build/release/guardian`.

### Install Locally

```bash
cp .build/release/guardian /usr/local/bin/
# Or anywhere in your PATH:
# cp .build/release/guardian ~/bin/guardian
```

### Verify

```bash
guardian --help
# Should print:
# OVERVIEW: Lock input, prevent sleep, keep agents running.
# USAGE: guardian <subcommand>
# SUBCOMMANDS:
#   lock                Lock all input devices and prevent sleep.
#   wrap                Lock input, run a command, auto-unlock when it exits.
#   status              Query guardian daemon status.
```

### First Run Setup

Before `guardian lock` will work, grant Accessibility permission:

1. Run `guardian lock` once — it will print a message and open System Settings
2. Go to **System Settings → Privacy & Security → Accessibility**
3. Add **Terminal.app** (or iTerm2, Alacritty, etc.) to the allowed list
4. **Restart your terminal** (required — the permission is checked at process launch)
5. Run `guardian lock` again — should now work

If you skip this step, `guardian lock` will print:
```
❌ Accessibility permission not granted.
   Open System Settings → Privacy & Security → Accessibility
```

## Publishing a Release

### Option 1: GitHub Release (Binary Upload)

```bash
# Build release binary
swift build -c release

# Strip debug symbols for smaller binary
strip .build/release/guardian

# Check binary size and architecture
file .build/release/guardian
ls -lh .build/release/guardian

# Create a GitHub release
gh release create v0.1.0 \
  .build/release/guardian \
  --title "v0.1.0" \
  --notes "First release. guardian lock, wrap, and status commands."
```

### Option 2: Homebrew Tap

Create a separate repo `kilogramirisok/homebrew-tap` with a formula:

```ruby
# Formula/guardian.rb
class Guardian < Formula
  desc "Lock input, prevent sleep, keep agents running"
  homepage "https://github.com/kilogramirisok/guardian"
  url "https://github.com/kilogramirisok/guardian/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "<compute with: shasum -a 256 ...>"
  head "https://github.com/kilogramirisok/guardian.git", branch: "main"

  depends_on xcode: ["15.0", :build]
  depends_on :macos

  def install
    system "swift", "build", "-c", "release"
    bin.install ".build/release/guardian"
  end

  test do
    system "#{bin}/guardian", "--help"
  end
end
```

Users install with:
```bash
brew tap kilogramirisok/tap
brew install guardian
```

### Option 3: Signed & Notarized .app Bundle (Professional)

Requires **Apple Developer Program** membership ($99/year).

```bash
# 1. Create an Xcode project wrapper (or use swift-package-manager with a custom scheme)
# 2. Build with Xcode
xcodebuild -scheme Guardian -configuration Release -derivedDataPath build

# 3. Code sign
codesign --sign "Developer ID Application: Your Name (TEAMID)" \
  --options runtime \
  --deep --force \
  build/Build/Products/Release/guardian

# 4. Notarize
notarytool submit build/Build/Products/Release/guardian \
  --apple-id "your@email.com" \
  --team-id "TEAMID" \
  --password "@keychain:AC_PASSWORD" \
  --wait

# 5. Staple
xcrun notarytool staple build/Build/Products/Release/guardian
```

Distribute as a DMG or .zip. No Gatekeeper warnings.

**This is the most polished option but requires the most setup. Only worth it if distributing to non-technical users.**

## CI Pipeline

The repo has a GitHub Actions workflow (`.github/workflows/ci.yml`) that:

1. Runs on `macos-15` runner (Apple Silicon, free for public repos)
2. Builds with `swift build -c release`
3. Runs tests with `swift test`
4. Uploads the binary as an artifact (available for 30 days)

**Limitations of CI testing:**
- Cannot test CGEventTap (no Accessibility permission)
- Cannot test Touch ID (no hardware)
- Cannot test NSPanel overlay (no display)
- Tests cover: arg parsing, duration formatting, process monitoring

**To download the CI-built binary:**
```bash
gh run list --limit 1  # get the run ID
gh run download <run-id>  # downloads guardian-macos-arm64/
```

## Installing on a Customer Machine

### Method 1: Direct Download (Simplest)

```bash
curl -L https://github.com/kilogramirisok/guardian/releases/latest/download/guardian -o /usr/local/bin/guardian
chmod +x /usr/local/bin/guardian
```

On first run, macOS may show "cannot be opened because it is from an unidentified developer." Fix:
- **System Settings → Privacy & Security → scroll down → "Open Anyway"**
- Or right-click the binary → Open → Open

### Method 2: Homebrew

```bash
brew tap kilogramirisok/tap
brew install guardian
```

No Gatekeeper warnings if the formula builds from source (Homebrew compiles it locally).

### Method 3: Build from Source

```bash
git clone https://github.com/kilogramirisok/guardian.git
cd guardian
swift build -c release
sudo cp .build/release/guardian /usr/local/bin/
```

### Post-Install Checklist

On the customer machine, verify:

```bash
# 1. Binary works
guardian --help

# 2. Test with a safe command (auto-unlocks in 3 seconds)
guardian wrap -- sleep 3

# 3. If step 2 says "Accessibility permission not granted":
#    System Settings → Privacy & Security → Accessibility → add Terminal.app
#    Restart terminal, retry step 2

# 4. Real usage — lock while agent runs
guardian wrap -- claude --dangerously-skip-permissions
```

## Architecture Note

The CI-built binary is **arm64 only** (Apple Silicon). For Intel Macs, build from source on the Intel machine, or add a separate CI job:

```yaml
# In ci.yml, add:
build-intel:
  runs-on: macos-13  # Intel runner
  steps:
    - uses: actions/checkout@v4
    - run: swift build -c release
    - uses: actions/upload-artifact@v4
      with:
        name: guardian-macos-x86_64
        path: .build/release/guardian
```

## Troubleshooting

| Problem | Fix |
|---------|-----|
| "Accessibility permission not granted" | System Settings → Privacy & Security → Accessibility → add your terminal app |
| Event taps don't block anything | Restart terminal after granting Accessibility. Check with `guardian lock` — should say "🔒 Input locked" |
| Screen goes to sleep during lock | Check: is the Mac on battery? `caffeinate -s` only works on AC power |
| Touch ID not available | Guardian falls back to password automatically. Or your Mac doesn't have Touch ID |
| Can't unlock — keyboard completely dead | Hold power button 10s to force shutdown. This is the emergency escape |
| Overlay doesn't show | Multiple displays? Check if the panel is behind another fullscreen app. `⌃⌘D` to toggle |
| "cannot be opened because it is from an unidentified developer" | Right-click → Open, or System Settings → Privacy & Security → "Open Anyway" |
