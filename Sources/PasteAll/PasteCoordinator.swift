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

        settings.$isEnabled.sink { [weak self] _ in self?.refreshMonitoring() }
            .store(in: &cancellables)
        accessibility.$isTrusted.sink { [weak self] _ in self?.refreshMonitoring() }
            .store(in: &cancellables)
    }

    func refreshMonitoring() {
        guard settings.isEnabled, accessibility.isTrusted else {
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
                guard pasteboard.changeCount == preparedChangeCount else {
                    isHandlingPaste = false
                    return
                }
                FinderPasteEventTap.postPaste { [weak self] posted in
                    guard let self else { return }
                    guard posted else {
                        try? snapshot.restore(to: pasteboard)
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
                activateFinder()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    paste()
                }
            } else {
                paste()
            }
        }
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
        default:
            String(localized: "error.generation")
        }
    }
}
