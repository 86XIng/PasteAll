import Foundation

/// A dotted numeric version such as `1.2` or `v1.2.3`. Pre-release and build
/// suffixes (`-beta.1`, `+5`) are ignored, and missing components compare as
/// zero, so `1.2` equals `1.2.0`.
public struct AppVersion: Comparable, CustomStringConvertible, Sendable {
    public let components: [Int]

    public init?(_ string: String) {
        var value = Substring(string.trimmingCharacters(in: .whitespaces))
        if value.first == "v" || value.first == "V" { value = value.dropFirst() }
        let core = value.prefix { $0 != "-" && $0 != "+" }
        let parts = core.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.count <= 4 else { return nil }

        var components: [Int] = []
        for part in parts {
            guard !part.isEmpty,
                  part.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let number = Int(part)
            else { return nil }
            components.append(number)
        }
        self.components = components
    }

    public var description: String {
        components.map(String.init).joined(separator: ".")
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        compare(lhs, rhs) == 0
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        compare(lhs, rhs) < 0
    }

    private static func compare(_ lhs: AppVersion, _ rhs: AppVersion) -> Int {
        for index in 0..<max(lhs.components.count, rhs.components.count) {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right ? -1 : 1 }
        }
        return 0
    }
}

/// The subset of GitHub's release JSON that the update check relies on.
public struct ReleaseInfo: Decodable, Equatable, Sendable {
    public let tagName: String
    public let pageURL: URL
    public let notes: String
    public let isDraft: Bool
    public let isPrerelease: Bool

    public init(tagName: String, pageURL: URL, notes: String = "", isDraft: Bool = false, isPrerelease: Bool = false) {
        self.tagName = tagName
        self.pageURL = pageURL
        self.notes = notes
        self.isDraft = isDraft
        self.isPrerelease = isPrerelease
    }

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case pageURL = "html_url"
        case notes = "body"
        case isDraft = "draft"
        case isPrerelease = "prerelease"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tagName = try container.decode(String.self, forKey: .tagName)
        pageURL = try container.decode(URL.self, forKey: .pageURL)
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        isDraft = try container.decodeIfPresent(Bool.self, forKey: .isDraft) ?? false
        isPrerelease = try container.decodeIfPresent(Bool.self, forKey: .isPrerelease) ?? false
    }
}

public enum UpdateCheckResult: Equatable, Sendable {
    case upToDate
    case updateAvailable(AppVersion, ReleaseInfo)
}

public enum UpdateCheck {
    public static func latestReleaseURL(repository: String) -> URL? {
        URL(string: "https://api.github.com/repos/\(repository)/releases/latest")
    }

    /// Returns nil when either version cannot be parsed or the release page is
    /// not on github.com, so a malformed response never opens an arbitrary URL.
    public static func evaluate(currentVersion: String, release: ReleaseInfo) -> UpdateCheckResult? {
        guard let current = AppVersion(currentVersion),
              let latest = AppVersion(release.tagName),
              release.pageURL.scheme == "https",
              release.pageURL.host?.lowercased() == "github.com"
        else { return nil }

        guard !release.isDraft, !release.isPrerelease, latest > current else { return .upToDate }
        return .updateAvailable(latest, release)
    }

    /// Homebrew keeps per-cask metadata in its Caskroom even after moving the
    /// app into /Applications, which tells us how the user prefers to upgrade.
    public static func isHomebrewInstall(
        caskToken: String,
        prefixes: [String] = ["/opt/homebrew", "/usr/local"],
        fileManager: FileManager = .default
    ) -> Bool {
        prefixes.contains { prefix in
            fileManager.fileExists(atPath: "\(prefix)/Caskroom/\(caskToken)")
        }
    }

    /// The previous launch's build is nil on a first install, which is not an update.
    public static func didUpdate(previousBuild: String?, currentBuild: String) -> Bool {
        guard let previousBuild else { return false }
        return previousBuild != currentBuild
    }
}
