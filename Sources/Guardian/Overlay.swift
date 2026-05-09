import Foundation
import AppKit

// Full-screen overlay that shows "Locked" status.
// Uses NSPanel to avoid stealing focus from the wrapped process.
// All AppKit UI work is isolated to @MainActor (Swift 6 requirement).

@MainActor
class Overlay {
    private var panels: [NSPanel] = []

    func show(message: String = "🔒 Locked", blurLevel: Int = 0) {
        createPanels(message: message, blurLevel: blurLevel)
    }

    func hide() {
        for panel in panels {
            panel.orderOut(nil)
        }
        panels.removeAll()
    }

    func update(message: String) {
        for panel in panels {
            if let contentView = panel.contentView,
               let label = contentView.subviews.first(where: { $0 is NSTextField }) as? NSTextField {
                label.stringValue = message
            }
        }
    }

    private func createPanels(message: String, blurLevel: Int) {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }

        for screen in screens {
            let panel = NSPanel(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            panel.isFloatingPanel = true
            panel.level = .statusBar + 1
            let alpha = 0.15 + (Double(blurLevel) / 10.0) * 0.5
            panel.backgroundColor = NSColor.black.withAlphaComponent(alpha)
            panel.isOpaque = false
            panel.hasShadow = false
            panel.ignoresMouseEvents = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.hidesOnDeactivate = false

            let label = NSTextField(labelWithString: message)
            label.font = NSFont.systemFont(ofSize: 48, weight: .bold)
            label.textColor = .white
            label.alignment = .center
            label.frame = NSRect(
                x: screen.frame.midX - 200,
                y: screen.frame.midY - 30,
                width: 400,
                height: 60
            )

            let subtitle = NSTextField(labelWithString: "⌘⇧L to unlock")
            subtitle.font = NSFont.systemFont(ofSize: 18, weight: .regular)
            subtitle.textColor = NSColor.white.withAlphaComponent(0.6)
            subtitle.alignment = .center
            subtitle.frame = NSRect(
                x: screen.frame.midX - 100,
                y: screen.frame.midY - 70,
                width: 200,
                height: 30
            )

            panel.contentView?.addSubview(label)
            panel.contentView?.addSubview(subtitle)
            panel.orderFrontRegardless()

            panels.append(panel)
        }
    }
}
