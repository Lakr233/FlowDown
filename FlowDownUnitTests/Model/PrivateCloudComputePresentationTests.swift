@testable import ChatClientKit
@testable import FlowDown
import Foundation
import Testing

/// What the app says about Apple Intelligence Cloud in each state. The tests
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
    func `quota below the limit shows nothing`() {
        #expect(PrivateCloudComputePresentation.quotaNotice(for: .belowLimit) == nil)
    }

    @Test
    func `approaching the limit shows a note without buttons`() throws {
        let notice = try #require(PrivateCloudComputePresentation.quotaNotice(for: .approachingLimit))
        #expect(notice.kind == .approachingLimit)
        #expect(notice.text == String(localized: "You've almost reached today's limit."))
        #expect(notice.actions.isEmpty)
    }

    @Test
    func `limit reached shows the reset time and the upgrade only when offered`() throws {
        let reset = Date(timeIntervalSince1970: 1_800_000_000)
        let withSuggestion = try #require(PrivateCloudComputePresentation.quotaNotice(
            for: .limitReached(resetDate: reset, canIncreaseLimit: true),
            formatTime: fixedTime,
        ))
        let time = "3:00 PM"
        #expect(withSuggestion.text == String(localized: "Today's limit reached. Resets at \(time)."))
        #expect(withSuggestion.actions == [.useOnDeviceModel, .increaseLimit])

        let withoutSuggestion = try #require(PrivateCloudComputePresentation.quotaNotice(
            for: .limitReached(resetDate: nil, canIncreaseLimit: false),
            formatTime: fixedTime,
        ))
        #expect(withoutSuggestion.text == String(localized: "Today's limit reached. Try again tomorrow."))
        #expect(withoutSuggestion.actions == [.useOnDeviceModel])
    }

    @Test
    func `offline offers the on-device model`() {
        let notice = PrivateCloudComputePresentation.failureNotice(for: .networkFailure)
        #expect(notice.kind == .offline)
        #expect(notice.text == String(localized: "You're offline. This model needs an internet connection."))
        #expect(notice.actions == [.useOnDeviceModel])
        #expect(notice.offeringOnDeviceModel(false).actions.isEmpty)
    }

    @Test
    func `a busy service asks to try again`() {
        let notice = PrivateCloudComputePresentation.failureNotice(for: .serviceUnavailable)
        #expect(notice.text == String(localized: "Apple Intelligence Cloud isn't responding. Try again in a moment."))
        #expect(notice.actions.isEmpty)
    }

    @Test
    func `the last failure wins over the quota note`() {
        let notice = PrivateCloudComputePresentation.notice(
            availability: .available,
            quota: .approachingLimit,
            lastFailure: .networkFailure,
        )
        #expect(notice?.kind == .offline)

        let quotaOnly = PrivateCloudComputePresentation.notice(
            availability: .available,
            quota: .approachingLimit,
            lastFailure: nil,
        )
        #expect(quotaOnly?.kind == .approachingLimit)

        let unavailable = PrivateCloudComputePresentation.notice(
            availability: .unavailable(.deviceNotEligible),
            quota: .belowLimit,
            lastFailure: nil,
        )
        #expect(unavailable?.kind == .unavailable)
    }

    @Test
    func `copy never uses middle dots`() {
        let texts = [
            PrivateCloudComputePresentation.displayName,
            PrivateCloudComputePresentation.subtitle,
            PrivateCloudComputePresentation.onDeviceSubtitle,
            PrivateCloudComputePresentation.useOnDeviceModelTitle,
            PrivateCloudComputePresentation.increaseLimitTitle,
        ]
        for text in texts {
            #expect(!text.contains("·") && !text.contains("•") && !text.contains("・"))
        }
    }
}
