//
//  WelcomeSyncPage.swift
//  FlowDown
//

import CloudKit
import os
import SnapKit
import Storage
import UIKit

/// iCloud Sync: a title and one sentence. Shown only where sync can be
/// turned on; Enable iCloud Sync does what turning on the switch in
/// Settings > Data does.
final class WelcomeSyncPage: UIViewController {
    private let flow: WelcomeFlow
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()

    init(flow: WelcomeFlow) {
        self.flow = flow
        super.init(nibName: nil, bundle: nil)
        navigationItem.largeTitleDisplayMode = .never
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    #if DEBUG
        /// Offers the page where it can't be, as on a Simulator, which has
        /// no CloudKit; any other value skips it:
        ///     simulator launch wiki.qaq.flow --env FLOWDOWN_SYNC_FIXTURE=available
        static let fixtureKey = "FLOWDOWN_SYNC_FIXTURE"
    #endif

    /// Only an iCloud account that is there now lets sync be turned on;
    /// an unknown status, an error or no answer in time skips the page.
    static func offersSync(supported: Bool, enabled: Bool, accountStatus: CKAccountStatus?) -> Bool {
        supported && !enabled && accountStatus == .available
    }

    /// Whether to show the page: sync is supported, off, and there is an
    /// iCloud account. CloudKit isn't asked under tests, where the app runs
    /// sync without it.
    static func isOffered(timeout: Duration = .seconds(2)) async -> Bool {
        let environment = ProcessInfo.processInfo.environment
        #if DEBUG
            if let fixture = environment[fixtureKey] {
                return offersSync(supported: true, enabled: SyncEngine.isSyncEnabled, accountStatus: fixture == "available" ? .available : nil)
            }
        #endif
        guard SyncEngine.isCloudSyncSupported, !SyncEngine.isSyncEnabled,
              environment["XCTestConfigurationFilePath"] == nil
        else { return false }
        let status = await accountStatus(timeout: timeout)
        return offersSync(supported: SyncEngine.isCloudSyncSupported, enabled: SyncEngine.isSyncEnabled, accountStatus: status)
    }

    /// The account status, or nil on an error or when CloudKit doesn't
    /// answer within the timeout.
    private static func accountStatus(timeout: Duration) async -> CKAccountStatus? {
        await withCheckedContinuation { continuation in
            let pending = OSAllocatedUnfairLock<CheckedContinuation<CKAccountStatus?, Never>?>(initialState: continuation)
            let resume: @Sendable (CKAccountStatus?) -> Void = { status in
                pending.withLock { value in
                    defer { value = nil }
                    return value
                }?.resume(returning: status)
            }
            Task {
                let status = try? await CKContainer(identifier: CloudKitConfig.containerIdentifier).accountStatus()
                resume(status)
            }
            Task {
                try? await Task.sleep(for: timeout)
                resume(nil)
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = WelcomeStyle.groupedBackground

        titleLabel.text = String(localized: "iCloud Sync")
        titleLabel.font = WelcomeStyle.titleFont
        titleLabel.textColor = WelcomeStyle.titleColor
        titleLabel.textAlignment = .center
        WelcomeStyle.fitOnOneLine(titleLabel)
        titleLabel.accessibilityTraits = .header

        messageLabel.text = String(localized: "Keep your chats in sync across your iPhone, iPad, and Mac.")
        messageLabel.font = WelcomeStyle.subtitleFont
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.textColor = WelcomeStyle.detailColor
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0

        let bar = WelcomeActionBar(
            title: String(localized: "Enable iCloud Sync"),
            secondaryTitle: String(localized: "Not Now"),
            action: { [weak self] in self?.enableSync() },
            secondaryAction: { [weak self] in self?.flow.showCaution() },
        )

        view.addSubview(titleLabel)
        view.addSubview(messageLabel)
        view.addSubview(bar)
        titleLabel.snp.makeConstraints { x in
            x.top.equalTo(view.safeAreaLayoutGuide).offset(24)
            x.leading.trailing.equalTo(view.safeAreaLayoutGuide).inset(32)
        }
        messageLabel.snp.makeConstraints { x in
            x.top.equalTo(titleLabel.snp.bottom).offset(12)
            x.leading.trailing.equalTo(titleLabel)
        }
        bar.snp.makeConstraints { x in
            x.leading.trailing.bottom.equalToSuperview()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    /// The same as turning on Enable iCloud Sync in Settings > Data. The
    /// page then leaves the stack, so Back from the next page goes to
    /// Choose a Model.
    private func enableSync() {
        SyncEngine.setSyncEnabled(true)
        // After re‑enabling, force reload full state before continuing
        Task {
            try? await syncEngine.stopSyncIfNeeded()
            try? await syncEngine.reloadDataForcefully()
        }
        flow.showCaution(replacing: self)
    }
}
