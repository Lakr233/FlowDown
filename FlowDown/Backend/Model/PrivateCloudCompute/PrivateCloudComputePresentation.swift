//
//  PrivateCloudComputePresentation.swift
//  FlowDown
//
//  What the app says about Apple's Private Cloud Compute model. Pure
//  functions over the FoundationModels-free state in ChatClientKit, so every
//  OS can compile and test them.
//

import ChatClientKit
import Foundation

enum PrivateCloudComputePresentation {
    static var isMacCatalyst: Bool {
        #if targetEnvironment(macCatalyst)
            true
        #else
            false
        #endif
    }

    /// Why the model can't be used, in the user's words.
    /// - Parameter appleIntelligenceDisabled: the on-device model reports
    ///   Apple Intelligence turned off, which is the usual cause of
    ///   `systemNotReady`.
    static func unavailableText(
        for reason: PrivateCloudComputeUnavailableReason,
        isMacCatalyst: Bool = Self.isMacCatalyst,
        appleIntelligenceDisabled: Bool = false,
    ) -> String {
        switch reason {
        case .operatingSystemTooOld:
            return isMacCatalyst
                ? String(localized: "Requires macOS 27 or later.")
                : String(localized: "Requires iOS 27 or later.")
        case .deviceNotEligible:
            return String(localized: "Not available on this device.")
        case .systemNotReady:
            if appleIntelligenceDisabled {
                return String(localized: "Apple Intelligence is not enabled. Check your device settings.")
            }
            return notAvailableRightNow(String(localized: "Model Not Ready"))
        case let .other(description):
            return notAvailableRightNow(description)
        }
    }

    /// Shown where this copy isn't signed with the Private Cloud Compute
    /// entitlement (the Mac build from GitHub Releases): in the Apple
    /// Intelligence Models footer, and as the hint for a failed request.
    static var notEntitledText: String {
        String(localized: "Due to Apple's restrictions, Private Cloud Compute is only available in the App Store version of FlowDown.")
    }

    /// The reason line under the Private Cloud Compute switch. A missing
    /// entitlement isn't repeated there; the section footer says it. The OS
    /// and device reasons stay.
    static func switchReasonText(
        for availability: PrivateCloudComputeAvailabilityState,
        isEntitled: Bool,
        isMacCatalyst: Bool = Self.isMacCatalyst,
        appleIntelligenceDisabled: Bool = false,
    ) -> String? {
        switch availability {
        case .unavailable(.operatingSystemTooOld), .unavailable(.deviceNotEligible):
            break
        case .available, .unavailable:
            guard isEntitled else { return nil }
        }
        return unavailableText(
            for: availability,
            isEntitled: isEntitled,
            isMacCatalyst: isMacCatalyst,
            appleIntelligenceDisabled: appleIntelligenceDisabled,
        )
    }

    /// Why the model can't be used, or nil when it can. A missing
    /// entitlement is reported unless the OS or device rules the model out
    /// anyway, since then the App Store build wouldn't run it either.
    static func unavailableText(
        for availability: PrivateCloudComputeAvailabilityState,
        isEntitled: Bool,
        isMacCatalyst: Bool = Self.isMacCatalyst,
        appleIntelligenceDisabled: Bool = false,
    ) -> String? {
        switch availability {
        case .unavailable(.operatingSystemTooOld), .unavailable(.deviceNotEligible):
            break
        case .available, .unavailable:
            if !isEntitled { return notEntitledText }
        }
        guard case let .unavailable(reason) = availability else { return nil }
        return unavailableText(
            for: reason,
            isMacCatalyst: isMacCatalyst,
            appleIntelligenceDisabled: appleIntelligenceDisabled,
        )
    }

    private static func notAvailableRightNow(_ reason: String) -> String {
        String(localized: "Not available right now: \(reason)")
    }

    /// The locale for the reset time: the language the app is shown in
    /// (which can differ from the system's, per app), with the user's region
    /// and 12 or 24 hour setting. zh-Hans reads "15:00" or "下午3:00".
    static var timeLocale: Locale {
        let current = Locale.autoupdatingCurrent
        var components = Locale.Components(locale: current)
        if let language = Bundle.main.preferredLocalizations.first {
            components.languageComponents = .init(identifier: language)
        }
        components.hourCycle = current.hourCycle
        return Locale(components: components)
    }

    /// The reset time, time only, in the system's short time format for
    /// `locale`.
    static func formatResetTime(_ date: Date, locale: Locale = timeLocale, timeZone: TimeZone = .current) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.locale = locale
        style.timeZone = timeZone
        return date.formatted(style)
    }

    static func limitReachedText(resetDate: Date?, formatTime: (Date) -> String = { formatResetTime($0) }) -> String {
        if let resetDate {
            let time = formatTime(resetDate)
            return String(localized: "Today's limit reached. Resets at \(time).")
        }
        return String(localized: "Today's limit reached. Try again tomorrow.")
    }

    /// The hint added to the conversation after a failed request.
    static func failureText(
        for failure: PrivateCloudComputeFailure,
        appleIntelligenceDisabled: Bool = false,
        formatTime: (Date) -> String = { formatResetTime($0) },
    ) -> String {
        switch failure {
        case .networkFailure:
            String(localized: "You're offline. This model needs an internet connection.")
        case let .quotaLimitReached(resetDate):
            limitReachedText(resetDate: resetDate, formatTime: formatTime)
        case .serviceUnavailable:
            String(localized: "Private Cloud Compute isn't responding. Try again in a moment.")
        case let .unavailable(reason):
            unavailableText(for: reason, appleIntelligenceDisabled: appleIntelligenceDisabled)
        }
    }

    /// Whether the model menu lists the cloud model: only where it could ever
    /// run. An eligible device that isn't ready yet still lists it, disabled,
    /// with the reason. A copy without the entitlement never lists it.
    static func isListedInModelMenu(_ availability: PrivateCloudComputeAvailabilityState, isEntitled: Bool = true) -> Bool {
        guard isEntitled else { return false }
        return switch availability {
        case .available:
            true
        case let .unavailable(reason):
            switch reason {
            case .operatingSystemTooOld, .deviceNotEligible:
                false
            case .systemNotReady, .other:
                true
            }
        }
    }
}
