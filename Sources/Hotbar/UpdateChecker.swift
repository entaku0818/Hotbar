import Foundation

struct GitHubRelease: Decodable, Equatable {
    let tagName: String
    let htmlURL: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}

protocol ReleaseFetching {
    func fetchLatestRelease() async throws -> GitHubRelease
}

final class GitHubReleaseFetcher: ReleaseFetching {
    /// `URL(fileURLWithPath:)` never fails, so this never actually falls
    /// through to it for our well-formed literal — it just avoids a
    /// force-unwrap of `URL(string:)`.
    private static let defaultReleaseURL = URL(string: "https://api.github.com/repos/entaku0818/Hotbar/releases/latest")
        ?? URL(fileURLWithPath: "/")

    private let url: URL
    private let session: URLSession

    init(
        url: URL = GitHubReleaseFetcher.defaultReleaseURL,
        session: URLSession = .shared
    ) {
        self.url = url
        self.session = session
    }

    func fetchLatestRelease() async throws -> GitHubRelease {
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, _) = try await session.data(for: request)
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }
}

/// Numeric "vX.Y.Z" / "X.Y.Z" version comparison (missing components treated as 0).
enum SemanticVersion {
    static func isNewer(_ lhs: String, than rhs: String) -> Bool {
        let lhsParts = components(of: lhs)
        let rhsParts = components(of: rhs)
        for index in 0..<max(lhsParts.count, rhsParts.count) {
            let left = index < lhsParts.count ? lhsParts[index] : 0
            let right = index < rhsParts.count ? rhsParts[index] : 0
            if left != right { return left > right }
        }
        return false
    }

    private static func components(of versionString: String) -> [Int] {
        let trimmed = versionString.hasPrefix("v") ? String(versionString.dropFirst()) : versionString
        return trimmed.split(separator: ".").map { Int($0) ?? 0 }
    }
}

enum UpdateCheckResult: Equatable {
    case upToDate
    case updateAvailable(version: String, url: URL)
    case checkFailed
}

/// Lightweight update check: compares the running version against the
/// latest tag on GitHub Releases and opens the release page if newer.
/// v1 has no in-app auto-updater (e.g. Sparkle) — this just points the
/// user to the manual download.
final class UpdateChecker {
    static let shared = UpdateChecker()

    private let fetcher: ReleaseFetching
    private let currentVersion: String

    init(
        fetcher: ReleaseFetching = GitHubReleaseFetcher(),
        currentVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    ) {
        self.fetcher = fetcher
        self.currentVersion = currentVersion
    }

    func checkForUpdate() async -> UpdateCheckResult {
        do {
            let release = try await fetcher.fetchLatestRelease()
            guard let url = URL(string: release.htmlURL) else { return .checkFailed }
            guard SemanticVersion.isNewer(release.tagName, than: currentVersion) else { return .upToDate }
            return .updateAvailable(version: release.tagName, url: url)
        } catch {
            return .checkFailed
        }
    }
}
