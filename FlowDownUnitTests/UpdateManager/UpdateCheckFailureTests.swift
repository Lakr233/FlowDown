@testable import FlowDown
import Foundation
import Testing

@Suite(.serialized)
struct UpdateCheckFailureTests {
    @Test
    func fetchAvailableUpdate_feedFailure_throwsInsteadOfReportingNoUpdate() async {
        let manager = makeManager(releaseResult: .failure(URLError(.notConnectedToInternet)))

        do {
            let package = try await manager.fetchAvailableUpdate()
            Issue.record("Expected the update check to fail, got \(String(describing: package)).")
        } catch {
            #expect((error as? URLError)?.code == .notConnectedToInternet)
        }
    }

    @Test
    func fetchAvailableUpdate_releaseWithoutBody_throwsInsteadOfReportingNoUpdate() async {
        let manager = makeManager(releaseResult: .success(.init(
            tagName: "9.0.0.1",
            body: nil,
            htmlURL: "https://example.com/missing-body",
            draft: false,
            prerelease: false,
        )))

        do {
            let package = try await manager.fetchAvailableUpdate()
            Issue.record("Expected the update check to fail, got \(String(describing: package)).")
        } catch {
            let nsError = error as NSError
            #expect(nsError.domain == "UpdateManagerError")
            #expect(nsError.code == 1)
        }
    }

    @Test
    func fetchAvailableUpdate_newerRelease_returnsPackage() async throws {
        let manager = makeManager(releaseResult: .success(.init(
            tagName: "1.2.0.4",
            body: "Release notes",
            htmlURL: "https://example.com/newer",
            draft: false,
            prerelease: false,
        )))

        let package = try await manager.fetchAvailableUpdate()

        #expect(package?.tag == "1.2.0.4")
    }

    @Test
    func fetchAvailableUpdate_currentRelease_returnsNil() async throws {
        let manager = makeManager(releaseResult: .success(.init(
            tagName: "1.2.0.3",
            body: "Release notes",
            htmlURL: "https://example.com/current",
            draft: false,
            prerelease: false,
        )))

        let package = try await manager.fetchAvailableUpdate()

        #expect(package == nil)
    }
}

private extension UpdateCheckFailureTests {
    func makeManager(releaseResult: Result<GitHubRelease, Error>) -> UpdateManager {
        UpdateManager(
            currentChannel: .fromGitHub,
            bundleInfoProvider: BundleInfoProviderStub(
                infoDictionary: [
                    "CFBundleShortVersionString": "1.2.0",
                    "CFBundleVersion": "3",
                ],
                appStoreReceiptURL: nil,
            ),
            receiptStateProvider: ReceiptStateProviderStub(),
            releaseFeedClient: ReleaseFeedClientStub(result: releaseResult),
        )
    }

    struct BundleInfoProviderStub: BundleInfoProviding {
        let infoDictionary: [String: Any]?
        let appStoreReceiptURL: URL?
    }

    struct ReceiptStateProviderStub: ReceiptStateProviding {
        func fileExists(atPath _: String) -> Bool {
            false
        }
    }

    struct ReleaseFeedClientStub: ReleaseFeedClient {
        let result: Result<GitHubRelease, Error>

        func latestGitHubRelease() async throws -> GitHubRelease {
            try result.get()
        }
    }
}
