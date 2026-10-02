@testable import FlowDown
import Foundation
import Testing

@Suite(.serialized)
struct UpdateManagerTests {
    @Test
    func `resolveCurrentChannel respects receipt presence and platform support`() {
        let receiptURL = URL(fileURLWithPath: "/tmp/flowdown-receipt")
        let bundleInfo = BundleInfoProviderStub(
            infoDictionary: [:],
            appStoreReceiptURL: receiptURL,
        )

        let appleChannel = UpdateManager.resolveCurrentChannel(
            supportsGitHubDistribution: true,
            bundleInfoProvider: bundleInfo,
            receiptStateProvider: ReceiptStateProviderStub(existingPaths: [receiptURL.path]),
        )
        let githubChannel = UpdateManager.resolveCurrentChannel(
            supportsGitHubDistribution: true,
            bundleInfoProvider: bundleInfo,
            receiptStateProvider: ReceiptStateProviderStub(existingPaths: []),
        )
        let unsupportedChannel = UpdateManager.resolveCurrentChannel(
            supportsGitHubDistribution: false,
            bundleInfoProvider: bundleInfo,
            receiptStateProvider: ReceiptStateProviderStub(existingPaths: []),
        )

        #expect(appleChannel == .fromApple)
        #expect(githubChannel == .fromGitHub)
        #expect(unsupportedChannel == .fromApple)
    }

    @Test
    func `canCheckForUpdates is enabled only for github builds`() {
        let githubManager = makeManager(
            currentChannel: .fromGitHub,
            version: "1.2.0",
            build: "3",
        )
        let appleManager = makeManager(
            currentChannel: .fromApple,
            version: "1.2.0",
            build: "3",
        )

        #expect(githubManager.canCheckForUpdates)
        #expect(!appleManager.canCheckForUpdates)
    }

    @Test
    func `newestPackage selects the highest available version`() throws {
        let manager = makeManager(
            currentChannel: .fromGitHub,
            version: "1.0.0",
            build: "1",
        )

        let package = try manager.newestPackage(from: [
            .init(tag: "1.0.0.9", downloadURL: #require(URL(string: "https://example.com/1"))),
            .init(tag: "1.10.0.1", downloadURL: #require(URL(string: "https://example.com/2"))),
            .init(tag: "1.2.0.5", downloadURL: #require(URL(string: "https://example.com/3"))),
        ])

        #expect(package?.tag == "1.10.0.1")
    }

    @Test
    func `updatePackage ignores older and equal versions while allowing newer releases`() throws {
        let manager = makeManager(
            currentChannel: .fromGitHub,
            version: "1.2.0",
            build: "3",
        )

        let older = try DistributionChannel.RemotePackage(
            tag: "1.2.0.2",
            downloadURL: #require(URL(string: "https://example.com/older")),
        )
        let equal = try DistributionChannel.RemotePackage(
            tag: "1.2.0.3",
            downloadURL: #require(URL(string: "https://example.com/equal")),
        )
        let newer = try DistributionChannel.RemotePackage(
            tag: "1.2.0.4",
            downloadURL: #require(URL(string: "https://example.com/newer")),
        )

        #expect(manager.updatePackage(from: older) == nil)
        #expect(manager.updatePackage(from: equal) == nil)
        #expect(manager.updatePackage(from: newer) == newer)
    }

    @Test
    func `github release feed client parses the latest release payload`() async throws {
        let payload = """
        {
          "tag_name": "2.0.0.1",
          "body": "Release notes",
          "html_url": "https://example.com/download",
          "draft": false,
          "prerelease": false
        }
        """
        let responseURL = try #require(URL(string: "https://example.com"))
        let session = try URLSessionStub(result: .success((
            Data(payload.utf8),
            #require(HTTPURLResponse(
                url: responseURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil,
            )),
        )))
        let client = try GitHubReleaseFeedClient(
            session: session,
            latestReleaseURL: #require(URL(string: "https://example.com/releases/latest")),
        )

        let release = try await client.latestGitHubRelease()

        #expect(release.tagName == "2.0.0.1")
        #expect(release.body == "Release notes")
        #expect(release.htmlURL == "https://example.com/download")
        #expect(!release.draft)
        #expect(!release.prerelease)
    }

    @Test
    func `github release filtering rejects draft prerelease and invalid payloads`() async throws {
        let validPackages = try await DistributionChannel.fromGitHub.getRemoteVersion(
            releaseFeedClient: ReleaseFeedClientStub(result: .success(.init(
                tagName: "2.0.0.1",
                body: "Release notes",
                htmlURL: "https://example.com/download",
                draft: false,
                prerelease: false,
            ))),
        )
        #expect(try validPackages == [
            .init(
                tag: "2.0.0.1",
                downloadURL: #require(URL(string: "https://example.com/download")),
            ),
        ])

        await assertGitHubReleaseRejected(
            release: .init(
                tagName: "2.0.0.2",
                body: "Draft build",
                htmlURL: "https://example.com/draft",
                draft: true,
                prerelease: false,
            ),
        )
        await assertGitHubReleaseRejected(
            release: .init(
                tagName: "2.0.0.3",
                body: "Prerelease build",
                htmlURL: "https://example.com/prerelease",
                draft: false,
                prerelease: true,
            ),
        )
        await assertGitHubReleaseRejected(
            release: .init(
                tagName: "2.0.0.4",
                body: nil,
                htmlURL: "https://example.com/missing-body",
                draft: false,
                prerelease: false,
            ),
        )
    }
}

private extension UpdateManagerTests {
    func makeManager(
        currentChannel: DistributionChannel,
        version: String,
        build: String,
    ) -> UpdateManager {
        UpdateManager(
            currentChannel: currentChannel,
            bundleInfoProvider: BundleInfoProviderStub(
                infoDictionary: [
                    "CFBundleShortVersionString": version,
                    "CFBundleVersion": build,
                ],
                appStoreReceiptURL: nil,
            ),
            receiptStateProvider: ReceiptStateProviderStub(existingPaths: []),
            releaseFeedClient: ReleaseFeedClientStub(result: .success(.init(
                tagName: "0.0.0.0",
                body: "Unused",
                htmlURL: "https://example.com/unused",
                draft: false,
                prerelease: false,
            ))),
        )
    }

    func assertGitHubReleaseRejected(release: GitHubRelease) async {
        do {
            _ = try await DistributionChannel.fromGitHub.getRemoteVersion(
                releaseFeedClient: ReleaseFeedClientStub(result: .success(release)),
            )
            Issue.record("Expected release \(release.tagName) to be rejected.")
        } catch {
            let nsError = error as NSError
            #expect(nsError.domain == "UpdateManagerError")
            #expect(nsError.code == 1)
        }
    }

    struct BundleInfoProviderStub: BundleInfoProviding {
        let infoDictionary: [String: Any]?
        let appStoreReceiptURL: URL?
    }

    struct ReceiptStateProviderStub: ReceiptStateProviding {
        let existingPaths: Set<String>

        init(existingPaths: [String]) {
            self.existingPaths = Set(existingPaths)
        }

        func fileExists(atPath path: String) -> Bool {
            existingPaths.contains(path)
        }
    }

    struct URLSessionStub: URLSessioning {
        let result: Result<(Data, URLResponse), Error>

        func data(from _: URL) async throws -> (Data, URLResponse) {
            try result.get()
        }
    }

    struct ReleaseFeedClientStub: ReleaseFeedClient {
        let result: Result<GitHubRelease, Error>

        func latestGitHubRelease() async throws -> GitHubRelease {
            try result.get()
        }
    }
}
