//
//  PrivateCloudComputePresentation.swift
//  FlowDown
//
//  What the app says about Apple Intelligence Cloud (Apple's Private Cloud
//  Compute model). Pure functions over the FoundationModels-free state in
//  ChatClientKit, so every OS can compile and test them.
//

import ChatClientKit
import Foundation

enum PrivateCloudComputePresentation {
    static var displayName: String {
        String(localized: "Apple Intelligence Cloud")
    }

    /// Under the cloud model in the model menu and in Settings.
    static var subtitle: String {
        String(localized: "Runs on Apple's Private Cloud Compute")
    }

    /// Under the on-device model, only while the cloud model is listed too.
    static var onDeviceSubtitle: String {
        String(localized: "On device")
    }

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
            String(localized: "Apple Intelligence Cloud isn't responding. Try again in a moment.")
        case let .unavailable(reason):
            unavailableText(for: reason, appleIntelligenceDisabled: appleIntelligenceDisabled)
        }
    }

    /// Whether the model menu lists the cloud model: only where it could ever
    /// run. An eligible device that isn't ready yet still lists it, disabled,
    /// with the reason.
    static func isListedInModelMenu(_ availability: PrivateCloudComputeAvailabilityState) -> Bool {
        switch availability {
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
