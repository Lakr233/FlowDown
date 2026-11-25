import CloudKit
@testable import FlowDown
import Foundation
import Storage
import Testing

struct WelcomeExperienceTests {
    private func makeDefaults() throws -> UserDefaults {
        let suite = "WelcomeExperienceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test
    func `a new user sees the welcome at launch`() throws {
        let defaults = try makeDefaults()
        #expect(WelcomeExperience.shouldPresentAtLaunch(defaults: defaults, hasExistingModel: { false }))
        #expect(WelcomeExperience.shouldPresent(defaults: defaults))
    }

    @Test
    func `a user who has seen the welcome does not see it again`() throws {
        let defaults = try makeDefaults()
        defaults.set("0", forKey: WelcomeExperience.seenVersionKey)
        #expect(!WelcomeExperience.shouldPresentAtLaunch(defaults: defaults, hasExistingModel: { false }))
    }

    @Test
    func `a user with a model skips the welcome and it is recorded as seen`() throws {
        let defaults = try makeDefaults()
        #expect(!WelcomeExperience.shouldPresentAtLaunch(defaults: defaults, hasExistingModel: { true }))
        #expect(defaults.string(forKey: WelcomeExperience.seenVersionKey) == WelcomeExperience.currentVersion)
        #expect(!WelcomeExperience.shouldPresent(defaults: defaults))
    }

    @Test
    func `models are not checked once the welcome has been seen`() throws {
        let defaults = try makeDefaults()
        WelcomeExperience.markPresented(defaults: defaults)
        var checked = false
        let result = WelcomeExperience.shouldPresentAtLaunch(defaults: defaults) {
            checked = true
            return false
        }
        #expect(!result)
        #expect(!checked)
    }

    @Test
    func `finishing the welcome records it as seen`() throws {
        let defaults = try makeDefaults()
        WelcomeExperience.markPresented(defaults: defaults)
        #expect(!WelcomeExperience.shouldPresent(defaults: defaults))
        #expect(!WelcomeExperience.shouldPresentAtLaunch(defaults: defaults, hasExistingModel: { false }))
    }

    // MARK: - Blank Cloud Models

    @Test
    func `a cloud model with nothing filled in is blank`() {
        #expect(WelcomeExperience.isBlank(CloudModel(deviceId: "test")))
        #expect(!WelcomeExperience.isBlank(CloudModel(deviceId: "test", model_identifier: "gpt-4o")))
        #expect(!WelcomeExperience.isBlank(CloudModel(deviceId: "test", endpoint: "https://example.com/v1")))
        #expect(!WelcomeExperience.isBlank(CloudModel(deviceId: "test", token: "sk-test")))
        #expect(!WelcomeExperience.isBlank(CloudModel(deviceId: "test", name: "Mine")))
    }

    @Test
    func `a blank cloud model does not count as an existing model`() {
        let blank = CloudModel(deviceId: "test")
        let filled = CloudModel(deviceId: "test", model_identifier: "gpt-4o")
        #expect(!WelcomeExperience.hasExistingModel(cloudModels: [], localModelCount: 0))
        #expect(!WelcomeExperience.hasExistingModel(cloudModels: [blank], localModelCount: 0))
        #expect(WelcomeExperience.hasExistingModel(cloudModels: [blank, filled], localModelCount: 0))
        #expect(WelcomeExperience.hasExistingModel(cloudModels: [blank], localModelCount: 1))
    }

    @Test
    func `a pending cloud model left blank is removed and forgotten`() throws {
        let defaults = try makeDefaults()
        let model = CloudModel(deviceId: "test")
        WelcomeExperience.setPendingCloudModel(model.id, defaults: defaults)
        var removed: [CloudModel.ID] = []
        let result = WelcomeExperience.discardBlankPendingCloudModel(
            defaults: defaults,
            lookup: { $0 == model.id ? model : nil },
            remove: { removed.append($0) },
        )
        #expect(result)
        #expect(removed == [model.id])
        #expect(WelcomeExperience.pendingCloudModel(defaults: defaults) == nil)
    }

    @Test
    func `a pending cloud model filled in stays and is forgotten`() throws {
        let defaults = try makeDefaults()
        let model = CloudModel(deviceId: "test", model_identifier: "gpt-4o")
        WelcomeExperience.setPendingCloudModel(model.id, defaults: defaults)
        var removed: [CloudModel.ID] = []
        let result = WelcomeExperience.discardBlankPendingCloudModel(
            defaults: defaults,
            lookup: { $0 == model.id ? model : nil },
            remove: { removed.append($0) },
        )
        #expect(!result)
        #expect(removed.isEmpty)
        #expect(WelcomeExperience.pendingCloudModel(defaults: defaults) == nil)
    }

    @Test
    func `nothing is removed without a pending cloud model`() throws {
        let defaults = try makeDefaults()
        var looked = false
        let result = WelcomeExperience.discardBlankPendingCloudModel(
            defaults: defaults,
            lookup: { _ in
                looked = true
                return CloudModel(deviceId: "test")
            },
            remove: { _ in Issue.record("nothing to remove") },
        )
        #expect(!result)
        #expect(!looked)
    }

    // MARK: - iCloud Sync Page

    @Test
    @MainActor
    func `the sync page is offered only when sync can be turned on`() {
        #expect(WelcomeSyncPage.offersSync(supported: true, enabled: false, accountStatus: .available))
        #expect(!WelcomeSyncPage.offersSync(supported: true, enabled: true, accountStatus: .available))
        #expect(!WelcomeSyncPage.offersSync(supported: false, enabled: false, accountStatus: .available))
    }

    @Test(arguments: [CKAccountStatus.noAccount, .restricted, .couldNotDetermine, .temporarilyUnavailable])
    @MainActor
    func `the sync page is skipped without an iCloud account`(status: CKAccountStatus) {
        #expect(!WelcomeSyncPage.offersSync(supported: true, enabled: false, accountStatus: status))
    }

    @Test
    @MainActor
    func `the sync page is skipped when the account check fails or times out`() {
        #expect(!WelcomeSyncPage.offersSync(supported: true, enabled: false, accountStatus: nil))
    }

    @Test
    @MainActor
    func `the sync page is not offered under tests`() async {
        #expect(await !WelcomeSyncPage.isOffered(timeout: .milliseconds(100)))
    }

    // MARK: - Choose a Model

    @Test
    @MainActor
    func `the Apple Intelligence footer gives one reason`() {
        #expect(WelcomeModelPage.footerReason(local: "Local", privateCloudCompute: "PCC") == "Local")
        #expect(WelcomeModelPage.footerReason(local: nil, privateCloudCompute: "PCC") == "PCC")
        #expect(WelcomeModelPage.footerReason(local: "", privateCloudCompute: "PCC") == "PCC")
        #expect(WelcomeModelPage.footerReason(local: "Local", privateCloudCompute: nil) == "Local")
        #expect(WelcomeModelPage.footerReason(local: nil, privateCloudCompute: nil) == nil)
    }
}
