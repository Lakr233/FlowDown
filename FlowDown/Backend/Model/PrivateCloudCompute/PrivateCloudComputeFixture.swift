//
//  PrivateCloudComputeFixture.swift
//  FlowDown
//
//  DEBUG-only fixtures for Apple Intelligence Cloud, so every designed state
//  can be shown on a Simulator, which has no model. Select one by launching
//  the app with the environment variable FLOWDOWN_PCC_FIXTURE set to a case
//  name, for example:
//
//      simulator launch wiki.qaq.flow --env FLOWDOWN_PCC_FIXTURE=approachingLimit
//
//  Add FLOWDOWN_PCC_FIXTURE_ON_DEVICE=available to also treat the on-device
//  model as available, so the menu and the "Use On-Device Model" button show.
//
//  Without the variable, and in every release build, the app reads the real
//  model. Fixture replies are labelled as fixture output; no model is called.
//

#if DEBUG
    import ChatClientKit
    import Foundation
    import FoundationModels

    enum PrivateCloudComputeFixture: String, CaseIterable {
        case available
        case deviceNotEligible
        case systemNotReady
        case approachingLimit
        /// Limit reached with a reset time and an iCloud+ suggestion.
        case limitReached
        /// Limit reached with neither a reset time nor a suggestion.
        case limitReachedWithoutResetDate
        /// Available, but every request fails with `networkFailure`.
        case networkFailure

        static let environmentKey = "FLOWDOWN_PCC_FIXTURE"
        /// Set to `available` next to a fixture to treat the on-device model
        /// as available too (the Simulator has none), so the model menu lists
        /// both Apple models and "Use On-Device Model" shows.
        static let onDeviceEnvironmentKey = "FLOWDOWN_PCC_FIXTURE_ON_DEVICE"

        /// Fixtures stand in for the iOS 27 model, so they only apply where it
        /// could exist.
        static var current: PrivateCloudComputeFixture? {
            guard PrivateCloudComputeIdentity.isSupportedOperatingSystem else { return nil }
            return ProcessInfo.processInfo.environment[environmentKey].flatMap(Self.init(rawValue:))
        }

        static var treatsOnDeviceModelAsAvailable: Bool {
            current != nil && ProcessInfo.processInfo.environment[onDeviceEnvironmentKey] == "available"
        }

        /// Today at 15:00 in the current time zone.
        static var fixtureResetDate: Date {
            Calendar.current.date(bySettingHour: 15, minute: 0, second: 0, of: Date()) ?? Date()
        }

        var availability: PrivateCloudComputeAvailabilityState {
            switch self {
            case .deviceNotEligible: .unavailable(.deviceNotEligible)
            case .systemNotReady: .unavailable(.systemNotReady)
            default: .available
            }
        }

        var quota: PrivateCloudComputeQuotaState {
            switch self {
            case .approachingLimit:
                .approachingLimit
            case .limitReached:
                .limitReached(resetDate: Self.fixtureResetDate, canIncreaseLimit: true)
            case .limitReachedWithoutResetDate:
                .limitReached(resetDate: nil, canIncreaseLimit: false)
            default:
                .belowLimit
            }
        }

        /// A fixture failure the real error types can't express (the
        /// framework offers no way to build a `LimitIncreaseSuggestion`).
        struct FixtureError: LocalizedError {
            let failure: PrivateCloudComputeFailure
            var errorDescription: String? {
                "Fixture failure: \(failure)"
            }
        }

        /// Scripted replies through the same pipeline as the real client.
        final class ChatClient: ChatService, @unchecked Sendable {
            let errorCollector = ErrorCollector.new()
            let fixture: PrivateCloudComputeFixture

            init(fixture: PrivateCloudComputeFixture) {
                self.fixture = fixture
            }

            static let sampleReasoning = "[Fixture] Scripted reasoning from the DEBUG fixture."
            static let sampleReply = "[Fixture] This reply is sample output from the DEBUG Apple Intelligence Cloud fixture. No model was called."

            func streamingChat(body _: ChatRequestBody) async throws -> AnyAsyncSequence<ChatResponseChunk> {
                switch fixture {
                case .deviceNotEligible, .systemNotReady:
                    if case let .unavailable(reason) = fixture.availability {
                        throw PrivateCloudComputeUnavailableError(reason: reason)
                    }
                case .limitReached:
                    throw FixtureError(failure: .quotaLimitReached(
                        resetDate: PrivateCloudComputeFixture.fixtureResetDate,
                        canIncreaseLimit: true,
                    ))
                case .limitReachedWithoutResetDate:
                    #if compiler(>=6.4)
                        if #available(iOS 27.0, macCatalyst 27.0, *) {
                            // The real error, so the real mapping runs.
                            throw PrivateCloudComputeLanguageModel.Error.quotaLimitReached(
                                .init(debugDescription: "Fixture: daily limit reached"),
                            )
                        }
                    #endif
                    throw FixtureError(failure: .quotaLimitReached(resetDate: nil, canIncreaseLimit: false))
                case .networkFailure:
                    #if compiler(>=6.4)
                        if #available(iOS 27.0, macCatalyst 27.0, *) {
                            throw PrivateCloudComputeLanguageModel.Error.networkFailure(
                                .init(debugDescription: "Fixture: offline"),
                            )
                        }
                    #endif
                    throw FixtureError(failure: .networkFailure)
                case .available, .approachingLimit:
                    break
                }

                let chunks: [ChatResponseChunk] = [.reasoning(Self.sampleReasoning)]
                    + Self.sampleReply.split(separator: " ", omittingEmptySubsequences: false)
                    .enumerated()
                    .map { index, word in .text(index == 0 ? String(word) : " " + word) }
                return AnyAsyncSequence(AsyncThrowingStream { continuation in
                    let task = Task {
                        for chunk in chunks {
                            try? await Task.sleep(for: .milliseconds(40))
                            if Task.isCancelled { break }
                            continuation.yield(chunk)
                        }
                        continuation.finish()
                    }
                    continuation.onTermination = { _ in task.cancel() }
                })
            }
        }
    }
#endif
