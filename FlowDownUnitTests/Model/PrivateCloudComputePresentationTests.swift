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
                == String(localized: "Apple Intelligence Cloud isn't responding. Try again in a moment."),
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
            PrivateCloudComputePresentation.displayName,
            PrivateCloudComputePresentation.subtitle,
            PrivateCloudComputePresentation.onDeviceSubtitle,
        ]
        for text in texts {
            #expect(!text.contains("·") && !text.contains("•") && !text.contains("・"))
        }
    }
}
