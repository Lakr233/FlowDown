//
//  PrivateCloudComputeCenter.swift
//  FlowDown
//
//  The app's one boundary to Apple's Private Cloud Compute model:
//  availability, the chat client, and how its errors read. DEBUG builds can
//  swap in a fixture here (`PrivateCloudComputeFixture`); production always
//  reads the real model.
//
//  Needs the managed entitlement `com.apple.developer.private-cloud-compute`
//  (Boolean), in both FlowDown/Resources/Entitlements files. Without it the
//  system reports the model unavailable or fails the request. The Developer
//  ID Mac build can't have it (`PrivateCloudComputeEntitlement`), so there
//  the model is unavailable, with the reason pointing to the App Store.
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

    /// Whether this copy is signed with the entitlement. Every iOS build is.
    var isEntitled: Bool {
        PrivateCloudComputeEntitlement.isGranted
    }

    var isAvailable: Bool {
        isEntitled && availabilityState.isAvailable
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
    /// and only while the Private Cloud Compute switch in Settings is on.
    var isListedInModelMenu: Bool {
        guard ModelManager.shared.privateCloudComputeEnabled else { return false }
        return PrivateCloudComputePresentation.isListedInModelMenu(availabilityState, isEntitled: isEntitled)
    }

    var unavailableText: String? {
        PrivateCloudComputePresentation.unavailableText(
            for: availabilityState,
            isEntitled: isEntitled,
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

    /// The hint for a failed cloud request in the app's own words, or nil
    /// for any other error.
    func failureText(from error: any Error) -> String? {
        if error is NotEntitledError {
            return PrivateCloudComputePresentation.notEntitledText
        }
        guard let failure = failure(from: error) else { return nil }
        return PrivateCloudComputePresentation.failureText(
            for: failure,
            appleIntelligenceDisabled: appleIntelligenceDisabled,
        )
    }

    // MARK: Client

    /// Thrown instead of calling the model from a copy without the
    /// entitlement, for example a conversation synced from an iPhone.
    struct NotEntitledError: LocalizedError {
        var errorDescription: String? {
            PrivateCloudComputePresentation.notEntitledText
        }
    }

    func makeChatService() throws -> any ChatService {
        guard isEntitled else { throw NotEntitledError() }
        #if DEBUG
            if let fixture = PrivateCloudComputeFixture.current {
                return PrivateCloudComputeFixture.ChatClient(fixture: fixture)
            }
        #endif
        #if compiler(>=6.4)
            if #available(iOS 27.0, macCatalyst 27.0, *) {
                // Always the deepest reasoning; there is no setting for it.
                return PrivateCloudComputeChatClient(configuration: .init(
                    reasoningDepth: .deep,
                ))
            }
        #endif
        throw PrivateCloudComputeUnavailableError(reason: .operatingSystemTooOld)
    }
}
