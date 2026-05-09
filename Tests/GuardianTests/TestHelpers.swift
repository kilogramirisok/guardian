import Foundation

// Helper functions exposed for testing.
// These mirror the private logic in GuardianDaemon.

func parseDurationTestHelper(_ input: String) -> Int? {
    let scanner = Scanner(string: input)
    guard let value = scanner.scanInt() else { return nil }
    let remaining = String(input[scanner.currentIndex...]).lowercased()
    switch remaining {
    case "s", "": return value
    case "m": return value * 60
    case "h": return value * 3600
    default: return nil
    }
}

func formatDurationTestHelper(_ interval: TimeInterval) -> String {
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
