import AppKit
import PasteAllCore
import SwiftUI

@MainActor
final class CandidatePicker {
    static let width: CGFloat = 300

    private var panel: NSPanel?
    private var resignObserver: NSObjectProtocol?

    func choose(
        from candidates: [ConversionCandidate],
        completion: @escaping (ConversionCandidate?) -> Void
    ) {
        guard !candidates.isEmpty else {
            completion(nil)
            return
        }

        var completed = false
        let finish: (ConversionCandidate?) -> Void = { [weak self] candidate in
            guard !completed else { return }
            completed = true
            if let observer = self?.resignObserver {
                NotificationCenter.default.removeObserver(observer)
                self?.resignObserver = nil
            }
            self?.panel?.orderOut(nil)
            self?.panel = nil
            completion(candidate)
        }

        let hosting = NSHostingController(
            rootView: CandidatePickerView(candidates: candidates, onSelect: finish, onCancel: { finish(nil) })
        )
        hosting.sizingOptions = []
        let size = hosting.sizeThatFits(in: NSSize(width: Self.width, height: .greatestFiniteMagnitude))

        // Borderless, so no hidden title bar adds an empty strip above the
        // options, and the frame matches the content exactly.
        //
        // Non-activating: the request usually arrives while Finder is active,
        // and macOS may refuse a background app's activation. The panel takes
        // keyboard focus without activating PasteAll, and must not hide when
        // PasteAll is inactive or the pending paste would never finish.
        let panel = PickerPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.transient, .moveToActiveSpace]
        panel.contentViewController = hosting
        panel.setContentSize(size)

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let origin = Self.origin(for: size, at: mouse, within: screen?.visibleFrame ?? .zero)
        panel.setFrameOrigin(origin)

        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()

        // Like a menu: clicking anywhere else dismisses it.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { finish(nil) }
        }
    }

    /// The bottom-right corner sits at the pointer, so the picker opens up and
    /// to the left of the clicked menu item instead of covering the area below
    /// it. Flips right or downward when it would run off the screen.
    static func origin(for size: NSSize, at mouse: NSPoint, within visible: NSRect) -> NSPoint {
        var x = mouse.x - size.width
        var y = mouse.y
        if x < visible.minX { x = mouse.x }
        if y + size.height > visible.maxY { y = mouse.y - size.height }
        x = min(max(x, visible.minX), visible.maxX - size.width)
        y = min(max(y, visible.minY), visible.maxY - size.height)
        return NSPoint(x: x, y: y)
    }
}

/// Borderless panels cannot become key by default, which the keyboard
/// shortcuts (Return, Escape, number keys) rely on.
private final class PickerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private struct CandidatePickerView: View {
    let candidates: [ConversionCandidate]
    let onSelect: (ConversionCandidate) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("picker.title")
                .font(.headline)
                .padding(.bottom, 2)
            ForEach(Array(candidates.enumerated()), id: \.element.id) { index, candidate in
                CandidateButton(
                    candidate: candidate,
                    index: index,
                    action: { onSelect(candidate) }
                )
            }
        }
        .padding(14)
        .frame(width: CandidatePicker.width, alignment: .topLeading)
        .background {
            Button(action: onCancel) { EmptyView() }
                .keyboardShortcut(.cancelAction)
                .hidden()
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
        }
    }
}

private struct CandidateButton: View {
    let candidate: ConversionCandidate
    let index: Int
    let action: () -> Void

    var body: some View {
        if index == 0 {
            button.keyboardShortcut(.defaultAction)
        } else {
            button.keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
        }
    }

    private var button: some View {
        Button(action: action) {
            HStack {
                Image(systemName: candidate.kind.systemImage)
                Text(candidate.kind.localizedLabel)
                Spacer()
                if index == 0 {
                    Text("picker.recommended")
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}

extension OutputKind {
    var localizedLabel: LocalizedStringKey {
        switch self {
        case .png: "format.png"
        case .jpeg: "format.jpeg"
        case .text: "format.text"
        case .markdown: "format.markdown"
        case .spreadsheet: "format.spreadsheet"
        case .webloc: "format.webloc"
        case .internetShortcut: "format.url"
        }
    }

    var systemImage: String {
        switch self {
        case .png, .jpeg: "photo"
        case .text: "doc.text"
        case .markdown: "text.document"
        case .spreadsheet: "tablecells"
        case .webloc, .internetShortcut: "link"
        }
    }
}
