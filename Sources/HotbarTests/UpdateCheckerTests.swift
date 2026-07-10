import XCTest
@testable import Hotbar

final class UpdateCheckerTests: XCTestCase {
    func testNoUpdateWhenVersionsMatch() async {
        let fetcher = MockReleaseFetcher(result: .success(
            GitHubRelease(tagName: "v1.1.0", htmlURL: "https://github.com/entaku0818/Hotbar/releases/tag/v1.1.0")
        ))
        let checker = UpdateChecker(fetcher: fetcher, currentVersion: "1.1.0")

        let result = await checker.checkForUpdate()

        XCTAssertEqual(result, .upToDate)
    }

    func testUpdateAvailableWhenRemoteIsNewer() async throws {
        let releaseURL = "https://github.com/entaku0818/Hotbar/releases/tag/v1.2.0"
        let fetcher = MockReleaseFetcher(result: .success(
            GitHubRelease(tagName: "v1.2.0", htmlURL: releaseURL)
        ))
        let checker = UpdateChecker(fetcher: fetcher, currentVersion: "1.1.0")

        let result = await checker.checkForUpdate()

        let expectedURL = try XCTUnwrap(URL(string: releaseURL))
        XCTAssertEqual(result, .updateAvailable(version: "v1.2.0", url: expectedURL))
    }

    func testNoUpdateWhenLocalIsNewerThanRemote() async {
        let fetcher = MockReleaseFetcher(result: .success(
            GitHubRelease(tagName: "v1.0.0", htmlURL: "https://example.com/v1.0.0")
        ))
        let checker = UpdateChecker(fetcher: fetcher, currentVersion: "1.1.0")

        let result = await checker.checkForUpdate()

        XCTAssertEqual(result, .upToDate)
    }

    func testCheckFailedOnNetworkError() async {
        let fetcher = MockReleaseFetcher(result: .failure(URLError(.notConnectedToInternet)))
        let checker = UpdateChecker(fetcher: fetcher, currentVersion: "1.1.0")

        let result = await checker.checkForUpdate()

        XCTAssertEqual(result, .checkFailed)
    }

    func testSemanticVersionComparisonHandlesDifferentComponentCounts() {
        XCTAssertTrue(SemanticVersion.isNewer("v1.2", than: "1.1.9"))
        XCTAssertTrue(SemanticVersion.isNewer("1.1.10", than: "1.1.9"))
        XCTAssertFalse(SemanticVersion.isNewer("1.1.0", than: "1.1.0"))
        XCTAssertFalse(SemanticVersion.isNewer("1.0.9", than: "1.1.0"))
        XCTAssertTrue(SemanticVersion.isNewer("2.0.0", than: "1.9.9"))
    }
}

private struct MockReleaseFetcher: ReleaseFetching {
    let result: Result<GitHubRelease, Error>

    func fetchLatestRelease() async throws -> GitHubRelease {
        try result.get()
    }
}
