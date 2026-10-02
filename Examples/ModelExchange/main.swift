//
//  main.swift
//  ModelExchange
//
//  Created by qaq on 8/12/2025.
//

import FlowDownModelExchange
import SwiftUI

FlowDownModelExchangeExampleApp.main()

struct FlowDownModelExchangeExampleApp: App {
    @State private var keyPair = ModelExchangeKeyPair()
    @State private var sessionId: String?
    @State private var status: String = "Idle"
    @State private var receivedModels: String = "No payload yet"
    @State private var lastExchangeURL: String?
    @State private var lastPayload: String?

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ExampleView(
                    keyPair: $keyPair,
                    sessionId: $sessionId,
                    status: $status,
                    receivedModels: $receivedModels,
                    lastExchangeURL: $lastExchangeURL,
                    lastPayload: $lastPayload,
                )
            }
        }
    }
}

private struct ExampleView: View {
    @Environment(\.openURL) private var openURL

    @Binding var keyPair: ModelExchangeKeyPair
    @Binding var sessionId: String?
    @Binding var status: String
    @Binding var receivedModels: String
    @Binding var lastExchangeURL: String?
    @Binding var lastPayload: String?

    private let callbackScheme = "example-callback"
    @State private var selectedCapabilities: Set<ModelExchangeCapability> = [.audio, .developerRole]

    private var builder: ModelExchangeRequestBuilder {
        ModelExchangeRequestBuilder(
            flowdownScheme: "flowdown",
            callbackScheme: callbackScheme,
            keyPair: keyPair,
        )
    }

    private var handshakeURL: URL? {
        builder.makeHandshakeURL()
    }

    var body: some View {
        List {
            Section("Flow") {
                Button("Start handshake with FlowDown") {
                    startHandshake()
                }
                Button("Rotate key pair") {
                    keyPair = ModelExchangeKeyPair()
                    sessionId = nil
                    status = "Keys rotated"
                    receivedModels = "No payload yet"
                    lastExchangeURL = nil
                    lastPayload = nil
                }
            }

            Section("Capabilities") {
                ForEach(ModelExchangeCapability.allCases, id: \.self) { capability in
                    Toggle(name(for: capability), isOn: binding(for: capability))
                }
            }

            Section("Current session") {
                LabeledContent("Session", value: sessionId ?? "Not verified")
                LabeledContent("Status", value: status)
            }

            Section("Handshake URL") {
                Text(handshakeURL?.absoluteString ?? "Unavailable")
                    .font(.footnote)
                    .textSelection(.enabled)
            }

            if let lastExchangeURL {
                Section("Last exchange request") {
                    Text(lastExchangeURL)
                        .font(.footnote)
                        .textSelection(.enabled)
                }
            }

            if let lastPayload {
                Section("Raw payload") {
                    Text(lastPayload)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                }
            }

            Section("Received models") {
                Text(receivedModels)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
            }

            Section("Public key") {
                Text("Signing: \(keyPair.publicKey.signing.base64EncodedString())")
                    .font(.footnote)
                    .textSelection(.enabled)
                Text("Agreement: \(keyPair.publicKey.agreement.base64EncodedString())")
                    .font(.footnote)
                    .textSelection(.enabled)
            }
        }
        .navigationTitle("Model Exchange Demo")
        .onOpenURL { url in
            handleCallback(url: url)
        }
    }

    private func binding(for capability: ModelExchangeCapability) -> Binding<Bool> {
        Binding(
            get: { selectedCapabilities.contains(capability) },
            set: { isOn in
                if isOn {
                    selectedCapabilities.insert(capability)
                } else {
                    selectedCapabilities.remove(capability)
                }
            },
        )
    }

    private func name(for capability: ModelExchangeCapability) -> String {
        switch capability {
        case .audio:
            "Audio"
        case .visual:
            "Visual"
        case .tool:
            "Tool"
        case .developerRole:
            "Role"
        }
    }

    private func startHandshake() {
        guard let url = handshakeURL else {
            status = "Handshake URL unavailable"
            return
        }
        status = "Opening FlowDown for verification"
        openURL(url)
    }

    private func handleCallback(url: URL) {
        guard url.scheme == callbackScheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return }

        let dict = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item -> (String, String)? in
            guard let value = item.value else { return nil }
            return (item.name.lowercased(), value)
        })

        switch dict["stage"]?.lowercased() {
        case "verification":
            handleVerification(dict: dict)
        case "completed":
            handleCompletion(dict: dict)
        case "cancelled":
            sessionId = nil
            status = "User cancelled in FlowDown"
        default:
            status = "Unknown callback stage"
        }
    }

    private func handleVerification(dict: [String: String]) {
        guard let session = dict["session"] else {
            status = "Missing session in verification"
            return
        }
        guard let pk = dict["pk"], pk == keyPair.encodedPublicKey else {
            status = "Public key mismatch in verification"
            return
        }

        sessionId = session
        status = "Session verified, requesting models"
        sendExchangeRequest(session: session)
    }

    private func handleCompletion(dict: [String: String]) {
        guard let payload = dict["payload"] else {
            status = "Missing payload"
            return
        }
        guard dict["session"] == sessionId else {
            status = "Session mismatch"
            return
        }

        do {
            let encrypted = try ModelExchangeEncryptedPayload.decode(from: payload)
            let data = try ModelExchangeCrypto.decrypt(encrypted, with: keyPair)
            let rendered = try renderModels(from: data, format: dict["format"] ?? "plist")
            receivedModels = rendered.text
            status = "Received \(rendered.count) model(s)"
            lastPayload = payload
        } catch {
            status = "Decrypt failed: \(error.localizedDescription)"
        }
        sessionId = nil
    }

    private func sendExchangeRequest(session: String) {
        do {
            let signed = try builder.makeExchangeURL(
                session: session,
                appName: "Example Integrator",
                reason: "Request models from FlowDown",
                capabilities: Array(selectedCapabilities),
                multipleSelection: false,
            )
            lastExchangeURL = signed.url.absoluteString
            status = "Opening FlowDown to pick models"
            openURL(signed.url)
        } catch {
            status = "Build request failed: \(error.localizedDescription)"
        }
    }

    private func renderModels(from data: Data, format: String) throws -> (text: String, count: Int) {
        if format.lowercased() == "plist" {
            let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            let normalized = normalizeJSONCompatible(plist)
            let count = (normalized as? [Any])?.count ?? 0
            guard JSONSerialization.isValidJSONObject(normalized),
                  let jsonData = try? JSONSerialization.data(withJSONObject: normalized, options: [.prettyPrinted, .sortedKeys]),
                  let jsonText = String(data: jsonData, encoding: .utf8)
            else {
                return (String(describing: normalized), count)
            }
            return (jsonText, count)
        }

        return (String(data: data, encoding: .utf8) ?? "Unsupported payload", 0)
    }

    private func normalizeJSONCompatible(_ value: Any) -> Any {
        switch value {
        case let date as Date:
            return ISO8601DateFormatter().string(from: date)
        case let data as Data:
            return data.base64EncodedString()
        case let array as [Any]:
            return array.map { normalizeJSONCompatible($0) }
        case let dict as [String: Any]:
            var converted: [String: Any] = [:]
            for (key, value) in dict {
                converted[key] = normalizeJSONCompatible(value)
            }
            return converted
        default:
            return value
        }
    }
}
