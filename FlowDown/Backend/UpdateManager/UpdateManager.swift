import AlertController
import Combine
import DpkgVersion
import Foundation
import UIKit

protocol URLSessioning {
    func data(from url: URL) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessioning {}

protocol BundleInfoProviding {
    var infoDictionary: [String: Any]? { get }
    var appStoreReceiptURL: URL? { get }
}

extension Bundle: BundleInfoProviding {}

protocol ReceiptStateProviding {
    func fileExists(atPath path: String) -> Bool
}

extension FileManager: ReceiptStateProviding {}

protocol ReleaseFeedClient {
    func latestGitHubRelease() async throws -> GitHubRelease
}

struct GitHubRelease: Equatable, Decodable {
    let tagName: String
    let body: String?
    let htmlURL: String
    let draft: Bool
    let prerelease: Bool

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case body
        case htmlURL = "html_url"
        case draft
        case prerelease
    }
}

struct GitHubReleaseFeedClient: ReleaseFeedClient {
    let session: URLSessioning
    let latestReleaseURL: URL

    init(
        session: URLSessioning = URLSession.shared,
        latestReleaseURL: URL = URL(string: "https://api.github.com/repos/Lakr233/FlowDown/releases/latest")!,
    ) {
        self.session = session
        self.latestReleaseURL = latestReleaseURL
    }

    func latestGitHubRelease() async throws -> GitHubRelease {
        let (data, _) = try await session.data(from: latestReleaseURL)
        guard let release = try? JSONDecoder().decode(GitHubRelease.self, from: data) else {
            throw NSError(domain: "UpdateManagerError", code: 1, userInfo: [
                NSLocalizedDescriptionKey: String(localized: "Failed to parse release information."),
            ])
        }
        return release
    }
}

enum DistributionChannel: String, Equatable, Hashable {
    case fromApple
    case fromGitHub
}

class UpdateManager: NSObject {
    static let shared = UpdateManager()

    let currentChannel: DistributionChannel
    private weak var anchorView: UIView?
    private let bundleInfoProvider: BundleInfoProviding
    private let receiptStateProvider: ReceiptStateProviding
    private let releaseFeedClient: ReleaseFeedClient

    var canCheckForUpdates: Bool {
        // Check if the current channel supports update checking
        [.fromGitHub].contains(currentChannel)
    }

    override private convenience init() {
        self.init(
            bundleInfoProvider: Bundle.main,
            receiptStateProvider: FileManager.default,
            releaseFeedClient: GitHubReleaseFeedClient(),
        )
    }

    init(
        currentChannel: DistributionChannel? = nil,
        bundleInfoProvider: BundleInfoProviding,
        receiptStateProvider: ReceiptStateProviding,
        releaseFeedClient: ReleaseFeedClient,
    ) {
        self.bundleInfoProvider = bundleInfoProvider
        self.receiptStateProvider = receiptStateProvider
        self.releaseFeedClient = releaseFeedClient
        if let currentChannel {
            self.currentChannel = currentChannel
        } else {
            self.currentChannel = Self.resolveCurrentChannel(
                supportsGitHubDistribution: {
                    #if targetEnvironment(macCatalyst)
                        true
                    #else
                        false
                    #endif
                }(),
                bundleInfoProvider: bundleInfoProvider,
                receiptStateProvider: receiptStateProvider,
            )
        }
        Logger.app.infoFile("UpdateManager initialized with channel: \(self.currentChannel)")
        super.init()
    }

    static func resolveCurrentChannel(
        supportsGitHubDistribution: Bool,
        bundleInfoProvider: BundleInfoProviding,
        receiptStateProvider: ReceiptStateProviding,
    ) -> DistributionChannel {
        guard supportsGitHubDistribution else {
            return .fromApple
        }

        if let receiptURL = bundleInfoProvider.appStoreReceiptURL,
           receiptStateProvider.fileExists(atPath: receiptURL.path)
        {
            return .fromApple
        } else {
            return .fromGitHub
        }
    }

    var bundleVersion: String {
        let version = bundleInfoProvider.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
        let build = bundleInfoProvider.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(version).\(build)"
    }

    func anchor(_ view: UIView) {
        anchorView = view
    }

    func performUpdateCheckFromUI() {
        guard let controller = anchorView?.parentViewController else {
            Logger.app.errorFile("no anchor view set for UpdateManager.")
            return
        }
        Logger.app.infoFile("checking for updates from \(bundleVersion)...")
        guard [.fromGitHub].contains(currentChannel) else {
            Logger.app.errorFile("Update check is not supported for the current distribution channel.")
            return
        }

        func completion(package: DistributionChannel.RemotePackage?) {
            Task { @MainActor in
                if let package {
                    self.presentUpdateAlert(controller: controller, package: package)
                } else {
                    Indicator.present(
                        title: "No Update Available",
                        preset: .done,
                        referencingView: controller.view,
                    )
                }
            }
        }

        Indicator.progress(
            title: "Checking for Updates",
            controller: controller,
        ) { completionHandler in
            var package: DistributionChannel.RemotePackage?
            do {
                let packages = try await self.currentChannel.getRemoteVersion(
                    releaseFeedClient: self.releaseFeedClient,
                )
                package = self.newestPackage(from: packages)
                package = self.updatePackage(from: package)
                Logger.app.infoFile("remote packages: \(packages)")
            } catch {
                Logger.app.errorFile("failed to check for updates: \(error.localizedDescription)")
            }
            await completionHandler {
                completion(package: package)
            }
        }
    }

    func updatePackage(from remotePackage: DistributionChannel.RemotePackage?) -> DistributionChannel.RemotePackage? {
        guard let remotePackage else { return nil }
        let compare = Version.compare(remotePackage.tag, bundleVersion)
        Logger.app.infoFile("comparing \(remotePackage.tag) and \(bundleVersion) result \(compare)")
        guard compare > 0 else { return nil }
        return remotePackage
    }

    func newestPackage(from list: [DistributionChannel.RemotePackage]) -> DistributionChannel.RemotePackage? {
        list.max { Version.compare($0.tag, $1.tag) < 0 }
    }

    private func presentUpdateAlert(controller: UIViewController, package: DistributionChannel.RemotePackage) {
        let alert = AlertViewController(
            title: "Update Available",
            message: "A new version \(package.tag) is available. Would you like to download it?",
        ) { context in
            context.allowSimpleDispose()
            context.addAction(title: "Cancel") {
                context.dispose()
            }
            context.addAction(title: "Download", attribute: .accent) {
                context.dispose {
                    UIApplication.shared.open(package.downloadURL, options: [:])
                }
            }
        }
        controller.present(alert, animated: true)
    }
}

extension DistributionChannel {
    struct RemotePackage: Equatable {
        let tag: String
        let downloadURL: URL
    }

    func getRemoteVersion(releaseFeedClient: ReleaseFeedClient = GitHubReleaseFeedClient()) async throws -> [RemotePackage] {
        switch self {
        case .fromApple:
            return []
        case .fromGitHub:
            let release = try await releaseFeedClient.latestGitHubRelease()
            guard release.body != nil,
                  !release.draft,
                  !release.prerelease,
                  let downloadPageURL = URL(string: release.htmlURL)
            else {
                throw NSError(domain: "UpdateManagerError", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: String(localized: "Failed to parse release information."),
                ])
            }
            Logger.app.infoFile("latest release version: \(release.tagName), url: \(release.htmlURL)")
            return [.init(tag: release.tagName, downloadURL: downloadPageURL)]
        }
    }
}
