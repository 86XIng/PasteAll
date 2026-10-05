import AppKit
import OSLog
import Security

let finderMenuLog = Logger(subsystem: "io.github.86xing.PasteAll", category: "FinderMenu")

/// Accepts only URL events sent by the extension embedded in this app.
/// A URL scheme or bundle identifier alone is not proof of sender identity.
@MainActor
final class FinderPasteReceiver: NSObject {
    private let authenticate: (Data) -> Bool
    private let handleRequest: (FinderPasteRequest) -> Void
    private var pendingRequests: [FinderPasteRequest] = []
    private var isReady = false
    private(set) var receivedLaunchRequest = false

    init(
        authenticate: @escaping (Data) -> Bool = FinderPasteSenderAuthentication.accepts,
        handleRequest: @escaping (FinderPasteRequest) -> Void
    ) {
        self.authenticate = authenticate
        self.handleRequest = handleRequest
    }

    func start() {
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(receive(_:reply:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL)
        )
    }

    /// Installed in willFinishLaunching, before initial Apple events arrive.
    /// Drain only after application setup is complete.
    func finishLaunching() {
        guard !isReady else { return }
        isReady = true
        let requests = pendingRequests
        pendingRequests.removeAll()
        for request in requests { handleRequest(request) }
    }

    @objc func receive(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        receive(
            urlString: event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
            auditToken: event.attributeDescriptor(forKeyword: AEKeyword(keySenderAuditTokenAttr))?.data
        )
    }

    func receive(urlString: String?, auditToken: Data?) {
        guard let auditToken, authenticate(auditToken) else {
            finderMenuLog.error("Rejected request from an unauthenticated sender")
            return
        }
        guard let string = urlString, let url = URL(string: string),
              let request = FinderPasteRequest(url: url)
        else {
            finderMenuLog.error("Rejected malformed request URL")
            return
        }
        finderMenuLog.info("Accepted request, app ready: \(self.isReady, privacy: .public)")

        if isReady {
            handleRequest(request)
        } else {
            receivedLaunchRequest = true
            pendingRequests.append(request)
        }
    }
}

enum FinderPasteSenderAuthentication {
    static func accepts(_ auditToken: Data) -> Bool {
        guard let extensionURL = Bundle.main.builtInPlugInsURL?
            .appendingPathComponent("PasteAllFinderExtension.appex") else { return false }
        return accepts(auditToken, extensionURL: extensionURL)
    }

    static func accepts(_ auditToken: Data, extensionURL: URL) -> Bool {
        guard auditToken.count == MemoryLayout<audit_token_t>.size else { return false }
        var bundledCode: SecStaticCode?
        var requirement: SecRequirement?
        var sender: SecCode?
        // For ad-hoc builds the designated requirement pins the code hash;
        // signed releases bind the identifier and signing identity instead.
        guard SecStaticCodeCreateWithPath(extensionURL as CFURL, [], &bundledCode) == errSecSuccess,
              let bundledCode,
              SecStaticCodeCheckValidity(bundledCode, [], nil) == errSecSuccess,
              SecCodeCopyDesignatedRequirement(bundledCode, [], &requirement) == errSecSuccess,
              let requirement,
              SecCodeCopyGuestWithAttributes(
                nil, [kSecGuestAttributeAudit: auditToken] as CFDictionary, [], &sender
              ) == errSecSuccess,
              let sender
        else { return false }
        return SecCodeCheckValidity(sender, [], requirement) == errSecSuccess
    }
}
