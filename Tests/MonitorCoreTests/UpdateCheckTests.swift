import Foundation
import Testing
@testable import MonitorCore

@Suite("Semantic versions")
struct SemanticVersionTests {
    @Test func parsesReleasesAndTags() {
        #expect(SemanticVersion("0.1.0") == SemanticVersion(major: 0, minor: 1, patch: 0))
        #expect(SemanticVersion("v1.2.3") == SemanticVersion(major: 1, minor: 2, patch: 3))
        #expect(SemanticVersion("V2.0.0") == SemanticVersion(major: 2, minor: 0, patch: 0))
        #expect(SemanticVersion("1.2") == SemanticVersion(major: 1, minor: 2, patch: 0))
        #expect(SemanticVersion("3") == SemanticVersion(major: 3, minor: 0, patch: 0))
    }

    @Test func parsesPrereleasesAndIgnoresBuildMetadata() {
        #expect(SemanticVersion("1.0.0-beta.2")?.prerelease == ["beta", "2"])
        #expect(SemanticVersion("1.0.0+build.5") == SemanticVersion(major: 1, minor: 0, patch: 0))
        #expect(SemanticVersion("1.0.0-rc.1+abc")?.prerelease == ["rc", "1"])
    }

    @Test(arguments: ["", "v", "1.x", "1..2", "1.2.3.4", "1.0.0-", "1.0.0-be ta", "1.0.0-a..b",
                      "-1.0", " 1.0.0", "1.0.0 ", "latest", "١.٢.٣"])
    func rejectsMalformedVersions(_ text: String) {
        #expect(SemanticVersion(text) == nil)
    }

    @Test func roundTripsThroughDescription() {
        for text in ["0.1.0", "10.20.30", "1.0.0-beta.2"] {
            #expect(SemanticVersion(text)?.description == text)
        }
        #expect(SemanticVersion("v1.2")?.description == "1.2.0")
    }

    @Test func ordersNumericallyNotAlphabetically() throws {
        let a = try #require(SemanticVersion("0.2.0"))
        let b = try #require(SemanticVersion("0.10.0"))
        let older = try #require(SemanticVersion("0.1.9"))
        let major = try #require(SemanticVersion("1.0.0"))
        #expect(a < b)
        #expect(older < a)
        #expect(major > b)
    }

    @Test func ordersPrereleasesLikeTheSpecification() throws {
        // The example from semver.org, section 11.
        let ordered = try ["1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-alpha.beta", "1.0.0-beta",
                           "1.0.0-beta.2", "1.0.0-beta.11", "1.0.0-rc.1", "1.0.0"]
            .map { try #require(SemanticVersion($0)) }
        for (earlier, later) in zip(ordered, ordered.dropFirst()) {
            #expect(earlier < later, "\(earlier) < \(later)")
            #expect(!(later < earlier), "not \(later) < \(earlier)")
        }
    }

    @Test func equalVersionsAreNotOrdered() throws {
        let a = try #require(SemanticVersion("1.2"))
        let b = try #require(SemanticVersion("v1.2.0"))
        #expect(a == b)
        #expect(!(a < b) && !(b < a))
    }

    @Test func appVersionParses() {
        #expect(SemanticVersion(AppVersion.string) != nil)
        #expect(UpdateCheck.currentVersion.description == AppVersion.string)
    }
}

@Suite("Update check")
struct UpdateCheckTests {
    private let current = SemanticVersion(major: 0, minor: 2, patch: 0)

    /// The fields GitHub's "latest release" endpoint returns, trimmed. The html_url points
    /// elsewhere on purpose: the release page must come from the version, not from the reply.
    private func reply(tag: String, draft: Bool = false, prerelease: Bool = false) -> Data {
        Data("""
        {"url": "https://api.github.com/repos/stalwartquintessence/candela/releases/1",
         "html_url": "https://example.com/not-candela",
         "tag_name": "\(tag)", "name": "Candela", "draft": \(draft), "prerelease": \(prerelease),
         "published_at": "2026-11-09T21:50:54Z", "assets": []}
        """.utf8)
    }

    @Test func newerReleaseIsAvailableWithItsGitHubPage() {
        let result = UpdateCheck.result(statusCode: 200, body: reply(tag: "v0.3.0"), current: current)
        let page = URL(string: "https://github.com/stalwartquintessence/candela/releases/tag/v0.3.0")!
        #expect(result == .available(SemanticVersion(major: 0, minor: 3, patch: 0), page: page))
    }

    @Test(arguments: ["v0.2.0", "v0.1.0", "0.2", "v0.2.0-rc.1"])
    func sameOrOlderReleaseIsUpToDate(_ tag: String) {
        #expect(UpdateCheck.result(statusCode: 200, body: reply(tag: tag), current: current) == .upToDate(current))
    }

    @Test func draftsAndPrereleasesAreIgnored() {
        #expect(UpdateCheck.result(statusCode: 200, body: reply(tag: "v9.0.0", draft: true), current: current) == .upToDate(current))
        #expect(UpdateCheck.result(statusCode: 200, body: reply(tag: "v9.0.0", prerelease: true), current: current) == .upToDate(current))
    }

    @Test func runningAPrereleaseSeesItsRelease() throws {
        let beta = try #require(SemanticVersion("0.3.0-beta.1"))
        let result = UpdateCheck.result(statusCode: 200, body: reply(tag: "v0.3.0"), current: beta)
        #expect(result == .available(SemanticVersion(major: 0, minor: 3, patch: 0),
                                     page: UpdateCheck.releasePage(for: SemanticVersion(major: 0, minor: 3, patch: 0))))
    }

    @Test func unreadableRepliesFail() {
        #expect(UpdateCheck.result(statusCode: 200, body: Data("<html>".utf8), current: current) == .failed(.unreadableReply))
        #expect(UpdateCheck.result(statusCode: 200, body: Data("{}".utf8), current: current) == .failed(.unreadableReply))
        #expect(UpdateCheck.result(statusCode: 200, body: reply(tag: "latest"), current: current) == .failed(.unreadableReply))
    }

    @Test func httpStatusesMapToFailures() {
        #expect(UpdateCheck.result(statusCode: 404, body: Data(), current: current) == .failed(.noReleases))
        #expect(UpdateCheck.result(statusCode: 403, body: Data(), current: current) == .failed(.rateLimited))
        #expect(UpdateCheck.result(statusCode: 429, body: Data(), current: current) == .failed(.rateLimited))
        #expect(UpdateCheck.result(statusCode: 500, body: Data(), current: current) == .failed(.unexpectedStatus(500)))
    }

    @Test func automaticCheckRunsOnceADay() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(UpdateCheck.isDue(lastCheck: nil, now: now))
        #expect(!UpdateCheck.isDue(lastCheck: now, now: now))
        #expect(!UpdateCheck.isDue(lastCheck: now.addingTimeInterval(-23 * 3600), now: now))
        #expect(UpdateCheck.isDue(lastCheck: now.addingTimeInterval(-24 * 3600), now: now))
        #expect(UpdateCheck.isDue(lastCheck: now.addingTimeInterval(-30 * 24 * 3600), now: now))
        // The clock was set back.
        #expect(UpdateCheck.isDue(lastCheck: now.addingTimeInterval(3600), now: now))
    }

    @Test func eachVersionIsAnnouncedOnce() {
        let next = SemanticVersion(major: 0, minor: 3, patch: 0)
        #expect(UpdateCheck.shouldAnnounce(next, lastAnnounced: nil))
        #expect(UpdateCheck.shouldAnnounce(next, lastAnnounced: "0.2.1"))
        #expect(!UpdateCheck.shouldAnnounce(next, lastAnnounced: "0.3.0"))
        #expect(!UpdateCheck.shouldAnnounce(next, lastAnnounced: "0.4.0"))
        #expect(UpdateCheck.shouldAnnounce(next, lastAnnounced: "garbage"))
    }

    @Test func requestsGoToThisRepository() {
        #expect(UpdateCheck.latestReleaseURL.absoluteString
            == "https://api.github.com/repos/stalwartquintessence/candela/releases/latest")
    }
}
