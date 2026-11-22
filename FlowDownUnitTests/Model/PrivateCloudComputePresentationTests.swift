@testable import ChatClientKit
import ConfigurableKit
@testable import FlowDown
import Foundation
import Testing

/// What the app says about Private Cloud Compute in each state. The tests
/// run on any OS: the presentation reads only the FoundationModels-free state.
struct PrivateCloudComputePresentationTests {
    private let fixedTime: (Date) -> String = { _ in "3:00 PM" }

    @Test
    func `model menu lists the cloud model only where it could run`() {
        #expect(PrivateCloudComputePresentation.isListedInModelMenu(.available))
        #expect(PrivateCloudComputePresentation.isListedInModelMenu(.unavailable(.systemNotReady)))
        #expect(PrivateCloudComputePresentation.isListedInModelMenu(.unavailable(.other("x"))))
        #expect(!PrivateCloudComputePresentation.isListedInModelMenu(.unavailable(.operatingSystemTooOld)))
        #expect(!PrivateCloudComputePresentation.isListedInModelMenu(.unavailable(.deviceNotEligible)))
    }

    @Test
    func `a copy without the entitlement never lists the cloud model`() {
        #expect(!PrivateCloudComputePresentation.isListedInModelMenu(.available, isEntitled: false))
        #expect(!PrivateCloudComputePresentation.isListedInModelMenu(.unavailable(.systemNotReady), isEntitled: false))
        #expect(PrivateCloudComputePresentation.isListedInModelMenu(.available, isEntitled: true))
    }

    @Test
    func `a copy without the entitlement points to the App Store`() {
        let appStore = String(localized: "Available only in FlowDown from the App Store.")
        #expect(PrivateCloudComputePresentation.notEntitledText == appStore)
        #expect(PrivateCloudComputePresentation.unavailableText(for: .available, isEntitled: false) == appStore)
        #expect(PrivateCloudComputePresentation.unavailableText(for: .unavailable(.systemNotReady), isEntitled: false) == appStore)
        #expect(PrivateCloudComputePresentation.unavailableText(for: .unavailable(.other("x")), isEntitled: false) == appStore)
        // The App Store build wouldn't run there either, so the OS or
        // device reason stays.
        #expect(
            PrivateCloudComputePresentation.unavailableText(
                for: .unavailable(.operatingSystemTooOld), isEntitled: false, isMacCatalyst: true,
            ) == String(localized: "Requires macOS 27 or later."),
        )
        #expect(
            PrivateCloudComputePresentation.unavailableText(for: .unavailable(.deviceNotEligible), isEntitled: false)
                == String(localized: "Not available on this device."),
        )
        // Entitled copies read as before.
        #expect(PrivateCloudComputePresentation.unavailableText(for: .available, isEntitled: true) == nil)
        #expect(
            PrivateCloudComputePresentation.unavailableText(for: .unavailable(.deviceNotEligible), isEntitled: true)
                == String(localized: "Not available on this device."),
        )
    }

    @Test
    func `a request from a copy without the entitlement fails with the App Store hint`() {
        let center = PrivateCloudComputeCenter.shared
        #expect(
            center.failureText(from: PrivateCloudComputeCenter.NotEntitledError())
                == String(localized: "Available only in FlowDown from the App Store."),
        )
        #expect(center.failure(from: PrivateCloudComputeCenter.NotEntitledError()) == nil)
    }

    @Test
    func `iOS builds are taken as entitled`() {
        #if !targetEnvironment(macCatalyst)
            #expect(PrivateCloudComputeEntitlement.isGranted)
            #expect(PrivateCloudComputeCenter.shared.isEntitled)
        #endif
    }

    @Test
    func `unavailable reasons read as plain sentences`() {
        #expect(
            PrivateCloudComputePresentation.unavailableText(for: .operatingSystemTooOld, isMacCatalyst: false)
                == String(localized: "Requires iOS 27 or later."),
        )
        #expect(
            PrivateCloudComputePresentation.unavailableText(for: .operatingSystemTooOld, isMacCatalyst: true)
                == String(localized: "Requires macOS 27 or later."),
        )
        #expect(
            PrivateCloudComputePresentation.unavailableText(for: .deviceNotEligible)
                == String(localized: "Not available on this device."),
        )
        #expect(
            PrivateCloudComputePresentation.unavailableText(for: .systemNotReady, appleIntelligenceDisabled: true)
                == String(localized: "Apple Intelligence is not enabled. Check your device settings."),
        )
        let reason = "someNewReason"
        #expect(
            PrivateCloudComputePresentation.unavailableText(for: .other(reason))
                == String(localized: "Not available right now: \(reason)"),
        )
    }

    @Test
    func `limit reached shows the reset time when known`() {
        let reset = Date(timeIntervalSince1970: 1_800_000_000)
        let time = "3:00 PM"
        #expect(
            PrivateCloudComputePresentation.failureText(
                for: .quotaLimitReached(resetDate: reset),
                formatTime: fixedTime,
            ) == String(localized: "Today's limit reached. Resets at \(time)."),
        )
        #expect(
            PrivateCloudComputePresentation.failureText(for: .quotaLimitReached(resetDate: nil))
                == String(localized: "Today's limit reached. Try again tomorrow."),
        )
    }

    @Test
    func `offline and busy read as plain sentences`() {
        #expect(
            PrivateCloudComputePresentation.failureText(for: .networkFailure)
                == String(localized: "You're offline. This model needs an internet connection."),
        )
        #expect(
            PrivateCloudComputePresentation.failureText(for: .serviceUnavailable)
                == String(localized: "Private Cloud Compute isn't responding. Try again in a moment."),
        )
    }

    @Test
    func `reset time follows the locale and its hour cycle`() throws {
        let utc = try #require(TimeZone(identifier: "UTC"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let date = try #require(calendar.date(from: .init(year: 2026, month: 11, day: 22, hour: 15)))

        var zh24 = Locale.Components(identifier: "zh-Hans_CN")
        zh24.hourCycle = .zeroToTwentyThree
        #expect(PrivateCloudComputePresentation.formatResetTime(date, locale: Locale(components: zh24), timeZone: utc) == "15:00")

        var zh12 = Locale.Components(identifier: "zh-Hans_CN")
        zh12.hourCycle = .oneToTwelve
        let zh12Text = PrivateCloudComputePresentation.formatResetTime(date, locale: Locale(components: zh12), timeZone: utc)
        #expect(zh12Text.contains("下午"))
        #expect(zh12Text.contains("3:00"))

        let en = PrivateCloudComputePresentation.formatResetTime(date, locale: Locale(identifier: "en_US"), timeZone: utc)
        #expect(en.contains("3:00"))
        #expect(en.contains("PM"))
    }

    @Test
    func `copy never uses middle dots`() {
        let texts = [
            AppleIntelligenceModelNames.localModel,
            AppleIntelligenceModelNames.privateCloudComputeModel,
            AppleIntelligenceModelNames.local,
            AppleIntelligenceModelNames.privateCloudCompute,
            AppleIntelligenceModelDescriptions.local,
            AppleIntelligenceModelDescriptions.privateCloudCompute,
            AppleIntelligenceModelDescriptions.sectionFooter,
        ]
        for text in texts {
            #expect(!text.isEmpty)
            #expect(!text.contains("·") && !text.contains("•") && !text.contains("・"))
        }
    }

    @MainActor
    @Test
    func `model names are English in every language`() {
        #expect(AppleIntelligenceModelNames.localModel == "Apple Intelligence Local")
        #expect(AppleIntelligenceModelNames.privateCloudComputeModel == "Apple Intelligence PCC")
        #expect(AppleIntelligenceModelNames.privateCloudCompute == "Private Cloud Compute")
        #expect(AppleIntelligenceModelNames.local != "Local (Apple Intelligence Model)")
        #expect(ModelManager.shared.modelName(identifier: PrivateCloudComputeCenter.modelIdentifier)
            == AppleIntelligenceModelNames.privateCloudComputeModel)
    }

    @Test
    func `switch text puts the reason on its own line`() {
        let description = AppleIntelligenceModelDescriptions.privateCloudCompute
        #expect(AppleIntelligenceModelDescriptions.text(description: description, unavailableReason: nil) == description)
        #expect(AppleIntelligenceModelDescriptions.text(description: description, unavailableReason: "") == description)
        let reason = PrivateCloudComputePresentation.unavailableText(for: .systemNotReady)
        #expect(
            AppleIntelligenceModelDescriptions.text(description: description, unavailableReason: reason)
                == description + "\n" + reason,
        )
    }

    @Test
    func `launch deletes the retired Reasoning Effort value`() throws {
        let suiteName = "pcc.retired.\(UUID().uuidString)"
        let suite = try #require(UserDefaults(suiteName: suiteName))
        defer { suite.removePersistentDomain(forName: suiteName) }
        let storage = UserDefaultKeyValueStorage(suite: suite)
        let key = ModelManager.retiredCloudReasoningEffortKey
        storage.setValue(Data("deep".utf8), forKey: key)
        storage.setValue(Data("1".utf8), forKey: ModelManager.privateCloudComputeEnabledKey)

        ModelManager.removeRetiredSettings(storage: storage)

        #expect(storage.value(forKey: key) == nil)
        #expect(storage.value(forKey: ModelManager.privateCloudComputeEnabledKey) != nil)
        #expect(SettingsBackup.retiredKeys.contains(key))
    }

    @MainActor
    @Test
    func `the Private Cloud Compute switch alone decides whether the menu lists it`() {
        let manager = ModelManager.shared
        let savedCloud = manager.privateCloudComputeEnabled
        let savedLocal = manager.appleIntelligenceEnabled
        defer {
            manager.privateCloudComputeEnabled = savedCloud
            manager.appleIntelligenceEnabled = savedLocal
        }
        let center = PrivateCloudComputeCenter.shared
        let listable = PrivateCloudComputePresentation.isListedInModelMenu(center.availabilityState)

        manager.privateCloudComputeEnabled = false
        manager.appleIntelligenceEnabled = true
        #expect(!center.isListedInModelMenu)

        manager.privateCloudComputeEnabled = true
        manager.appleIntelligenceEnabled = false
        #expect(center.isListedInModelMenu == listable)
    }
}
