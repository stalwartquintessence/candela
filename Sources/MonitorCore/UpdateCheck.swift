import Foundation

/// A version number such as 0.2.0 or 1.0.0-beta.2, ordered by Semantic Versioning rules.
public struct SemanticVersion: Comparable, CustomStringConvertible, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int
    /// Pre-release identifiers, for example ["beta", "2"] in 1.0.0-beta.2. Empty for a release.
    public let prerelease: [String]

    public init(major: Int, minor: Int, patch: Int, prerelease: [String] = []) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
    }

    /// Accepts "1.2.3", a tag like "v1.2.3", "1.2" (patch 0) and "1.2.3-beta.1". Build metadata
    /// ("+...") is ignored. Returns nil for anything else.
    public init?(_ text: String) {
        var rest = Substring(text)
        if rest.first == "v" || rest.first == "V" { rest = rest.dropFirst() }
        if let plus = rest.firstIndex(of: "+") { rest = rest[..<plus] }

        var prerelease: [String] = []
        if let dash = rest.firstIndex(of: "-") {
            prerelease = rest[rest.index(after: dash)...]
                .split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            guard prerelease.allSatisfy({ !$0.isEmpty && $0.allSatisfy(Self.isIdentifierCharacter) }) else { return nil }
            rest = rest[..<dash]
        }

        let parts = rest.split(separator: ".", omittingEmptySubsequences: false)
        guard (1 ... 3).contains(parts.count) else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }), let n = Int(part) else { return nil }
            numbers.append(n)
        }
        while numbers.count < 3 { numbers.append(0) }
        self.init(major: numbers[0], minor: numbers[1], patch: numbers[2], prerelease: prerelease)
    }

    public var description: String {
        let core = "\(major).\(minor).\(patch)"
        return prerelease.isEmpty ? core : core + "-" + prerelease.joined(separator: ".")
    }

    public static func < (a: SemanticVersion, b: SemanticVersion) -> Bool {
        if (a.major, a.minor, a.patch) != (b.major, b.minor, b.patch) {
            return (a.major, a.minor, a.patch) < (b.major, b.minor, b.patch)
        }
        // A pre-release comes before its release: 1.0.0-beta < 1.0.0.
        switch (a.prerelease.isEmpty, b.prerelease.isEmpty) {
        case (true, _): return false
        case (false, true): return true
        case (false, false): return precedes(a.prerelease, b.prerelease)
        }
    }

    /// Pre-release identifiers compare one by one: numbers numerically, and before words.
    private static func precedes(_ a: [String], _ b: [String]) -> Bool {
        for (x, y) in zip(a, b) where x != y {
            switch (Int(x), Int(y)) {
            case let (i?, j?): return i < j
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return x < y
            }
        }
        return a.count < b.count
    }

    private static func isIdentifierCharacter(_ c: Character) -> Bool {
        c.isASCII && (c.isLetter || c.isNumber || c == "-")
    }
}

/// Why an update check gave no answer.
public enum UpdateCheckFailure: Equatable, Sendable {
    /// The request never got an HTTP reply (offline, DNS, timeout).
    case offline(String)
    /// GitHub limits unauthenticated requests per network.
    case rateLimited
    /// The repository has no published release (or no longer exists).
    case noReleases
    case unexpectedStatus(Int)
    case unreadableReply

    public var message: String {
        switch self {
        case let .offline(reason):
            // macOS's reason is already a sentence ("The Internet connection appears to be
            // offline."), so it follows as one instead of in brackets.
            let sentence = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sentence.isEmpty else { return "Candela could not reach GitHub. Try again later." }
            let ending = sentence.last.map { ".!?".contains($0) } == true ? "" : "."
            return "Candela could not reach GitHub. \(sentence)\(ending)"
        case .rateLimited:
            return "GitHub is limiting requests from this network. Try again later."
        case .noReleases:
            return "No published release was found on GitHub."
        case let .unexpectedStatus(code):
            return "GitHub replied with an unexpected status (\(code)). Try again later."
        case .unreadableReply:
            return "GitHub's reply could not be read. Try again later."
        }
    }
}

public enum UpdateCheckResult: Equatable, Sendable {
    case upToDate(SemanticVersion)
    /// A newer release, with its page on GitHub.
    case available(SemanticVersion, page: URL)
    case failed(UpdateCheckFailure)
}

/// The update check is Candela's only network request. The app sends it; everything that can be
/// decided without the network is here, so it is unit tested.
public enum UpdateCheck {
    /// Where releases are published. Forks: change this to your own repository.
    public static let repository = "stalwartquintessence/candela"

    /// GitHub's latest published release. Drafts and pre-releases are never returned here.
    public static let latestReleaseURL = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!

    /// The running version. A unit test makes sure AppVersion.string always parses.
    public static let currentVersion = SemanticVersion(AppVersion.string) ?? SemanticVersion(major: 0, minor: 0, patch: 0)

    /// The release page for a version. Built from the version number, never taken from the reply,
    /// so a reply can never make Candela open some other address.
    public static func releasePage(for version: SemanticVersion) -> URL {
        URL(string: "https://github.com/\(repository)/releases/tag/v\(version)")!
    }

    /// How often the automatic check (off by default) asks GitHub.
    public static let interval: TimeInterval = 24 * 60 * 60

    /// Whether the automatic check should ask GitHub now.
    public static func isDue(lastCheck: Date?, now: Date) -> Bool {
        guard let lastCheck else { return true }
        // A last check "in the future" means the clock was set back; do not wait for it.
        return lastCheck > now || now.timeIntervalSince(lastCheck) >= interval
    }

    /// Automatic checks tell the user about each new version once, not every day.
    public static func shouldAnnounce(_ version: SemanticVersion, lastAnnounced: String?) -> Bool {
        guard let lastAnnounced, let announced = SemanticVersion(lastAnnounced) else { return true }
        return version > announced
    }

    /// Turns GitHub's reply into a result.
    public static func result(statusCode: Int, body: Data, current: SemanticVersion = currentVersion) -> UpdateCheckResult {
        switch statusCode {
        case 200: break
        case 404: return .failed(.noReleases)
        case 403, 429: return .failed(.rateLimited)
        default: return .failed(.unexpectedStatus(statusCode))
        }
        guard let release = try? JSONDecoder().decode(Release.self, from: body),
              let latest = SemanticVersion(release.tagName) else {
            return .failed(.unreadableReply)
        }
        if release.draft == true || release.prerelease == true || latest <= current {
            return .upToDate(current)
        }
        return .available(latest, page: releasePage(for: latest))
    }

    private struct Release: Decodable {
        let tagName: String
        let draft: Bool?
        let prerelease: Bool?

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case draft, prerelease
        }
    }
}
