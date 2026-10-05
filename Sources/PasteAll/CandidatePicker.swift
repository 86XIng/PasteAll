import AppKit
import PasteAllCore
import SwiftUI

@MainActor
final class CandidatePicker {
    private enum Layout {
        static let width: CGFloat = 320
        static let baseHeight: CGFloat = 90
        static let rowHeight: CGFloat = 40

        static func panelSize(candidateCount: Int) -> NSSize {
            NSSize(
                width: width,
                height: baseHeight + CGFloat(candidateCount) * rowHeight
            )
        }
    }

    private var panel: NSPanel?

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
            self?.panel?.orderOut(nil)
            self?.panel = nil
            completion(candidate)
        }

        let panelSize = Layout.panelSize(candidateCount: candidates.count)
        let view = CandidatePickerView(candidates: candidates, onSelect: finish, onCancel: { finish(nil) })
            .frame(
                width: panelSize.width,
                height: panelSize.height,
                alignment: .topLeading
            )
        let hosting = NSHostingController(rootView: view)
        hosting.sizingOptions = []
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.transient, .moveToActiveSpace]
        panel.contentViewController = hosting
        panel.setContentSize(panelSize)
        panel.minSize = panel.frame.size
        panel.maxSize = panel.frame.size
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        var origin = NSPoint(x: mouse.x + 12, y: mouse.y - panel.frame.height - 12)
        origin.x = min(max(origin.x, visible.minX), visible.maxX - panel.frame.width)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - panel.frame.height)
        panel.setFrameOrigin(origin)

        self.panel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }
}

private struct CandidatePickerView: View {
    let candidates: [ConversionCandidate]
    let onSelect: (ConversionCandidate) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("picker.title")
                .font(.headline)
            ForEach(Array(candidates.enumerated()), id: \.element.id) { index, candidate in
                CandidateButton(
                    candidate: candidate,
                    index: index,
                    action: { onSelect(candidate) }
                )
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            Button(action: onCancel) { EmptyView() }
                .keyboardShortcut(.cancelAction)
                .hidden()
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
