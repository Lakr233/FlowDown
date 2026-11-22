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

/// A note shown above the input while Apple Intelligence Cloud is the
/// conversation's model.
struct PrivateCloudComputeNotice: Equatable {
    enum Kind: Equatable {
        case approachingLimit
        case limitReached
        case offline
        case serviceUnavailable
        case unavailable
    }

    enum Action: Equatable {
        /// Switch this conversation to the on-device Apple Intelligence model.
        case useOnDeviceModel
        /// Present the system's iCloud+ sheet (`LimitIncreaseSuggestion.show()`).
        case increaseLimit

        var title: String {
            switch self {
            case .useOnDeviceModel: PrivateCloudComputePresentation.useOnDeviceModelTitle
            case .increaseLimit: PrivateCloudComputePresentation.increaseLimitTitle
            }
        }

        var accessibilityIdentifier: String {
            switch self {
            case .useOnDeviceModel: "cloud-model-use-on-device"
            case .increaseLimit: "cloud-model-increase-limit"
            }
        }
    }

    let kind: Kind
    let text: String
    let actions: [Action]

    /// The same note without the switch button when the on-device model
    /// isn't available.
    func offeringOnDeviceModel(_ available: Bool) -> PrivateCloudComputeNotice {
        guard !available else { return self }
        return .init(kind: kind, text: text, actions: actions.filter { $0 != .useOnDeviceModel })
    }
}

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

    static var useOnDeviceModelTitle: String {
        String(localized: "Use On-Device Model")
    }

    static var increaseLimitTitle: String {
        String(localized: "Get More with iCloud+")
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

    /// The reset time, formatted for the user's locale, time only.
    static func formatResetTime(_ date: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
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

    private static func limitReachedNotice(
        resetDate: Date?,
        canIncreaseLimit: Bool,
        formatTime: (Date) -> String,
    ) -> PrivateCloudComputeNotice {
        .init(
            kind: .limitReached,
            text: limitReachedText(resetDate: resetDate, formatTime: formatTime),
            actions: canIncreaseLimit ? [.useOnDeviceModel, .increaseLimit] : [.useOnDeviceModel],
        )
    }

    /// The persistent note for the daily allowance, or nil while it's fine.
    static func quotaNotice(
        for state: PrivateCloudComputeQuotaState,
        formatTime: (Date) -> String = { formatResetTime($0) },
    ) -> PrivateCloudComputeNotice? {
        switch state {
        case .belowLimit:
            nil
        case .approachingLimit:
            .init(
                kind: .approachingLimit,
                text: String(localized: "You've almost reached today's limit."),
                actions: [],
            )
        case let .limitReached(resetDate, canIncreaseLimit):
            limitReachedNotice(resetDate: resetDate, canIncreaseLimit: canIncreaseLimit, formatTime: formatTime)
        }
    }

    /// The note after a failed request.
    static func failureNotice(
        for failure: PrivateCloudComputeFailure,
        appleIntelligenceDisabled: Bool = false,
        formatTime: (Date) -> String = { formatResetTime($0) },
    ) -> PrivateCloudComputeNotice {
        switch failure {
        case .networkFailure:
            .init(
                kind: .offline,
                text: String(localized: "You're offline. This model needs an internet connection."),
                actions: [.useOnDeviceModel],
            )
        case let .quotaLimitReached(resetDate, canIncreaseLimit):
            limitReachedNotice(resetDate: resetDate, canIncreaseLimit: canIncreaseLimit, formatTime: formatTime)
        case .serviceUnavailable:
            .init(
                kind: .serviceUnavailable,
                text: String(localized: "Apple Intelligence Cloud isn't responding. Try again in a moment."),
                actions: [],
            )
        case let .unavailable(reason):
            .init(
                kind: .unavailable,
                text: unavailableText(for: reason, appleIntelligenceDisabled: appleIntelligenceDisabled),
                actions: [],
            )
        }
    }

    /// What the input area shows: the last failure in this conversation wins
    /// over the quota, because it explains why the last reply is missing.
    static func notice(
        availability: PrivateCloudComputeAvailabilityState,
        quota: PrivateCloudComputeQuotaState,
        lastFailure: PrivateCloudComputeFailure?,
        appleIntelligenceDisabled: Bool = false,
        formatTime: (Date) -> String = { formatResetTime($0) },
    ) -> PrivateCloudComputeNotice? {
        if let lastFailure {
            return failureNotice(
                for: lastFailure,
                appleIntelligenceDisabled: appleIntelligenceDisabled,
                formatTime: formatTime,
            )
        }
        if case let .unavailable(reason) = availability {
            return failureNotice(
                for: .unavailable(reason),
                appleIntelligenceDisabled: appleIntelligenceDisabled,
                formatTime: formatTime,
            )
        }
        return quotaNotice(for: quota, formatTime: formatTime)
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
