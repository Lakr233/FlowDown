//
//  WelcomeSyncPage.swift
//  FlowDown
//

import CloudKit
import SnapKit
import Storage
import UIKit

/// iCloud Sync: a title and one sentence. Enable iCloud Sync does what
/// turning on the switch in Settings > Data does; where sync is on already,
/// or can't run, the page only says so.
final class WelcomeSyncPage: UIViewController {
    enum State: String {
        /// Sync can be turned on: Enable iCloud Sync, or Not Now.
        case available
        case on
        /// No iCloud account on this device.
        case notSetUp
        /// No CloudKit sync here: the Simulator, or an older system.
        case unsupported
    }

    private let flow: WelcomeFlow
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private var actionBar: WelcomeActionBar?
    private var state: State

    init(flow: WelcomeFlow) {
        self.flow = flow
        state = Self.initialState
        super.init(nibName: nil, bundle: nil)
        navigationItem.largeTitleDisplayMode = .never
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    #if DEBUG
        /// Shows a state where it can't happen, as on a Simulator, which has
        /// no CloudKit:
        ///     simulator launch wiki.qaq.flow --env FLOWDOWN_SYNC_FIXTURE=notSetUp
        static let fixtureKey = "FLOWDOWN_SYNC_FIXTURE"
    #endif

    private static var initialState: State {
        #if DEBUG
            if let fixture = ProcessInfo.processInfo.environment[fixtureKey].flatMap(State.init(rawValue:)) {
                return fixture
            }
        #endif
        if !SyncEngine.isCloudSyncSupported { return .unsupported }
        return SyncEngine.isSyncEnabled ? .on : .available
    }

    /// Whether to ask CloudKit about the account: not with a fixture, and
    /// not under tests, where the app runs sync without CloudKit.
    private static var asksForAccount: Bool {
        let environment = ProcessInfo.processInfo.environment
        #if DEBUG
            if environment[fixtureKey] != nil { return false }
        #endif
        return environment["XCTestConfigurationFilePath"] == nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = WelcomeStyle.groupedBackground

        titleLabel.text = String(localized: "iCloud Sync")
        titleLabel.font = WelcomeStyle.titleFont
        titleLabel.textColor = WelcomeStyle.titleColor
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.accessibilityTraits = .header

        messageLabel.font = WelcomeStyle.subtitleFont
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.textColor = WelcomeStyle.detailColor
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0

        view.addSubview(titleLabel)
        view.addSubview(messageLabel)
        titleLabel.snp.makeConstraints { x in
            x.top.equalTo(view.safeAreaLayoutGuide).offset(24)
            x.leading.trailing.equalTo(view.safeAreaLayoutGuide).inset(32)
        }
        messageLabel.snp.makeConstraints { x in
            x.top.equalTo(titleLabel.snp.bottom).offset(12)
            x.leading.trailing.equalTo(titleLabel)
        }

        render()
        if state == .available, Self.asksForAccount {
            checkAccount()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        // back from the next page after turning sync on
        if state == .available, SyncEngine.isSyncEnabled {
            state = .on
            render()
        }
    }

    private func render() {
        switch state {
        case .available:
            messageLabel.text = String(localized: "Keep your chats in sync across your iPhone, iPad, and Mac.")
        case .on:
            messageLabel.text = String(localized: "iCloud Sync is on.")
        case .notSetUp:
            messageLabel.text = String(localized: "iCloud isn't set up on this device.")
        case .unsupported:
            messageLabel.text = String(localized: "iCloud sync is not available on this iOS version.")
        }

        actionBar?.removeFromSuperview()
        let bar = if state == .available {
            WelcomeActionBar(
                title: String(localized: "Enable iCloud Sync"),
                secondaryTitle: String(localized: "Not Now"),
                action: { [weak self] in self?.enableSync() },
                secondaryAction: { [weak self] in self?.flow.showCaution() },
            )
        } else {
            WelcomeActionBar(title: String(localized: "Continue")) { [weak self] in
                self?.flow.showCaution()
            }
        }
        view.addSubview(bar)
        bar.snp.makeConstraints { x in
            x.leading.trailing.bottom.equalToSuperview()
        }
        actionBar = bar
    }

    /// Sync needs an iCloud account; without one the page says so instead
    /// of offering to turn sync on. Only asked where sync can run, since
    /// the Simulator has no CloudKit.
    private func checkAccount() {
        Task { [weak self] in
            let status = try? await CKContainer(identifier: CloudKitConfig.containerIdentifier).accountStatus()
            guard let self, state == .available,
                  status == .noAccount || status == .restricted
            else { return }
            state = .notSetUp
            render()
        }
    }

    /// The same as turning on Enable iCloud Sync in Settings > Data.
    private func enableSync() {
        SyncEngine.setSyncEnabled(true)
        // After re‑enabling, force reload full state before continuing
        Task {
            try? await syncEngine.stopSyncIfNeeded()
            try? await syncEngine.reloadDataForcefully()
        }
        flow.showCaution()
    }
}
