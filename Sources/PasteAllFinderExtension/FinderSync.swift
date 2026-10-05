import AppKit
import FinderSync
import OSLog

private let log = Logger(subsystem: "io.github.86xing.PasteAll", category: "FinderExtension")

/// Adds "Paste Clipboard as File" to Finder's context menu. The extension is
/// sandboxed and cannot write into arbitrary folders, so it only forwards the
/// target location to the PasteAll app, which does the conversion.
final class FinderSync: FIFinderSync {
    private var lastMenuKind: FIMenuKind = .contextualMenuForContainer

    override init() {
        super.init()
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForContainer || menuKind == .contextualMenuForItems,
              clipboardMayContainConvertibleContent()
        else { return nil }
        lastMenuKind = menuKind

        let menu = NSMenu(title: "")
        let paste = NSMenuItem(
            title: NSLocalizedString("finder.menu.paste", comment: "Finder context menu item"),
            action: #selector(pasteAsFile(_:)),
            keyEquivalent: ""
        )
        paste.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil)
        menu.addItem(paste)
        menu.addItem(
            withTitle: NSLocalizedString("finder.menu.pasteChoosing", comment: "Finder context menu item"),
            action: #selector(pasteChoosingFormat(_:)),
            keyEquivalent: ""
        )
        return menu
    }

    @objc private func pasteAsFile(_ sender: AnyObject?) {
        send(choosesFormat: false)
    }

    @objc private func pasteChoosingFormat(_ sender: AnyObject?) {
        send(choosesFormat: true)
    }

    /// Finder already offers its own Paste for copied files, and an empty
    /// clipboard has nothing to convert. Only types are read here, never data.
    private func clipboardMayContainConvertibleContent() -> Bool {
        let types = NSPasteboard.general.types ?? []
        return !types.isEmpty && !types.contains(.fileURL)
    }

    private func send(choosesFormat: Bool) {
        let controller = FIFinderSyncController.default()
        guard let target = controller.targetedURL() else {
            log.error("Finder provided no targeted URL")
            return
        }
        let request = FinderPasteRequest(
            targetedURL: target,
            selectedURLs: controller.selectedItemURLs() ?? [],
            isItemMenu: lastMenuKind == .contextualMenuForItems,
            choosesFormat: choosesFormat
        )
        guard let url = request.url else {
            log.error("Could not encode the request")
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.allowsRunningApplicationSubstitution = false
        // Explicitly target our containing app. Launch Services queues the URL
        // until it is ready and preserves the extension's sender audit token.
        NSWorkspace.shared.open(
            [url], withApplicationAt: hostApplicationURL, configuration: configuration
        ) { _, error in
            if let error {
                log.error("Could not hand off to PasteAll: \(error.localizedDescription, privacy: .public)")
            } else {
                log.info("Handed off request to PasteAll")
            }
        }
    }

    /// PasteAll.app/Contents/PlugIns/PasteAllFinderExtension.appex
    private var hostApplicationURL: URL {
        Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
