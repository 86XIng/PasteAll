import AppKit
import SwiftUI

@MainActor
final class ErrorPresenter {
    private var panel: NSPanel?

    func show(_ message: String) {
        panel?.orderOut(nil)
        let view = HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 340, alignment: .leading)
        // The window is transparent; without a backing the text would sit
        // directly on whatever is behind it, unreadable in dark mode.
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
        }

        let hosting = NSHostingController(rootView: view)
        hosting.sizingOptions = []
        let size = hosting.sizeThatFits(in: NSSize(width: 340, height: CGFloat.greatestFiniteMagnitude))
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.ignoresMouseEvents = true

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? .zero
        var origin = NSPoint(x: mouse.x + 12, y: mouse.y - panel.frame.height - 12)
        origin.x = min(max(origin.x, visibleFrame.minX), visibleFrame.maxX - panel.frame.width)
        origin.y = min(max(origin.y, visibleFrame.minY), visibleFrame.maxY - panel.frame.height)
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
        panel.invalidateShadow()
        self.panel = panel
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self, weak panel] in
            panel?.orderOut(nil)
            if self?.panel === panel { self?.panel = nil }
        }
    }
}
