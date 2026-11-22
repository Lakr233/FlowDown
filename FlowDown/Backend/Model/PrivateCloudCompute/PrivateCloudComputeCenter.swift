//
//  PrivateCloudComputeCenter.swift
//  FlowDown
//
//  The app's one boundary to Apple Intelligence Cloud (Apple's Private Cloud
//  Compute model): availability, the chat client, and how its errors read.
//  DEBUG builds can swap in a fixture here
//  (`PrivateCloudComputeFixture`); production always reads the real model.
//
//  Needs the managed entitlement `com.apple.developer.private-cloud-compute`
//  (Boolean), in both FlowDown/Resources/Entitlements files. Without it the
//  system reports the model unavailable or fails the request.
//

import ChatClientKit
import Foundation
import FoundationModels

final class PrivateCloudComputeCenter: @unchecked Sendable {
    static let shared = PrivateCloudComputeCenter()

    static var modelIdentifier: String {
        PrivateCloudComputeIdentity.modelIdentifier
    }

    private init() {}

    // MARK: State

    var availabilityState: PrivateCloudComputeAvailabilityState {
        #if DEBUG
            if let fixture = PrivateCloudComputeFixture.current {
                return fixture.availability
            }
        #endif
        #if compiler(>=6.4)
            if #available(iOS 27.0, macCatalyst 27.0, *) {
                return PrivateCloudComputeModel.shared.availabilityState
            }
        #endif
        return .unavailable(.operatingSystemTooOld)
    }

    var isAvailable: Bool {
        availabilityState.isAvailable
    }

    /// Whether the on-device model says Apple Intelligence is turned off,
    /// the usual cause of the cloud model's `systemNotReady`.
    var appleIntelligenceDisabled: Bool {
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            return SystemLanguageModel.default.availability == .unavailable(.appleIntelligenceNotEnabled)
        }
        return false
    }

    /// Listed in the model menu only on iOS / macOS 27 and eligible devices,
    /// and only while the Apple Intelligence switch in Settings is on.
    var isListedInModelMenu: Bool {
        guard ModelManager.shared.appleIntelligenceEnabled else { return false }
        return PrivateCloudComputePresentation.isListedInModelMenu(availabilityState)
    }

    var unavailableText: String? {
        guard case let .unavailable(reason) = availabilityState else { return nil }
        return PrivateCloudComputePresentation.unavailableText(
            for: reason,
            appleIntelligenceDisabled: appleIntelligenceDisabled,
        )
    }

    /// Whether the on-device Apple Intelligence model can run. DEBUG
    /// fixtures can stand in for it on a Simulator, which has no model.
    var isOnDeviceModelAvailable: Bool {
        #if DEBUG
            if PrivateCloudComputeFixture.treatsOnDeviceModelAsAvailable {
                return true
            }
        #endif
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            return AppleIntelligenceModel.shared.isAvailable
        }
        return false
    }

    // MARK: Failures

    /// Maps an error from a cloud request onto the failures the app explains,
    /// or nil for any other error.
    func failure(from error: any Error) -> PrivateCloudComputeFailure? {
        #if DEBUG
            if let error = error as? PrivateCloudComputeFixture.FixtureError {
                return error.failure
            }
        #endif
        if let error = error as? PrivateCloudComputeUnavailableError {
            return .unavailable(error.reason)
        }
        #if compiler(>=6.4)
            if #available(iOS 27.0, macCatalyst 27.0, *) {
                return PrivateCloudComputeModel.failure(from: error)
            }
        #endif
        return nil
    }

    // MARK: Client

    func makeChatService() throws -> any ChatService {
        #if DEBUG
            if let fixture = PrivateCloudComputeFixture.current {
                return PrivateCloudComputeFixture.ChatClient(fixture: fixture)
            }
        #endif
        #if compiler(>=6.4)
            if #available(iOS 27.0, macCatalyst 27.0, *) {
                return PrivateCloudComputeChatClient(configuration: .init(
                    reasoningDepth: ModelManager.shared.cloudReasoningDepth,
                ))
            }
        #endif
        throw PrivateCloudComputeUnavailableError(reason: .operatingSystemTooOld)
    }
}
