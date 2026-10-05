import Foundation

/// Sent by the Finder Sync extension to ask the app to save the clipboard into
/// a folder. This file is compiled into both targets.
///
/// Launch Services delivers the URL as an Apple event, including the sender's
/// OS-supplied audit token. The host authenticates that token before decoding.
struct FinderPasteRequest: Codable, Equatable {
    static let extensionBundleSuffix = ".FinderExtension"
    private static let urlScheme = "pasteall-finder"

    /// The folder the Finder window shows.
    let containerPath: String
    /// A single selected item may be a destination folder. Background and
    /// multi-selection requests need only the container, not every item path.
    let selectedPaths: [String]
    /// Always show the format picker, regardless of the detection mode.
    let choosesFormat: Bool

    var encoded: String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    init(containerPath: String, selectedPaths: [String], choosesFormat: Bool) {
        self.containerPath = containerPath
        self.selectedPaths = selectedPaths
        self.choosesFormat = choosesFormat
    }

    init(targetedURL: URL, selectedURLs: [URL], isItemMenu: Bool, choosesFormat: Bool) {
        self.init(
            containerPath: (isItemMenu ? targetedURL.deletingLastPathComponent() : targetedURL).path,
            selectedPaths: isItemMenu && selectedURLs.count == 1 ? [selectedURLs[0].path] : [],
            choosesFormat: choosesFormat
        )
    }

    var url: URL? {
        guard let encoded else { return nil }
        var components = URLComponents()
        components.scheme = Self.urlScheme
        components.host = "paste"
        components.queryItems = [URLQueryItem(name: "request", value: encoded)]
        return components.url
    }

    init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == Self.urlScheme, components.host == "paste",
              let items = components.queryItems, items.count == 1,
              items[0].name == "request", let encoded = items[0].value
        else { return nil }
        self.init(encoded: encoded)
    }

    init?(encoded: String) {
        guard let request = try? JSONDecoder().decode(Self.self, from: Data(encoded.utf8)) else { return nil }
        self = request
    }
}
