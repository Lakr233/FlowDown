//
//  MCPSignInFlow.swift
//  FlowDown
//

import AlertController
import Storage
import UIKit

/// The user-facing steps around `MCPService.signIn`: asking for a Client ID
/// when the authorization server cannot register FlowDown by itself, and
/// reporting the outcome.
@MainActor
enum MCPSignInFlow {
    static func signIn(
        serverID: ModelContextServer.ID,
        from controller: UIViewController,
        completion: (@MainActor () -> Void)? = nil,
    ) {
        if MCPService.shared.authorizationState(for: serverID) == .clientIDRequired,
           let server = MCPService.shared.server(with: serverID),
           MCPService.shared.oauth.manualClient(for: server) == nil
        {
            promptClientID(serverID: serverID, from: controller) {
                signIn(serverID: serverID, from: controller, completion: completion)
            }
            return
        }
        Task { @MainActor in
            defer { completion?() }
            do {
                try await MCPService.shared.signIn(serverID: serverID)
                Indicator.present(title: "Signed In", referencingView: controller.view)
            } catch MCPOAuthError.cancelled {
                return
            } catch MCPOAuthError.clientIDRequired {
                promptClientID(serverID: serverID, from: controller) {
                    signIn(serverID: serverID, from: controller, completion: completion)
                }
            } catch {
                presentError(error, from: controller)
            }
        }
    }

    static func signOut(
        serverID: ModelContextServer.ID,
        from controller: UIViewController,
        completion: (@MainActor () -> Void)? = nil,
    ) {
        let alert = AlertViewController(
            title: "Sign Out",
            message: "FlowDown will forget the sign-in for this server on this device.",
        ) { context in
            context.addAction(title: "Cancel") {
                context.dispose()
            }
            context.addAction(title: "Sign Out", attribute: .accent) {
                context.dispose {
                    Task { @MainActor in
                        await MCPService.shared.signOut(serverID: serverID)
                        completion?()
                    }
                }
            }
        }
        controller.present(alert, animated: true)
    }

    /// Asks for a Client ID, then an optional client secret. An empty Client
    /// ID removes the stored one.
    static func promptClientID(
        serverID: ModelContextServer.ID,
        from controller: UIViewController,
        then: (@MainActor () -> Void)? = nil,
    ) {
        guard let server = MCPService.shared.server(with: serverID) else { return }
        let existing = MCPService.shared.oauth.manualClient(for: server)
        let idInput = AlertInputViewController(
            title: "Client ID",
            message: "Enter the OAuth Client ID registered for FlowDown with this server's authorization server. Use the redirect URI flowdown://mcp-oauth/callback.",
            placeholder: "Client ID",
            text: existing?.clientID ?? "",
        ) { clientID in
            let clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clientID.isEmpty else {
                MCPService.shared.setManualClient(serverID: serverID, clientID: "", clientSecret: nil)
                return
            }
            let secretInput = AlertInputViewController(
                title: "Client Secret",
                message: "Optional. Leave empty for a public client.",
                placeholder: "Client Secret (Optional)",
                text: "",
            ) { secret in
                MCPService.shared.setManualClient(serverID: serverID, clientID: clientID, clientSecret: secret)
                then?()
            }
            // Let the first prompt finish dismissing.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                controller.present(secretInput, animated: true)
            }
        }
        controller.present(idInput, animated: true)
    }

    private static func presentError(_ error: Swift.Error, from controller: UIViewController) {
        let alert = AlertViewController(
            title: "Sign-In Failed",
            message: "\(error.localizedDescription)",
        ) { context in
            context.allowSimpleDispose()
            context.addAction(title: "OK", attribute: .accent) {
                context.dispose()
            }
        }
        controller.present(alert, animated: true)
    }
}
