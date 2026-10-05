import AppKit
import Combine
import Foundation
import PasteAllCore

@MainActor
final class PasteCoordinator: ObservableObject {
    static let shared = PasteCoordinator()

    @Published private(set) var isMonitoring = false

    private let settings = SettingsStore.shared
    private let accessibility = AccessibilityController.shared
    private let detector = ContentDetector()
    private let generator = FileGenerator()
    private let eventTap = FinderPasteEventTap()
    private let picker = CandidatePicker()
    private let errors = ErrorPresenter()
    private var cacheStore: CacheStore?
    private var cancellables = Set<AnyCancellable>()
    private var isHandlingPaste = false

    private init() {
        cacheStore = try? CacheStore()
        cacheStore?.cleanup()
        eventTap.onFinderPaste = { [weak self] in
            self?.interceptFinderPaste() ?? false
        }
        eventTap.shortcutProvider = { [weak settings] in
            settings?.pasteShortcut ?? .defaultShortcut
        }

        settings.$isEnabled.combineLatest(accessibility.$isTrusted)
            .sink { [weak self] enabled, trusted in
                self?.updateMonitoring(enabled: enabled, trusted: trusted)
            }
            .store(in: &cancellables)
    }

    func refreshMonitoring() {
        updateMonitoring(enabled: settings.isEnabled, trusted: accessibility.isTrusted)
    }

    private func updateMonitoring(enabled: Bool, trusted: Bool) {
        guard enabled, trusted else {
            eventTap.stop()
            isMonitoring = false
            return
        }
        isMonitoring = eventTap.start()
    }

    private func interceptFinderPaste() -> Bool {
        guard !isHandlingPaste else { return true }
        let pasteboard = NSPasteboard.general
        let snapshot = ClipboardSnapshot(pasteboard: pasteboard)
        if snapshot.containsFileReference { return false }

        let candidates = detector.candidates(
            for: snapshot,
            mode: settings.detectionMode,
            preferredURLFormat: settings.shortcutFormat
        )
        guard !candidates.isEmpty else { return false }
        isHandlingPaste = true

        if settings.detectionMode == .askEveryTime {
            picker.choose(from: candidates) { [weak self] candidate in
                guard let self else { return }
                guard let candidate else {
                    self.isHandlingPaste = false
                    self.activateFinder()
                    return
                }
                self.prepareAndPaste(candidate, snapshot: snapshot, needsFinderActivation: true)
            }
        } else {
            prepareAndPaste(candidates[0], snapshot: snapshot, needsFinderActivation: false)
        }
        return true
    }

    private func prepareAndPaste(
        _ candidate: ConversionCandidate,
        snapshot: ClipboardSnapshot,
        needsFinderActivation: Bool
    ) {
        guard let cacheStore else {
            isHandlingPaste = false
            errors.show(String(localized: "error.cache"))
            return
        }
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount == snapshot.changeCount else {
            isHandlingPaste = false
            errors.show(String(localized: "error.clipboardChanged"))
            return
        }

        let destination: URL
        do {
            destination = try cacheStore.reserveDestination(for: candidate.kind) { key in
                NSLocalizedString(key, comment: "Generated filename stem")
            }
        } catch {
            isHandlingPaste = false
            errors.show(localizedMessage(for: error))
            return
        }

        // Return focus after the picker closes, before asynchronous generation.
        // Never reactivate Finder later if the user switches apps while waiting.
        if needsFinderActivation { activateFinder() }

        let generator = self.generator
        let generation = Task.detached(priority: .userInitiated) {
            try generator.generate(candidate, at: destination)
            try cacheStore.secure(destination)
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await generation.value
            } catch {
                try? FileManager.default.removeItem(at: destination)
                isHandlingPaste = false
                errors.show(localizedMessage(for: error))
                return
            }

            guard pasteboard.changeCount == snapshot.changeCount else {
                try? FileManager.default.removeItem(at: destination)
                isHandlingPaste = false
                errors.show(String(localized: "error.clipboardChanged"))
                return
            }

            pasteboard.clearContents()
            guard pasteboard.writeObjects([destination as NSURL]) else {
                try? snapshot.restore(to: pasteboard)
                try? FileManager.default.removeItem(at: destination)
                isHandlingPaste = false
                errors.show(String(localized: "error.pasteboard"))
                return
            }
            let preparedChangeCount = pasteboard.changeCount

            let paste = { [weak self] in
                guard let self else { return }
                FinderPasteEventTap.postPaste(isValid: { [weak self] in
                    guard let self else { return false }
                    return pasteboard.changeCount == preparedChangeCount
                        && self.settings.isEnabled && self.accessibility.isTrusted
                }) { [weak self] posted in
                    guard let self else { return }
                    guard posted else {
                        if ClipboardRestorationPolicy.shouldRestore(
                            currentChangeCount: pasteboard.changeCount,
                            preparedChangeCount: preparedChangeCount
                        ) {
                            try? snapshot.restore(to: pasteboard)
                        }
                        try? FileManager.default.removeItem(at: destination)
                        isHandlingPaste = false
                        errors.show(String(localized: "error.event"))
                        return
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                        if ClipboardRestorationPolicy.shouldRestore(
                            currentChangeCount: pasteboard.changeCount,
                            preparedChangeCount: preparedChangeCount
                        ) {
                            try? snapshot.restore(to: pasteboard)
                        }
                        self?.isHandlingPaste = false
                    }
                }
            }

            if needsFinderActivation {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    paste()
                }
            } else {
                paste()
            }
        }
    }

    /// Handles the Finder context menu: writes the converted clipboard straight
    /// into the folder, without touching the clipboard or replaying keystrokes.
    func handleFinderMenuRequest(_ request: FinderPasteRequest) {
        guard settings.isEnabled else {
            finderMenuLog.notice("Ignored request: PasteAll is disabled")
            errors.show(String(localized: "error.disabled"))
            return
        }
        // FinderPasteReceiver authenticates the extension before calling this.
        // Focus may change during launch; it is not an authentication signal.
        guard !isHandlingPaste else {
            finderMenuLog.notice("Ignored request: another paste is in progress")
            return
        }
        guard let directory = Self.destinationDirectory(for: request) else {
            finderMenuLog.error("No writable destination for \(request.containerPath, privacy: .private)")
            errors.show(String(localized: "error.destination"))
            return
        }

        let snapshot = ClipboardSnapshot(pasteboard: .general)
        let candidates = detector.candidates(
            for: snapshot,
            mode: settings.detectionMode,
            preferredURLFormat: settings.shortcutFormat
        )
        guard !candidates.isEmpty else {
            finderMenuLog.notice("No convertible clipboard content")
            errors.show(String(localized: "error.unsupported"))
            return
        }
        finderMenuLog.info("Converting clipboard as \(candidates[0].kind.rawValue, privacy: .public) (\(candidates.count, privacy: .public) candidates)")
        isHandlingPaste = true

        if request.choosesFormat || settings.detectionMode == .askEveryTime {
            picker.choose(from: candidates) { [weak self] candidate in
                guard let self else { return }
                self.activateFinder()
                guard let candidate else {
                    self.isHandlingPaste = false
                    return
                }
                self.write(candidate, into: directory)
            }
        } else {
            write(candidates[0], into: directory)
        }
    }

    private func write(_ candidate: ConversionCandidate, into directory: URL) {
        let destination: URL
        do {
            destination = try CacheStore.reserveFile(
                for: candidate.kind,
                in: directory,
                permissions: S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH
            ) { key in
                NSLocalizedString(key, comment: "Generated filename stem")
            }
        } catch {
            finderMenuLog.error("Could not reserve a file: \(error.localizedDescription, privacy: .public)")
            isHandlingPaste = false
            errors.show(localizedMessage(for: error))
            return
        }

        let generator = self.generator
        Task { [weak self] in
            do {
                try await Task.detached(priority: .userInitiated) {
                    try generator.generate(candidate, at: destination)
                }.value
                finderMenuLog.info("Wrote \(destination.lastPathComponent, privacy: .private)")
            } catch {
                finderMenuLog.error("Generation failed: \(error.localizedDescription, privacy: .public)")
                try? FileManager.default.removeItem(at: destination)
                if let self { errors.show(localizedMessage(for: error)) }
            }
            self?.isHandlingPaste = false
        }
    }

    /// A single right-clicked folder is the destination; otherwise the folder
    /// the Finder window shows. Packages such as .app bundles count as files.
    static func destinationDirectory(
        for request: FinderPasteRequest,
        fileManager: FileManager = .default
    ) -> URL? {
        func directory(atPath path: String) -> URL? {
            guard path.hasPrefix("/") else { return nil }
            let url = URL(fileURLWithPath: path).standardizedFileURL
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey]),
                  values.isDirectory == true,
                  values.isPackage != true,
                  fileManager.isWritableFile(atPath: url.path)
            else { return nil }
            return url
        }

        if request.selectedPaths.count == 1, let selected = directory(atPath: request.selectedPaths[0]) {
            return selected
        }
        return directory(atPath: request.containerPath)
    }

    private func activateFinder() {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder")
            .first?.activate(options: [])
    }

    private func localizedMessage(for error: Error) -> String {
        switch error {
        case PasteAllError.clipboardChanged:
            String(localized: "error.clipboardChanged")
        case PasteAllError.cannotCreateCache:
            String(localized: "error.cache")
        case PasteAllError.cannotWritePasteboard:
            String(localized: "error.pasteboard")
        case PasteAllError.invalidTable:
            String(localized: "error.table")
        case PasteAllError.cannotWriteDestination:
            String(localized: "error.destination")
        default:
            String(localized: "error.generation")
        }
    }
}
