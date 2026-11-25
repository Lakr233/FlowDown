@testable import FlowDown
import Foundation
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
}
