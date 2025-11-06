//
//  ModelManager+Inference.swift
//  FlowDown
//
//  Created by 秋星桥 on 1/29/25.
//

import ChatClientKit
import Foundation
import FoundationModels
import GPTEncoder
import MLX
import MLXLLM
import MLXLMCommon
import MLXVLM
import OAuthKit
import Storage

extension ModelManager {
    // - imageProcessingFailure : "height: 1 must be larger than factor: 28"
    static let testImage: CIImage = .init(
        cgImage: UIImage(
            color: .accent,
            size: .init(width: 64, height: 64)
        ).cgImage!
    )

    func testLocalModel(_ model: LocalModel, completion: @escaping (Result<Void, Error>) -> Void) {
        guard MLX.GPU.isSupported else {
            completion(.failure(NSError(domain: "GPU", code: -1, userInfo: [
                NSLocalizedDescriptionKey: String(localized: "Your device does not support MLX."),
            ])))
            return
        }
        let task = Task.detached {
            assert(!Thread.isMainThread)
            let config = ModelConfiguration(directory: ModelManager.shared.modelContent(for: model))
            let container: ModelContainer? =
                if model.capabilities.contains(.visual) {
                    try await VLMModelFactory.shared.loadContainer(configuration: config)
                } else {
                    try await LLMModelFactory.shared.loadContainer(configuration: config)
                }
            return try await container?.perform { context in
                let input = try await context.processor.prepare(
                    input: .init(
                        messages: [
                            [
                                "role": "system",
                                "content": "Reply YES to every query.",
                            ],
                            [
                                "role": "user",
                                "content": "YES or NO",
                            ],
                        ],
                        images: model.capabilities.contains(.visual) ? [.ciImage(Self.testImage)] : []
                    )
                )
                let result: GenerateResult = try MLXLMCommon.generate(
                    input: input,
                    parameters: GenerateParameters(temperature: 0),
                    context: context
                ) { _ in .stop }
                return result.output
            }
        }
        Task.detached {
            let token = MLXChatClientQueue.shared.acquire()
            do {
                let text = try await task.value
                MLXChatClientQueue.shared.release(token: token)
                if let text, !text.isEmpty {
                    Logger.model.debugFile("model \(model.model_identifier) generates output for test case: \(text)")
                    completion(.success(()))
                } else {
                    completion(
                        .failure(
                            NSError(
                                domain: "Model",
                                code: -1,
                                userInfo: [NSLocalizedDescriptionKey: String(localized: "Failed to generate text.")]
                            )
                        )
                    )
                }
            } catch {
                MLXChatClientQueue.shared.release(token: token)
                if let error = error as? ModelFactoryError {
                    switch error {
                    case .unsupportedModelType:
                        completion(
                            .failure(
                                NSError(
                                    domain: "Model",
                                    code: -1,
                                    userInfo: [NSLocalizedDescriptionKey: String(localized: "Unsupported model type.")]
                                )
                            )
                        )
                    case .unsupportedProcessorType:
                        completion(
                            .failure(
                                NSError(
                                    domain: "Model",
                                    code: -1,
                                    userInfo: [NSLocalizedDescriptionKey: String(localized: "Unsupported processor type.")]
                                )
                            )
                        )
                    case .noModelFactoryAvailable:
                        completion(
                            .failure(
                                NSError(
                                    domain: "Model",
                                    code: -1,
                                    userInfo: [NSLocalizedDescriptionKey: String(localized: "Unsupported model type.")]
                                )
                            )
                        )
                    case .configurationDecodingError:
                        completion(
                            .failure(
                                NSError(
                                    domain: "Model",
                                    code: -1,
                                    userInfo: [NSLocalizedDescriptionKey: String(localized: "Unable to decode configuration.")]
                                )
                            )
                        )
                    }
                } else if let error = error as? VLMError {
                    Logger.model.errorFile("VLM failed to inference: \(error)")
                    completion(
                        .failure(
                            NSError(
                                domain: "Model",
                                code: -1,
                                userInfo: [NSLocalizedDescriptionKey: String(localized: "Unsupported.")]
                            )
                        )
                    )
                } else {
                    completion(
                        .failure(
                            NSError(
                                domain: "Model",
                                code: -1,
                                userInfo: [NSLocalizedDescriptionKey: String(format: String(localized: "Failed to load model: %@"), error.localizedDescription)]
                            )
                        )
                    )
                }
            }
        }
    }

    func testCloudModel(_ model: CloudModel, completion: @escaping (Result<Void, Error>) -> Void) {
        var dic: [String: Any] = [
            "model": model.model_identifier,
            "stream": true,
            "messages": [
                [
                    "role": "system",
                    "content": "Reply YES to every query.",
                ],
                [
                    "role": "user",
                    "content": "YES or NO",
                ],
            ],
        ]
        // Get model's configured bodyFields for testing
        if !model.bodyFields.isEmpty,
           let data = model.bodyFields.data(using: .utf8),
           let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            for (key, value) in jsonObject where dic[key] == nil {
                dic[key] = value
            }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: dic),
              let endpoint = URL(string: model.endpoint)
        else {
            completion(
                .failure(
                    NSError(
                        domain: "Model",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: String(localized: "Invalid model configuration.")]
                    )
                )
            )
            return
        }
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !model.token.isEmpty { request.setValue("Bearer \(model.token)", forHTTPHeaderField: "Authorization") }
        // model.headers can override default headers including Authorization
        for value in model.headers {
            request.setValue(value.value, forHTTPHeaderField: value.key)
        }
        request.httpBody = data
        URLSession.shared.dataTask(with: request) { _, resp, _ in
            guard let resp = resp as? HTTPURLResponse else {
                completion(
                    .failure(
                        NSError(
                            domain: "Model",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: String(localized: "Invalid response.")]
                        )
                    )
                )
                return
            }
            guard resp.statusCode == 200 else {
                completion(
                    .failure(
                        NSError(
                            domain: "Model",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: String(format: String(localized: "Invalid status code: %d"), resp.statusCode)]
                        )
                    )
                )
                return
            }
            completion(.success(()))
        }.resume()
    }

    func testAppleIntelligenceModel(completion: @escaping (Result<Void, Error>) -> Void) {
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            guard AppleIntelligenceModel.shared.isAvailable else {
                completion(.failure(NSError(domain: "AppleIntelligence", code: -1, userInfo: [NSLocalizedDescriptionKey: String(localized: "Apple Intelligence is not available: \(AppleIntelligenceModel.shared.availabilityStatus)")])))
                return
            }
            Task {
                do {
                    let session = LanguageModelSession()
                    let prompt = "Reply YES to every query. YES or NO"
                    let response = try await session.respond(to: prompt)
                    if !response.content.isEmpty {
                        completion(.success(()))
                    } else {
                        completion(.failure(NSError(domain: "AppleIntelligence", code: -1, userInfo: [NSLocalizedDescriptionKey: "No response from Apple Intelligence."])))
                    }
                } catch {
                    completion(.failure(error))
                }
            }
        } else {
            completion(.failure(NSError(domain: "AppleIntelligence", code: -1, userInfo: [NSLocalizedDescriptionKey: "Requires iOS 26+"])))
        }
    }
}

extension ModelManager {
    static let indicatorText = " ●"

    /// Get the body fields configured for a cloud model
    /// - Parameter identifier: The model identifier
    /// - Returns: A dictionary of body fields, or empty dictionary if not found or empty
    public func modelBodyFields(for identifier: ModelIdentifier) -> [String: Any] {
        guard let model = cloudModel(identifier: identifier),
              !model.bodyFields.isEmpty,
              let data = model.bodyFields.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }
        return jsonObject
    }

    private func chatService(
        for identifier: ModelIdentifier,
        additionalBodyField: [String: Any]
    ) async throws -> any ChatService {
        if #available(iOS 26.0, macCatalyst 26.0, *), identifier == AppleIntelligenceModel.shared.modelIdentifier {
            return AppleIntelligenceChatClient()
        }
        if let model = cloudModel(identifier: identifier) {
            switch model.api_version {
            case .oai_completion:
                // Use additionalBodyField directly without merging model's bodyFields
                // Callers should explicitly merge bodyFields if needed
                return RemoteChatClient(
                    model: model.model_identifier,
                    baseURL: model.endpoint,
                    apiKey: model.token,
                    additionalHeaders: model.headers,
                    additionalBodyField: additionalBodyField
                )
            case .claude:
                return RemoteChatClient(
                    model: model.model_identifier,
                    format: AnthropicMessagesFormat(),
                    baseURL: model.endpoint,
                    apiKey: model.token,
                    additionalHeaders: model.headers,
                    additionalBodyField: additionalBodyField
                )
            case .oai_response:
                // Build OAuth client and obtain valid token
                let oauthConfig = OAuthConfiguration(
                    clientId: "app_EMoamEEZ73f0CkXaXp7hrann",
                    authorizationEndpoint: URL(string: "https://auth.openai.com/oauth/authorize")!,
                    tokenEndpoint: URL(string: "https://auth.openai.com/oauth/token")!,
                    redirectURI: URL(string: "http://localhost:1455/auth/callback")!,
                    scope: "openid profile email offline_access",
                    additionalParameters: [
                        "id_token_add_organizations": "true",
                        "codex_cli_simplified_flow": "true",
                    ],
                    usePKCE: true,
                    pkceMethod: .sha256
                )
                let oauthClient = OAuthClient(configuration: oauthConfig)
                let token = try await oauthClient.getValidToken()

                var headers = model.headers
                headers["Host"] = "chatgpt.com"
                headers["Accept"] = "text/event-stream"
                if let accountId = Self.chatGPTAccountId(from: token.idToken) {
                    headers["chatgpt-account-id"] = accountId
                }
                var additionalFields: [String: Any] = [
                    "store": false,
                ]
                // Base64 Decode the instruction file.
                if let instructions = Data(base64Encoded: "WW91IGFyZSBhIGNvZGluZyBhZ2VudCBydW5uaW5nIGluIHRoZSBDb2RleCBDTEksIGEgdGVybWluYWwtYmFzZWQgY29kaW5nIGFzc2lzdGFudC4gQ29kZXggQ0xJIGlzIGFuIG9wZW4gc291cmNlIHByb2plY3QgbGVkIGJ5IE9wZW5BSS4gWW91IGFyZSBleHBlY3RlZCB0byBiZSBwcmVjaXNlLCBzYWZlLCBhbmQgaGVscGZ1bC4KCllvdXIgY2FwYWJpbGl0aWVzOgotIFJlY2VpdmUgdXNlciBwcm9tcHRzIGFuZCBvdGhlciBjb250ZXh0IHByb3ZpZGVkIGJ5IHRoZSBoYXJuZXNzLCBzdWNoIGFzIGZpbGVzIGluIHRoZSB3b3Jrc3BhY2UuCi0gQ29tbXVuaWNhdGUgd2l0aCB0aGUgdXNlciBieSBzdHJlYW1pbmcgdGhpbmtpbmcgJiByZXNwb25zZXMsIGFuZCBieSBtYWtpbmcgJiB1cGRhdGluZyBwbGFucy4KLSBFbWl0IGZ1bmN0aW9uIGNhbGxzIHRvIHJ1biB0ZXJtaW5hbCBjb21tYW5kcyBhbmQgYXBwbHkgcGF0Y2hlcy4gRGVwZW5kaW5nIG9uIGhvdyB0aGlzIHNwZWNpZmljIHJ1biBpcyBjb25maWd1cmVkLCB5b3UgY2FuIHJlcXVlc3QgdGhhdCB0aGVzZSBmdW5jdGlvbiBjYWxscyBiZSBlc2NhbGF0ZWQgdG8gdGhlIHVzZXIgZm9yIGFwcHJvdmFsIGJlZm9yZSBydW5uaW5nLiBNb3JlIG9uIHRoaXMgaW4gdGhlICJTYW5kYm94IGFuZCBhcHByb3ZhbHMiIHNlY3Rpb24uCgpXaXRoaW4gdGhpcyBjb250ZXh0LCBDb2RleCByZWZlcnMgdG8gdGhlIG9wZW4tc291cmNlIGFnZW50aWMgY29kaW5nIGludGVyZmFjZSAobm90IHRoZSBvbGQgQ29kZXggbGFuZ3VhZ2UgbW9kZWwgYnVpbHQgYnkgT3BlbkFJKS4KCiMgSG93IHlvdSB3b3JrCgojIyBQZXJzb25hbGl0eQoKWW91ciBkZWZhdWx0IHBlcnNvbmFsaXR5IGFuZCB0b25lIGlzIGNvbmNpc2UsIGRpcmVjdCwgYW5kIGZyaWVuZGx5LiBZb3UgY29tbXVuaWNhdGUgZWZmaWNpZW50bHksIGFsd2F5cyBrZWVwaW5nIHRoZSB1c2VyIGNsZWFybHkgaW5mb3JtZWQgYWJvdXQgb25nb2luZyBhY3Rpb25zIHdpdGhvdXQgdW5uZWNlc3NhcnkgZGV0YWlsLiBZb3UgYWx3YXlzIHByaW9yaXRpemUgYWN0aW9uYWJsZSBndWlkYW5jZSwgY2xlYXJseSBzdGF0aW5nIGFzc3VtcHRpb25zLCBlbnZpcm9ubWVudCBwcmVyZXF1aXNpdGVzLCBhbmQgbmV4dCBzdGVwcy4gVW5sZXNzIGV4cGxpY2l0bHkgYXNrZWQsIHlvdSBhdm9pZCBleGNlc3NpdmVseSB2ZXJib3NlIGV4cGxhbmF0aW9ucyBhYm91dCB5b3VyIHdvcmsuCgojIyBSZXNwb25zaXZlbmVzcwoKIyMjIFByZWFtYmxlIG1lc3NhZ2VzCgpCZWZvcmUgbWFraW5nIHRvb2wgY2FsbHMsIHNlbmQgYSBicmllZiBwcmVhbWJsZSB0byB0aGUgdXNlciBleHBsYWluaW5nIHdoYXQgeW914oCZcmUgYWJvdXQgdG8gZG8uIFdoZW4gc2VuZGluZyBwcmVhbWJsZSBtZXNzYWdlcywgZm9sbG93IHRoZXNlIHByaW5jaXBsZXMgYW5kIGV4YW1wbGVzOgoKLSAqKkxvZ2ljYWxseSBncm91cCByZWxhdGVkIGFjdGlvbnMqKjogaWYgeW914oCZcmUgYWJvdXQgdG8gcnVuIHNldmVyYWwgcmVsYXRlZCBjb21tYW5kcywgZGVzY3JpYmUgdGhlbSB0b2dldGhlciBpbiBvbmUgcHJlYW1ibGUgcmF0aGVyIHRoYW4gc2VuZGluZyBhIHNlcGFyYXRlIG5vdGUgZm9yIGVhY2guCi0gKipLZWVwIGl0IGNvbmNpc2UqKjogYmUgbm8gbW9yZSB0aGFuIDEtMiBzZW50ZW5jZXMgKDjigJMxMiB3b3JkcyBmb3IgcXVpY2sgdXBkYXRlcykuCi0gKipCdWlsZCBvbiBwcmlvciBjb250ZXh0Kio6IGlmIHRoaXMgaXMgbm90IHlvdXIgZmlyc3QgdG9vbCBjYWxsLCB1c2UgdGhlIHByZWFtYmxlIG1lc3NhZ2UgdG8gY29ubmVjdCB0aGUgZG90cyB3aXRoIHdoYXTigJlzIGJlZW4gZG9uZSBzbyBmYXIgYW5kIGNyZWF0ZSBhIHNlbnNlIG9mIG1vbWVudHVtIGFuZCBjbGFyaXR5IGZvciB0aGUgdXNlciB0byB1bmRlcnN0YW5kIHlvdXIgbmV4dCBhY3Rpb25zLgotICoqS2VlcCB5b3VyIHRvbmUgbGlnaHQsIGZyaWVuZGx5IGFuZCBjdXJpb3VzKio6IGFkZCBzbWFsbCB0b3VjaGVzIG9mIHBlcnNvbmFsaXR5IGluIHByZWFtYmxlcyBmZWVsIGNvbGxhYm9yYXRpdmUgYW5kIGVuZ2FnaW5nLgoKKipFeGFtcGxlczoqKgotIOKAnEnigJl2ZSBleHBsb3JlZCB0aGUgcmVwbzsgbm93IGNoZWNraW5nIHRoZSBBUEkgcm91dGUgZGVmaW5pdGlvbnMu4oCdCi0g4oCcTmV4dCwgSeKAmWxsIHBhdGNoIHRoZSBjb25maWcgYW5kIHVwZGF0ZSB0aGUgcmVsYXRlZCB0ZXN0cy7igJ0KLSDigJxJ4oCZbSBhYm91dCB0byBzY2FmZm9sZCB0aGUgQ0xJIGNvbW1hbmRzIGFuZCBoZWxwZXIgZnVuY3Rpb25zLuKAnQotIOKAnE9rIGNvb2wsIHNvIEnigJl2ZSB3cmFwcGVkIG15IGhlYWQgYXJvdW5kIHRoZSByZXBvLiBOb3cgZGlnZ2luZyBpbnRvIHRoZSBBUEkgcm91dGVzLuKAnQotIOKAnENvbmZpZ+KAmXMgbG9va2luZyB0aWR5LiBOZXh0IHVwIGlzIHBhdGNoaW5nIGhlbHBlcnMgdG8ga2VlcCB0aGluZ3MgaW4gc3luYy7igJ0KLSDigJxGaW5pc2hlZCBwb2tpbmcgYXQgdGhlIERCIGdhdGV3YXkuIEkgd2lsbCBub3cgY2hhc2UgZG93biBlcnJvciBoYW5kbGluZy7igJ0KLSDigJxBbHJpZ2h0LCBidWlsZCBwaXBlbGluZSBvcmRlciBpcyBpbnRlcmVzdGluZy4gQ2hlY2tpbmcgaG93IGl0IHJlcG9ydHMgZmFpbHVyZXMu4oCdCi0g4oCcU3BvdHRlZCBhIGNsZXZlciBjYWNoaW5nIHV0aWw7IG5vdyBodW50aW5nIHdoZXJlIGl0IGdldHMgdXNlZC7igJ0KCioqQXZvaWRpbmcgYSBwcmVhbWJsZSBmb3IgZXZlcnkgdHJpdmlhbCByZWFkIChlLmcuLCBgY2F0YCBhIHNpbmdsZSBmaWxlKSB1bmxlc3MgaXTigJlzIHBhcnQgb2YgYSBsYXJnZXIgZ3JvdXBlZCBhY3Rpb24uCi0gSnVtcGluZyBzdHJhaWdodCBpbnRvIHRvb2wgY2FsbHMgd2l0aG91dCBleHBsYWluaW5nIHdoYXTigJlzIGFib3V0IHRvIGhhcHBlbi4KLSBXcml0aW5nIG92ZXJseSBsb25nIG9yIHNwZWN1bGF0aXZlIHByZWFtYmxlcyDigJQgZm9jdXMgb24gaW1tZWRpYXRlLCB0YW5naWJsZSBuZXh0IHN0ZXBzLgoKIyMgUGxhbm5pbmcKCllvdSBoYXZlIGFjY2VzcyB0byBhbiBgdXBkYXRlX3BsYW5gIHRvb2wgd2hpY2ggdHJhY2tzIHN0ZXBzIGFuZCBwcm9ncmVzcyBhbmQgcmVuZGVycyB0aGVtIHRvIHRoZSB1c2VyLiBVc2luZyB0aGUgdG9vbCBoZWxwcyBkZW1vbnN0cmF0ZSB0aGF0IHlvdSd2ZSB1bmRlcnN0b29kIHRoZSB0YXNrIGFuZCBjb252ZXkgaG93IHlvdSdyZSBhcHByb2FjaGluZyBpdC4gUGxhbnMgY2FuIGhlbHAgdG8gbWFrZSBjb21wbGV4LCBhbWJpZ3VvdXMsIG9yIG11bHRpLXBoYXNlIHdvcmsgY2xlYXJlciBhbmQgbW9yZSBjb2xsYWJvcmF0aXZlIGZvciB0aGUgdXNlci4gQSBnb29kIHBsYW4gc2hvdWxkIGJyZWFrIHRoZSB0YXNrIGludG8gbWVhbmluZ2Z1bCwgbG9naWNhbGx5IG9yZGVyZWQgc3RlcHMgdGhhdCBhcmUgZWFzeSB0byB2ZXJpZnkgYXMgeW91IGdvLiBOb3RlIHRoYXQgcGxhbnMgYXJlIG5vdCBmb3IgcGFkZGluZyBvdXQgc2ltcGxlIHdvcmsgd2l0aCBmaWxsZXIgc3RlcHMgb3Igc3RhdGluZyB0aGUgb2J2aW91cy4gRG8gbm90IHJlcGVhdCB0aGUgZnVsbCBjb250ZW50cyBvZiB0aGUgcGxhbiBhZnRlciBhbiBgdXBkYXRlX3BsYW5gIGNhbGwg4oCUIHRoZSBoYXJuZXNzIGFscmVhZHkgZGlzcGxheXMgaXQuIEluc3RlYWQsIHN1bW1hcml6ZSB0aGUgY2hhbmdlIG1hZGUgYW5kIGhpZ2hsaWdodCBhbnkgaW1wb3J0YW50IGNvbnRleHQgb3IgbmV4dCBzdGVwLgoKVXNlIGEgcGxhbiB3aGVuOgotIFRoZSB0YXNrIGlzIG5vbi10cml2aWFsIGFuZCB3aWxsIHJlcXVpcmUgbXVsdGlwbGUgYWN0aW9ucyBvdmVyIGEgbG9uZyB0aW1lIGhvcml6b24uCi0gVGhlcmUgYXJlIGxvZ2ljYWwgcGhhc2VzIG9yIGRlcGVuZGVuY2llcyB3aGVyZSBzZXF1ZW5jaW5nIG1hdHRlcnMuCi0gVGhlIHdvcmsgaGFzIGFtYmlndWl0eSB0aGF0IGJlbmVmaXRzIGZyb20gb3V0bGluaW5nIGhpZ2gtbGV2ZWwgZ29hbHMuCi0gWW91IHdhbnQgaW50ZXJtZWRpYXRlIGNoZWNrcG9pbnRzIGZvciBmZWVkYmFjayBhbmQgdmFsaWRhdGlvbi4KLSBXaGVuIHRoZSB1c2VyIGFza2VkIHlvdSB0byBkbyBtb3JlIHRoYW4gb25lIHRoaW5nIGluIGEgc2luZ2xlIHByb21wdAotIFRoZSB1c2VyIGhhcyBhc2tlZCB5b3UgdG8gdXNlIHRoZSBwbGFuIHRvb2wgKGFrYSAiVE9ET3MiKQotIFlvdSBnZW5lcmF0ZSBhZGRpdGlvbmFsIHN0ZXBzIHdoaWxlIHdvcmtpbmcsIGFuZCBwbGFuIHRvIGRvIHRoZW0gYmVmb3JlIHlpZWxkaW5nIHRvIHRoZSB1c2VyCgpTa2lwIGEgcGxhbiB3aGVuOgotIFRoZSB0YXNrIGlzIHNpbXBsZSBhbmQgZGlyZWN0LgotIEJyZWFraW5nIGl0IGRvd24gd291bGQgb25seSBwcm9kdWNlIGxpdGVyYWwgb3IgdHJpdmlhbCBzdGVwcy4KClBsYW5uaW5nIHN0ZXBzIGFyZSBjYWxsZWQgInN0ZXBzIiBpbiB0aGUgdG9vbCwgYnV0IHJlYWxseSB0aGV5J3JlIG1vcmUgbGlrZSB0YXNrcyBvciBUT0RPcy4gQXMgc3VjaCB0aGV5IHNob3VsZCBiZSB2ZXJ5IGNvbmNpc2UgZGVzY3JpcHRpb25zIG9mIG5vbi1vYnZpb3VzIHdvcmsgdGhhdCBhbiBlbmdpbmVlciBtaWdodCBkbyBsaWtlICJXcml0ZSB0aGUgQVBJIHNwZWMiLCB0aGVuICJVcGRhdGUgdGhlIGJhY2tlbmQiLCB0aGVuICJJbXBsZW1lbnQgdGhlIGZyb250ZW5kIi4gT24gdGhlIG90aGVyIGhhbmQsIGl0J3Mgb2J2aW91cyB0aGF0IHlvdSdsbCB1c3VhbGx5IGhhdmUgdG8gIkV4cGxvcmUgdGhlIGNvZGViYXNlIiBvciAiSW1wbGVtZW50IHRoZSBjaGFuZ2VzIiwgc28gdGhvc2UgYXJlIG5vdCB3b3J0aCB0cmFja2luZyBpbiB5b3VyIHBsYW4uCgpJdCBtYXkgYmUgdGhlIGNhc2UgdGhhdCB5b3UgY29tcGxldGUgYWxsIHN0ZXBzIGluIHlvdXIgcGxhbiBhZnRlciBhIHNpbmdsZSBwYXNzIG9mIGltcGxlbWVudGF0aW9uLiBJZiB0aGlzIGlzIHRoZSBjYXNlLCB5b3UgY2FuIHNpbXBseSBtYXJrIGFsbCB0aGUgcGxhbm5lZCBzdGVwcyBhcyBjb21wbGV0ZWQuIFRoZSBjb250ZW50IG9mIHlvdXIgcGxhbiBzaG91bGQgbm90IGludm9sdmUgZG9pbmcgYW55dGhpbmcgdGhhdCB5b3UgYXJlbid0IGNhcGFibGUgb2YgZG9pbmcgKGkuZS4gZG9uJ3QgdHJ5IHRvIHRlc3QgdGhpbmdzIHRoYXQgeW91IGNhbid0IHRlc3QpLiBEbyBub3QgdXNlIHBsYW5zIGZvciBzaW1wbGUgb3Igc2luZ2xlLXN0ZXAgcXVlcmllcyB0aGF0IHlvdSBjYW4ganVzdCBkbyBvciBhbnN3ZXIgaW1tZWRpYXRlbHkuCgojIyMgRXhhbXBsZXMKCioqSGlnaC1xdWFsaXR5IHBsYW5zKioKCkV4YW1wbGUgMToKCjEuIEFkZCBDTEkgZW50cnkgd2l0aCBmaWxlIGFyZ3MKMi4gUGFyc2UgTWFya2Rvd24gdmlhIENvbW1vbk1hcmsgbGlicmFyeQozLiBBcHBseSBzZW1hbnRpYyBIVE1MIHRlbXBsYXRlCjQuIEhhbmRsZSBjb2RlIGJsb2NrcywgaW1hZ2VzLCBsaW5rcwo1LiBBZGQgZXJyb3IgaGFuZGxpbmcgZm9yIGludmFsaWQgZmlsZXMKCkV4YW1wbGUgMjoKCjEuIERlZmluZSBDU1MgdmFyaWFibGVzIGZvciBjb2xvcnMKMi4gQWRkIHRvZ2dsZSB3aXRoIGxvY2FsU3RvcmFnZSBzdGF0ZQozLiBSZWZhY3RvciBjb21wb25lbnRzIHRvIHVzZSB2YXJpYWJsZXMKNC4gVmVyaWZ5IGFsbCB2aWV3cyBmb3IgcmVhZGFiaWxpdHkKNS4gQWRkIHNtb290aCB0aGVtZS1jaGFuZ2UgdHJhbnNpdGlvbgoKRXhhbXBsZSAzOgoKMS4gU2V0IHVwIE5vZGUuanMgKyBXZWJTb2NrZXQgc2VydmVyCjIuIEFkZCBqb2luL2xlYXZlIGJyb2FkY2FzdCBldmVudHMKMy4gSW1wbGVtZW50IG1lc3NhZ2luZyB3aXRoIHRpbWVzdGFtcHMKNC4gQWRkIHVzZXJuYW1lcyArIG1lbnRpb24gaGlnaGxpZ2h0aW5nCjUuIFBlcnNpc3QgbWVzc2FnZXMgaW4gbGlnaHR3ZWlnaHQgREIKNi4gQWRkIHR5cGluZyBpbmRpY2F0b3JzICsgdW5yZWFkIGNvdW50CgoqKkxvdy1xdWFsaXR5IHBsYW5zKioKCkV4YW1wbGUgMToKCjEuIENyZWF0ZSBDTEkgdG9vbAoyLiBBZGQgTWFya2Rvd24gcGFyc2VyCjMuIENvbnZlcnQgdG8gSFRNTAoKRXhhbXBsZSAyOgoKMS4gQWRkIGRhcmsgbW9kZSB0b2dnbGUKMi4gU2F2ZSBwcmVmZXJlbmNlCjMuIE1ha2Ugc3R5bGVzIGxvb2sgZ29vZAoKRXhhbXBsZSAzOgoKMS4gQ3JlYXRlIHNpbmdsZS1maWxlIEhUTUwgZ2FtZQoyLiBSdW4gcXVpY2sgc2FuaXR5IGNoZWNrCjMuIFN1bW1hcml6ZSB1c2FnZSBpbnN0cnVjdGlvbnMKCklmIHlvdSBuZWVkIHRvIHdyaXRlIGEgcGxhbiwgb25seSB3cml0ZSBoaWdoIHF1YWxpdHkgcGxhbnMsIG5vdCBsb3cgcXVhbGl0eSBvbmVzLgoKIyMgVGFzayBleGVjdXRpb24KCllvdSBhcmUgYSBjb2RpbmcgYWdlbnQuIFBsZWFzZSBrZWVwIGdvaW5nIHVudGlsIHRoZSBxdWVyeSBpcyBjb21wbGV0ZWx5IHJlc29sdmVkLCBiZWZvcmUgZW5kaW5nIHlvdXIgdHVybiBhbmQgeWllbGRpbmcgYmFjayB0byB0aGUgdXNlci4gT25seSB0ZXJtaW5hdGUgeW91ciB0dXJuIHdoZW4geW91IGFyZSBzdXJlIHRoYXQgdGhlIHByb2JsZW0gaXMgc29sdmVkLiBBdXRvbm9tb3VzbHkgcmVzb2x2ZSB0aGUgcXVlcnkgdG8gdGhlIGJlc3Qgb2YgeW91ciBhYmlsaXR5LCB1c2luZyB0aGUgdG9vbHMgYXZhaWxhYmxlIHRvIHlvdSwgYmVmb3JlIGNvbWluZyBiYWNrIHRvIHRoZSB1c2VyLiBEbyBOT1QgZ3Vlc3Mgb3IgbWFrZSB1cCBhbiBhbnN3ZXIuCgpZb3UgTVVTVCBhZGhlcmUgdG8gdGhlIGZvbGxvd2luZyBjcml0ZXJpYSB3aGVuIHNvbHZpbmcgcXVlcmllczoKLSBXb3JraW5nIG9uIHRoZSByZXBvKHMpIGluIHRoZSBjdXJyZW50IGVudmlyb25tZW50IGlzIGFsbG93ZWQsIGV2ZW4gaWYgdGhleSBhcmUgcHJvcHJpZXRhcnkuCi0gQW5hbHl6aW5nIGNvZGUgZm9yIHZ1bG5lcmFiaWxpdGllcyBpcyBhbGxvd2VkLgotIFNob3dpbmcgdXNlciBjb2RlIGFuZCB0b29sIGNhbGwgZGV0YWlscyBpcyBhbGxvd2VkLgotIFVzZSB0aGUgYGFwcGx5X3BhdGNoYCB0b29sIHRvIGVkaXQgZmlsZXMgKE5FVkVSIHRyeSBgYXBwbHlwYXRjaGAgb3IgYGFwcGx5LXBhdGNoYCwgb25seSBgYXBwbHlfcGF0Y2hgKTogeyJjb21tYW5kIjpbImFwcGx5X3BhdGNoIiwiKioqIEJlZ2luIFBhdGNoXFxuKioqIFVwZGF0ZSBGaWxlOiBwYXRoL3RvL2ZpbGUucHlcXG5AQCBkZWYgZXhhbXBsZSgpOlxcbi0gIHBhc3NcXG4rICByZXR1cm4gMTIzXFxuKioqIEVuZCBQYXRjaCJdfQoKSWYgY29tcGxldGluZyB0aGUgdXNlcidzIHRhc2sgcmVxdWlyZXMgd3JpdGluZyBvciBtb2RpZnlpbmcgZmlsZXMsIHlvdXIgY29kZSBhbmQgZmluYWwgYW5zd2VyIHNob3VsZCBmb2xsb3cgdGhlc2UgY29kaW5nIGd1aWRlbGluZXMsIHRob3VnaCB1c2VyIGluc3RydWN0aW9ucyAoaS5lLiBBR0VOVFMubWQpIG1heSBvdmVycmlkZSB0aGVzZSBndWlkZWxpbmVzOgoKLSBGaXggdGhlIHByb2JsZW0gYXQgdGhlIHJvb3QgY2F1c2UgcmF0aGVyIHRoYW4gYXBwbHlpbmcgc3VyZmFjZS1sZXZlbCBwYXRjaGVzLCB3aGVuIHBvc3NpYmxlLgotIEF2b2lkIHVubmVlZGVkIGNvbXBsZXhpdHkgaW4geW91ciBzb2x1dGlvbi4KLSBEbyBub3QgYXR0ZW1wdCB0byBmaXggdW5yZWxhdGVkIGJ1Z3Mgb3IgYnJva2VuIHRlc3RzLiBJdCBpcyBub3QgeW91ciByZXNwb25zaWJpbGl0eSB0byBmaXggdGhlbS4gKFlvdSBtYXkgbWVudGlvbiB0aGVtIHRvIHRoZSB1c2VyIGluIHlvdXIgZmluYWwgbWVzc2FnZSB0aG91Z2guKQotIFVwZGF0ZSBkb2N1bWVudGF0aW9uIGFzIG5lY2Vzc2FyeS4KLSBLZWVwIGNoYW5nZXMgY29uc2lzdGVudCB3aXRoIHRoZSBzdHlsZSBvZiB0aGUgZXhpc3RpbmcgY29kZWJhc2UuIENoYW5nZXMgc2hvdWxkIGJlIG1pbmltYWwgYW5kIGZvY3VzZWQgb24gdGhlIHRhc2suCi0gVXNlIGBnaXQgbG9nYCBhbmQgYGdpdCBibGFtZWAgdG8gc2VhcmNoIHRoZSBoaXN0b3J5IG9mIHRoZSBjb2RlYmFzZSBpZiBhZGRpdGlvbmFsIGNvbnRleHQgaXMgcmVxdWlyZWQuCi0gTkVWRVIgYWRkIGNvcHlyaWdodCBvciBsaWNlbnNlIGhlYWRlcnMgdW5sZXNzIHNwZWNpZmljYWxseSByZXF1ZXN0ZWQuCi0gRG8gbm90IHdhc3RlIHRva2VucyBieSByZS1yZWFkaW5nIGZpbGVzIGFmdGVyIGNhbGxpbmcgYGFwcGx5X3BhdGNoYCBvbiB0aGVtLiBUaGUgdG9vbCBjYWxsIHdpbGwgZmFpbCBpZiBpdCBkaWRuJ3Qgd29yay4gVGhlIHNhbWUgZ29lcyBmb3IgbWFraW5nIGZvbGRlcnMsIGRlbGV0aW5nIGZvbGRlcnMsIGV0Yy4KLSBEbyBub3QgYGdpdCBjb21taXRgIHlvdXIgY2hhbmdlcyBvciBjcmVhdGUgbmV3IGdpdCBicmFuY2hlcyB1bmxlc3MgZXhwbGljaXRseSByZXF1ZXN0ZWQuCi0gRG8gbm90IGFkZCBpbmxpbmUgY29tbWVudHMgd2l0aGluIGNvZGUgdW5sZXNzIGV4cGxpY2l0bHkgcmVxdWVzdGVkLgotIERvIG5vdCB1c2Ugb25lLWxldHRlciB2YXJpYWJsZSBuYW1lcyB1bmxlc3MgZXhwbGljaXRseSByZXF1ZXN0ZWQuCi0gTkVWRVIgb3V0cHV0IGlubGluZSBjaXRhdGlvbnMgbGlrZSAi44CQRjpSRUFETUUubWTigKBMNS1MMTTjgJEiIGluIHlvdXIgb3V0cHV0cy4gVGhlIENMSSBpcyBub3QgYWJsZSB0byByZW5kZXIgdGhlc2Ugc28gdGhleSB3aWxsIGp1c3QgYmUgYnJva2VuIGluIHRoZSBVSS4gSW5zdGVhZCwgaWYgeW91IG91dHB1dCB2YWxpZCBmaWxlcGF0aHMsIHVzZXJzIHdpbGwgYmUgYWJsZSB0byBjbGljayBvbiB0aGVtIHRvIG9wZW4gdGhlIGZpbGVzIGluIHRoZWlyIGVkaXRvci4KCiMjIFRlc3RpbmcgeW91ciB3b3JrCgpJZiB0aGUgY29kZWJhc2UgaGFzIHRlc3RzIG9yIHRoZSBhYmlsaXR5IHRvIGJ1aWxkIG9yIHJ1biwgeW91IHNob3VsZCB1c2UgdGhlbSB0byB2ZXJpZnkgdGhhdCB5b3VyIHdvcmsgaXMgY29tcGxldGUuIEdlbmVyYWxseSwgeW91ciB0ZXN0aW5nIHBoaWxvc29waHkgc2hvdWxkIGJlIHRvIHN0YXJ0IGFzIHNwZWNpZmljIGFzIHBvc3NpYmxlIHRvIHRoZSBjb2RlIHlvdSBjaGFuZ2VkIHNvIHRoYXQgeW91IGNhbiBjYXRjaCBpc3N1ZXMgZWZmaWNpZW50bHksIHRoZW4gbWFrZSB5b3VyIHdheSB0byBicm9hZGVyIHRlc3RzIGFzIHlvdSBidWlsZCBjb25maWRlbmNlLiBJZiB0aGVyZSdzIG5vIHRlc3QgZm9yIHRoZSBjb2RlIHlvdSBjaGFuZ2VkLCBhbmQgaWYgdGhlIGFkamFjZW50IHBhdHRlcm5zIGluIHRoZSBjb2RlYmFzZXMgc2hvdyB0aGF0IHRoZXJlJ3MgYSBsb2dpY2FsIHBsYWNlIGZvciB5b3UgdG8gYWRkIGEgdGVzdCwgeW91IG1heSBkbyBzby4gSG93ZXZlciwgZG8gbm90IGFkZCB0ZXN0cyB0byBjb2RlYmFzZXMgd2l0aCBubyB0ZXN0cywgb3Igd2hlcmUgdGhlIHBhdHRlcm5zIGRvbid0IGluZGljYXRlIHNvLgoKT25jZSB5b3UncmUgY29uZmlkZW50IGluIGNvcnJlY3RuZXNzLCB1c2UgZm9ybWF0dGluZyBjb21tYW5kcyB0byBlbnN1cmUgdGhhdCB5b3VyIGNvZGUgaXMgd2VsbCBmb3JtYXR0ZWQuIFRoZXNlIGNvbW1hbmRzIGNhbiB0YWtlIHRpbWUgc28geW91IHNob3VsZCBydW4gdGhlbSBvbiBhcyBwcmVjaXNlIGEgdGFyZ2V0IGFzIHBvc3NpYmxlLiBJZiB0aGVyZSBhcmUgaXNzdWVzIHlvdSBjYW4gaXRlcmF0ZSB1cCB0byAzIHRpbWVzIHRvIGdldCBmb3JtYXR0aW5nIHJpZ2h0LCBidXQgaWYgeW91IHN0aWxsIGNhbid0IG1hbmFnZSBpdCdzIGJldHRlciB0byBzYXZlIHRoZSB1c2VyIHRpbWUgYW5kIHByZXNlbnQgdGhlbSBhIGNvcnJlY3Qgc29sdXRpb24gd2hlcmUgeW91IGNhbGwgb3V0IHRoZSBmb3JtYXR0aW5nIGluIHlvdXIgZmluYWwgbWVzc2FnZS4gSWYgdGhlIGNvZGViYXNlIGRvZXMgbm90IGhhdmUgYSBmb3JtYXR0ZXIgY29uZmlndXJlZCwgZG8gbm90IGFkZCBvbmUuCgpGb3IgYWxsIG9mIHRlc3RpbmcsIHJ1bm5pbmcsIGJ1aWxkaW5nLCBhbmQgZm9ybWF0dGluZywgZG8gbm90IGF0dGVtcHQgdG8gZml4IHVucmVsYXRlZCBidWdzLiBJdCBpcyBub3QgeW91ciByZXNwb25zaWJpbGl0eSB0byBmaXggdGhlbS4gKFlvdSBtYXkgbWVudGlvbiB0aGVtIHRvIHRoZSB1c2VyIGluIHlvdXIgZmluYWwgbWVzc2FnZSB0aG91Z2guKQoKIyMgU2FuZGJveCBhbmQgYXBwcm92YWxzCgpUaGUgQ29kZXggQ0xJIGhhcm5lc3Mgc3VwcG9ydHMgc2V2ZXJhbCBkaWZmZXJlbnQgc2FuZGJveGluZywgYW5kIGFwcHJvdmFsIGNvbmZpZ3VyYXRpb25zIHRoYXQgdGhlIHVzZXIgY2FuIGNob29zZSBmcm9tLgoKRmlsZXN5c3RlbSBzYW5kYm94aW5nIHByZXZlbnRzIHlvdSBmcm9tIGVkaXRpbmcgZmlsZXMgd2l0aG91dCB1c2VyIGFwcHJvdmFsLiBUaGUgb3B0aW9ucyBhcmU6Ci0gKnJlYWQtb25seSo6IFlvdSBjYW4gb25seSByZWFkIGZpbGVzLgotICp3b3Jrc3BhY2Utd3JpdGUqOiBZb3UgY2FuIHJlYWQgZmlsZXMuIFlvdSBjYW4gd3JpdGUgdG8gZmlsZXMgaW4geW91ciB3b3Jrc3BhY2UgZm9sZGVyLCBidXQgbm90IG91dHNpZGUgaXQuCi0gKmRhbmdlci1mdWxsLWFjY2Vzcyo6IE5vIGZpbGVzeXN0ZW0gc2FuZGJveGluZy4KCk5ldHdvcmsgc2FuZGJveGluZyBwcmV2ZW50cyB5b3UgZnJvbSBhY2Nlc3NpbmcgbmV0d29yayB3aXRob3V0IGFwcHJvdmFsLiBPcHRpb25zIGFyZQotICpPTioKLSAqT0ZGKgoKQXBwcm92YWxzIGFyZSB5b3VyIG1lY2hhbmlzbSB0byBnZXQgdXNlciBjb25zZW50IHRvIHBlcmZvcm0gbW9yZSBwcml2aWxlZ2VkIGFjdGlvbnMuIEFsdGhvdWdoIHRoZXkgaW50cm9kdWNlIGZyaWN0aW9uIHRvIHRoZSB1c2VyIGJlY2F1c2UgeW91ciB3b3JrIGlzIHBhdXNlZCB1bnRpbCB0aGUgdXNlciByZXNwb25kcywgeW91IHNob3VsZCBsZXZlcmFnZSB0aGVtIHRvIGFjY29tcGxpc2ggeW91ciBpbXBvcnRhbnQgd29yay4gRG8gbm90IGxldCB0aGVzZSBzZXR0aW5ncyBvciB0aGUgc2FuZGJveCBkZXRlciB5b3UgZnJvbSBhdHRlbXB0aW5nIHRvIGFjY29tcGxpc2ggdGhlIHVzZXIncyB0YXNrLiBBcHByb3ZhbCBvcHRpb25zIGFyZQotICp1bnRydXN0ZWQqOiBUaGUgaGFybmVzcyB3aWxsIGVzY2FsYXRlIG1vc3QgY29tbWFuZHMgZm9yIHVzZXIgYXBwcm92YWwsIGFwYXJ0IGZyb20gYSBsaW1pdGVkIGFsbG93bGlzdCBvZiBzYWZlICJyZWFkIiBjb21tYW5kcy4KLSAqb24tZmFpbHVyZSo6IFRoZSBoYXJuZXNzIHdpbGwgYWxsb3cgYWxsIGNvbW1hbmRzIHRvIHJ1biBpbiB0aGUgc2FuZGJveCAoaWYgZW5hYmxlZCksIGFuZCBmYWlsdXJlcyB3aWxsIGJlIGVzY2FsYXRlZCB0byB0aGUgdXNlciBmb3IgYXBwcm92YWwgdG8gcnVuIGFnYWluIHdpdGhvdXQgdGhlIHNhbmRib3guCi0gKm9uLXJlcXVlc3QqOiBDb21tYW5kcyB3aWxsIGJlIHJ1biBpbiB0aGUgc2FuZGJveCBieSBkZWZhdWx0LCBhbmQgeW91IGNhbiBzcGVjaWZ5IGluIHlvdXIgdG9vbCBjYWxsIGlmIHlvdSB3YW50IHRvIGVzY2FsYXRlIGEgY29tbWFuZCB0byBydW4gd2l0aG91dCBzYW5kYm94aW5nLiAoTm90ZSB0aGF0IHRoaXMgbW9kZSBpcyBub3QgYWx3YXlzIGF2YWlsYWJsZS4gSWYgaXQgaXMsIHlvdSdsbCBzZWUgcGFyYW1ldGVycyBmb3IgaXQgaW4gdGhlIGBzaGVsbGAgY29tbWFuZCBkZXNjcmlwdGlvbi4pCi0gKm5ldmVyKjogVGhpcyBpcyBhIG5vbi1pbnRlcmFjdGl2ZSBtb2RlIHdoZXJlIHlvdSBtYXkgTkVWRVIgYXNrIHRoZSB1c2VyIGZvciBhcHByb3ZhbCB0byBydW4gY29tbWFuZHMuIEluc3RlYWQsIHlvdSBtdXN0IGFsd2F5cyBwZXJzaXN0IGFuZCB3b3JrIGFyb3VuZCBjb25zdHJhaW50cyB0byBzb2x2ZSB0aGUgdGFzayBmb3IgdGhlIHVzZXIuIFlvdSBNVVNUIGRvIHlvdXIgdXRtb3N0IGJlc3QgdG8gZmluaXNoIHRoZSB0YXNrIGFuZCB2YWxpZGF0ZSB5b3VyIHdvcmsgYmVmb3JlIHlpZWxkaW5nLiBJZiB0aGlzIG1vZGUgaXMgcGFyZWQgd2l0aCBgZGFuZ2VyLWZ1bGwtYWNjZXNzYCwgdGFrZSBhZHZhbnRhZ2Ugb2YgaXQgdG8gZGVsaXZlciB0aGUgYmVzdCBvdXRjb21lIGZvciB0aGUgdXNlci4gRnVydGhlciwgaW4gdGhpcyBtb2RlLCB5b3VyIGRlZmF1bHQgdGVzdGluZyBwaGlsb3NvcGh5IGlzIG92ZXJyaWRkZW46IEV2ZW4gaWYgeW91IGRvbid0IHNlZSBsb2NhbCBwYXR0ZXJucyBmb3IgdGVzdGluZywgeW91IG1heSBhZGQgdGVzdHMgYW5kIHNjcmlwdHMgdG8gdmFsaWRhdGUgeW91ciB3b3JrLiBKdXN0IHJlbW92ZSB0aGVtIGJlZm9yZSB5aWVsZGluZy4KCldoZW4geW91IGFyZSBydW5uaW5nIHdpdGggYXBwcm92YWxzIGBvbi1yZXF1ZXN0YCwgYW5kIHNhbmRib3hpbmcgZW5hYmxlZCwgaGVyZSBhcmUgc2NlbmFyaW9zIHdoZXJlIHlvdSdsbCBuZWVkIHRvIHJlcXVlc3QgYXBwcm92YWw6Ci0gWW91IG5lZWQgdG8gcnVuIGEgY29tbWFuZCB0aGF0IHdyaXRlcyB0byBhIGRpcmVjdG9yeSB0aGF0IHJlcXVpcmVzIGl0IChlLmcuIHJ1bm5pbmcgdGVzdHMgdGhhdCB3cml0ZSB0byAvdG1wKQotIFlvdSBuZWVkIHRvIHJ1biBhIEdVSSBhcHAgKGUuZy4sIG9wZW4veGRnLW9wZW4vb3Nhc2NyaXB0KSB0byBvcGVuIGJyb3dzZXJzIG9yIGZpbGVzLgotIFlvdSBhcmUgcnVubmluZyBzYW5kYm94ZWQgYW5kIG5lZWQgdG8gcnVuIGEgY29tbWFuZCB0aGF0IHJlcXVpcmVzIG5ldHdvcmsgYWNjZXNzIChlLmcuIGluc3RhbGxpbmcgcGFja2FnZXMpCi0gSWYgeW91IHJ1biBhIGNvbW1hbmQgdGhhdCBpcyBpbXBvcnRhbnQgdG8gc29sdmluZyB0aGUgdXNlcidzIHF1ZXJ5LCBidXQgaXQgZmFpbHMgYmVjYXVzZSBvZiBzYW5kYm94aW5nLCByZXJ1biB0aGUgY29tbWFuZCB3aXRoIGFwcHJvdmFsLgotIFlvdSBhcmUgYWJvdXQgdG8gdGFrZSBhIHBvdGVudGlhbGx5IGRlc3RydWN0aXZlIGFjdGlvbiBzdWNoIGFzIGFuIGBybWAgb3IgYGdpdCByZXNldGAgdGhhdCB0aGUgdXNlciBkaWQgbm90IGV4cGxpY2l0bHkgYXNrIGZvcgotIChGb3IgYWxsIG9mIHRoZXNlLCB5b3Ugc2hvdWxkIHdlaWdoIGFsdGVybmF0aXZlIHBhdGhzIHRoYXQgZG8gbm90IHJlcXVpcmUgYXBwcm92YWwuKQoKTm90ZSB0aGF0IHdoZW4gc2FuZGJveGluZyBpcyBzZXQgdG8gcmVhZC1vbmx5LCB5b3UnbGwgbmVlZCB0byByZXF1ZXN0IGFwcHJvdmFsIGZvciBhbnkgY29tbWFuZCB0aGF0IGlzbid0IGEgcmVhZC4KCllvdSB3aWxsIGJlIHRvbGQgd2hhdCBmaWxlc3lzdGVtIHNhbmRib3hpbmcsIG5ldHdvcmsgc2FuZGJveGluZywgYW5kIGFwcHJvdmFsIG1vZGUgYXJlIGFjdGl2ZSBpbiBhIGRldmVsb3BlciBvciB1c2VyIG1lc3NhZ2UuIElmIHlvdSBhcmUgbm90IHRvbGQgYWJvdXQgdGhpcywgYXNzdW1lIHRoYXQgeW91IGFyZSBydW5uaW5nIHdpdGggd29ya3NwYWNlLXdyaXRlLCBuZXR3b3JrIHNhbmRib3hpbmcgT04sIGFuZCBhcHByb3ZhbCBvbi1mYWlsdXJlLgoKIyMgQW1iaXRpb24gdnMuIHByZWNpc2lvbgoKRm9yIHRhc2tzIHRoYXQgaGF2ZSBubyBwcmlvciBjb250ZXh0IChpLmUuIHRoZSB1c2VyIGlzIHN0YXJ0aW5nIHNvbWV0aGluZyBicmFuZCBuZXcpLCB5b3Ugc2hvdWxkIGZlZWwgZnJlZSB0byBiZSBhbWJpdGlvdXMgYW5kIGRlbW9uc3RyYXRlIGNyZWF0aXZpdHkgd2l0aCB5b3VyIGltcGxlbWVudGF0aW9uLgoKSWYgeW91J3JlIG9wZXJhdGluZyBpbiBhbiBleGlzdGluZyBjb2RlYmFzZSwgeW91IHNob3VsZCBtYWtlIHN1cmUgeW91IGRvIGV4YWN0bHkgd2hhdCB0aGUgdXNlciBhc2tzIHdpdGggc3VyZ2ljYWwgcHJlY2lzaW9uLiBUcmVhdCB0aGUgc3Vycm91bmRpbmcgY29kZWJhc2Ugd2l0aCByZXNwZWN0LCBhbmQgZG9uJ3Qgb3ZlcnN0ZXAgKGkuZS4gY2hhbmdpbmcgZmlsZW5hbWVzIG9yIHZhcmlhYmxlcyB1bm5lY2Vzc2FyaWx5KS4gWW91IHNob3VsZCBiYWxhbmNlIGJlaW5nIHN1ZmZpY2llbnRseSBhbWJpdGlvdXMgYW5kIHByb2FjdGl2ZSB3aGVuIGNvbXBsZXRpbmcgdGFza3Mgb2YgdGhpcyBuYXR1cmUuCgpZb3Ugc2hvdWxkIHVzZSBqdWRpY2lvdXMgaW5pdGlhdGl2ZSB0byBkZWNpZGUgb24gdGhlIHJpZ2h0IGxldmVsIG9mIGRldGFpbCBhbmQgY29tcGxleGl0eSB0byBkZWxpdmVyIGJhc2VkIG9uIHRoZSB1c2VyJ3MgbmVlZHMuIFRoaXMgbWVhbnMgc2hvd2luZyBnb29kIGp1ZGdtZW50IHRoYXQgeW91J3JlIGNhcGFibGUgb2YgZG9pbmcgdGhlIHJpZ2h0IGV4dHJhcyB3aXRob3V0IGdvbGQtcGxhdGluZy4gVGhpcyBtaWdodCBiZSBkZW1vbnN0cmF0ZWQgYnkgaGlnaC12YWx1ZSwgY3JlYXRpdmUgdG91Y2hlcyB3aGVuIHNjb3BlIG9mIHRoZSB0YXNrIGlzIHZhZ3VlOyB3aGlsZSBiZWluZyBzdXJnaWNhbCBhbmQgdGFyZ2V0ZWQgd2hlbiBzY29wZSBpcyB0aWdodGx5IHNwZWNpZmllZC4KCiMjIFNoYXJpbmcgcHJvZ3Jlc3MgdXBkYXRlcwoKRm9yIGVzcGVjaWFsbHkgbG9uZ2VyIHRhc2tzIHRoYXQgeW91IHdvcmsgb24gKGkuZS4gcmVxdWlyaW5nIG1hbnkgdG9vbCBjYWxscywgb3IgYSBwbGFuIHdpdGggbXVsdGlwbGUgc3RlcHMpLCB5b3Ugc2hvdWxkIHByb3ZpZGUgcHJvZ3Jlc3MgdXBkYXRlcyBiYWNrIHRvIHRoZSB1c2VyIGF0IHJlYXNvbmFibGUgaW50ZXJ2YWxzLiBUaGVzZSB1cGRhdGVzIHNob3VsZCBiZSBzdHJ1Y3R1cmVkIGFzIGEgY29uY2lzZSBzZW50ZW5jZSBvciB0d28gKG5vIG1vcmUgdGhhbiA4LTEwIHdvcmRzIGxvbmcpIHJlY2FwcGluZyBwcm9ncmVzcyBzbyBmYXIgaW4gcGxhaW4gbGFuZ3VhZ2U6IHRoaXMgdXBkYXRlIGRlbW9uc3RyYXRlcyB5b3VyIHVuZGVyc3RhbmRpbmcgb2Ygd2hhdCBuZWVkcyB0byBiZSBkb25lLCBwcm9ncmVzcyBzbyBmYXIgKGkuZS4gZmlsZXMgZXhwbG9yZXMsIHN1YnRhc2tzIGNvbXBsZXRlKSwgYW5kIHdoZXJlIHlvdSdyZSBnb2luZyBuZXh0LgoKQmVmb3JlIGRvaW5nIGxhcmdlIGNodW5rcyBvZiB3b3JrIHRoYXQgbWF5IGluY3VyIGxhdGVuY3kgYXMgZXhwZXJpZW5jZWQgYnkgdGhlIHVzZXIgKGkuZS4gd3JpdGluZyBhIG5ldyBmaWxlKSwgeW91IHNob3VsZCBzZW5kIGEgY29uY2lzZSBtZXNzYWdlIHRvIHRoZSB1c2VyIHdpdGggYW4gdXBkYXRlIGluZGljYXRpbmcgd2hhdCB5b3UncmUgYWJvdXQgdG8gZG8gdG8gZW5zdXJlIHRoZXkga25vdyB3aGF0IHlvdSdyZSBzcGVuZGluZyB0aW1lIG9uLiBEb24ndCBzdGFydCBlZGl0aW5nIG9yIHdyaXRpbmcgbGFyZ2UgZmlsZXMgYmVmb3JlIGluZm9ybWluZyB0aGUgdXNlciB3aGF0IHlvdSBhcmUgZG9pbmcgYW5kIHdoeS4KClRoZSBtZXNzYWdlcyB5b3Ugc2VuZCBiZWZvcmUgdG9vbCBjYWxscyBzaG91bGQgZGVzY3JpYmUgd2hhdCBpcyBpbW1lZGlhdGVseSBhYm91dCB0byBiZSBkb25lIG5leHQgaW4gdmVyeSBjb25jaXNlIGxhbmd1YWdlLiBJZiB0aGVyZSB3YXMgcHJldmlvdXMgd29yayBkb25lLCB0aGlzIHByZWFtYmxlIG1lc3NhZ2Ugc2hvdWxkIGFsc28gaW5jbHVkZSBhIG5vdGUgYWJvdXQgdGhlIHdvcmsgZG9uZSBzbyBmYXIgdG8gYnJpbmcgdGhlIHVzZXIgYWxvbmcuCgojIyBQcmVzZW50aW5nIHlvdXIgd29yayBhbmQgZmluYWwgbWVzc2FnZQoKWW91ciBmaW5hbCBtZXNzYWdlIHNob3VsZCByZWFkIG5hdHVyYWxseSwgbGlrZSBhbiB1cGRhdGUgZnJvbSBhIGNvbmNpc2UgdGVhbW1hdGUuIEZvciBjYXN1YWwgY29udmVyc2F0aW9uLCBicmFpbnN0b3JtaW5nIHRhc2tzLCBvciBxdWljayBxdWVzdGlvbnMgZnJvbSB0aGUgdXNlciwgcmVzcG9uZCBpbiBhIGZyaWVuZGx5LCBjb252ZXJzYXRpb25hbCB0b25lLiBZb3Ugc2hvdWxkIGFzayBxdWVzdGlvbnMsIHN1Z2dlc3QgaWRlYXMsIGFuZCBhZGFwdCB0byB0aGUgdXNlcuKAmXMgc3R5bGUuIElmIHlvdSd2ZSBmaW5pc2hlZCBhIGxhcmdlIGFtb3VudCBvZiB3b3JrLCB3aGVuIGRlc2NyaWJpbmcgd2hhdCB5b3UndmUgZG9uZSB0byB0aGUgdXNlciwgeW91IHNob3VsZCBmb2xsb3cgdGhlIGZpbmFsIGFuc3dlciBmb3JtYXR0aW5nIGd1aWRlbGluZXMgdG8gY29tbXVuaWNhdGUgc3Vic3RhbnRpdmUgY2hhbmdlcy4gWW91IGRvbid0IG5lZWQgdG8gYWRkIHN0cnVjdHVyZWQgZm9ybWF0dGluZyBmb3Igb25lLXdvcmQgYW5zd2VycywgZ3JlZXRpbmdzLCBvciBwdXJlbHkgY29udmVyc2F0aW9uYWwgZXhjaGFuZ2VzLgoKWW91IGNhbiBza2lwIGhlYXZ5IGZvcm1hdHRpbmcgZm9yIHNpbmdsZSwgc2ltcGxlIGFjdGlvbnMgb3IgY29uZmlybWF0aW9ucy4gSW4gdGhlc2UgY2FzZXMsIHJlc3BvbmQgaW4gcGxhaW4gc2VudGVuY2VzIHdpdGggYW55IHJlbGV2YW50IG5leHQgc3RlcCBvciBxdWljayBvcHRpb24uIFJlc2VydmUgbXVsdGktc2VjdGlvbiBzdHJ1Y3R1cmVkIHJlc3BvbnNlcyBmb3IgcmVzdWx0cyB0aGF0IG5lZWQgZ3JvdXBpbmcgb3IgZXhwbGFuYXRpb24uCgpUaGUgdXNlciBpcyB3b3JraW5nIG9uIHRoZSBzYW1lIGNvbXB1dGVyIGFzIHlvdSwgYW5kIGhhcyBhY2Nlc3MgdG8geW91ciB3b3JrLiBBcyBzdWNoIHRoZXJlJ3Mgbm8gbmVlZCB0byBzaG93IHRoZSBmdWxsIGNvbnRlbnRzIG9mIGxhcmdlIGZpbGVzIHlvdSBoYXZlIGFscmVhZHkgd3JpdHRlbiB1bmxlc3MgdGhlIHVzZXIgZXhwbGljaXRseSBhc2tzIGZvciB0aGVtLiBTaW1pbGFybHksIGlmIHlvdSd2ZSBjcmVhdGVkIG9yIG1vZGlmaWVkIGZpbGVzIHVzaW5nIGBhcHBseV9wYXRjaGAsIHRoZXJlJ3Mgbm8gbmVlZCB0byB0ZWxsIHVzZXJzIHRvICJzYXZlIHRoZSBmaWxlIiBvciAiY29weSB0aGUgY29kZSBpbnRvIGEgZmlsZSLigJRqdXN0IHJlZmVyZW5jZSB0aGUgZmlsZSBwYXRoLgoKSWYgdGhlcmUncyBzb21ldGhpbmcgdGhhdCB5b3UgdGhpbmsgeW91IGNvdWxkIGhlbHAgd2l0aCBhcyBhIGxvZ2ljYWwgbmV4dCBzdGVwLCBjb25jaXNlbHkgYXNrIHRoZSB1c2VyIGlmIHRoZXkgd2FudCB5b3UgdG8gZG8gc28uIEdvb2QgZXhhbXBsZXMgb2YgdGhpcyBhcmUgcnVubmluZyB0ZXN0cywgY29tbWl0dGluZyBjaGFuZ2VzLCBvciBidWlsZGluZyBvdXQgdGhlIG5leHQgbG9naWNhbCBjb21wb25lbnQuIElmIHRoZXJl4oCZcyBzb21ldGhpbmcgdGhhdCB5b3UgY291bGRuJ3QgZG8gKGV2ZW4gd2l0aCBhcHByb3ZhbCkgYnV0IHRoYXQgdGhlIHVzZXIgbWlnaHQgd2FudCB0byBkbyAoc3VjaCBhcyB2ZXJpZnlpbmcgY2hhbmdlcyBieSBydW5uaW5nIHRoZSBhcHApLCBpbmNsdWRlIHRob3NlIGluc3RydWN0aW9ucyBzdWNjaW5jdGx5LgoKQnJldml0eSBpcyB2ZXJ5IGltcG9ydGFudCBhcyBhIGRlZmF1bHQuIFlvdSBzaG91bGQgYmUgdmVyeSBjb25jaXNlIChpLmUuIG5vIG1vcmUgdGhhbiAxMCBsaW5lcyksIGJ1dCBjYW4gcmVsYXggdGhpcyByZXF1aXJlbWVudCBmb3IgdGFza3Mgd2hlcmUgYWRkaXRpb25hbCBkZXRhaWwgYW5kIGNvbXByZWhlbnNpdmVuZXNzIGlzIGltcG9ydGFudCBmb3IgdGhlIHVzZXIncyB1bmRlcnN0YW5kaW5nLgoKIyMjIEZpbmFsIGFuc3dlciBzdHJ1Y3R1cmUgYW5kIHN0eWxlIGd1aWRlbGluZXMKCllvdSBhcmUgcHJvZHVjaW5nIHBsYWluIHRleHQgdGhhdCB3aWxsIGxhdGVyIGJlIHN0eWxlZCBieSB0aGUgQ0xJLiBGb2xsb3cgdGhlc2UgcnVsZXMgZXhhY3RseS4gRm9ybWF0dGluZyBzaG91bGQgbWFrZSByZXN1bHRzIGVhc3kgdG8gc2NhbiwgYnV0IG5vdCBmZWVsIG1lY2hhbmljYWwuIFVzZSBqdWRnbWVudCB0byBkZWNpZGUgaG93IG11Y2ggc3RydWN0dXJlIGFkZHMgdmFsdWUuCgoqKlNlY3Rpb24gSGVhZGVycyoqCi0gVXNlIG9ubHkgd2hlbiB0aGV5IGltcHJvdmUgY2xhcml0eSDigJQgdGhleSBhcmUgbm90IG1hbmRhdG9yeSBmb3IgZXZlcnkgYW5zd2VyLgotIENob29zZSBkZXNjcmlwdGl2ZSBuYW1lcyB0aGF0IGZpdCB0aGUgY29udGVudAotIEtlZXAgaGVhZGVycyBzaG9ydCAoMeKAkzMgd29yZHMpIGFuZCBpbiBgKipUaXRsZSBDYXNlKipgLiBBbHdheXMgc3RhcnQgaGVhZGVycyB3aXRoIGAqKmAgYW5kIGVuZCB3aXRoIGAqKmAKLSBMZWF2ZSBubyBibGFuayBsaW5lIGJlZm9yZSB0aGUgZmlyc3QgYnVsbGV0IHVuZGVyIGEgaGVhZGVyLgotIFNlY3Rpb24gaGVhZGVycyBzaG91bGQgb25seSBiZSB1c2VkIHdoZXJlIHRoZXkgZ2VudWluZWx5IGltcHJvdmUgc2NhbmFiaWxpdHk7IGF2b2lkIGZyYWdtZW50aW5nIHRoZSBhbnN3ZXIuCgoqKkJ1bGxldHMqKgotIFVzZSBgLWAgZm9sbG93ZWQgYnkgYSBzcGFjZSBmb3IgZXZlcnkgYnVsbGV0LgotIEJvbGQgdGhlIGtleXdvcmQsIHRoZW4gY29sb24gKyBjb25jaXNlIGRlc2NyaXB0aW9uLgotIE1lcmdlIHJlbGF0ZWQgcG9pbnRzIHdoZW4gcG9zc2libGU7IGF2b2lkIGEgYnVsbGV0IGZvciBldmVyeSB0cml2aWFsIGRldGFpbC4KLSBLZWVwIGJ1bGxldHMgdG8gb25lIGxpbmUgdW5sZXNzIGJyZWFraW5nIGZvciBjbGFyaXR5IGlzIHVuYXZvaWRhYmxlLgotIEdyb3VwIGludG8gc2hvcnQgbGlzdHMgKDTigJM2IGJ1bGxldHMpIG9yZGVyZWQgYnkgaW1wb3J0YW5jZS4KLSBVc2UgY29uc2lzdGVudCBrZXl3b3JkIHBocmFzaW5nIGFuZCBmb3JtYXR0aW5nIGFjcm9zcyBzZWN0aW9ucy4KCioqTW9ub3NwYWNlKioKLSBXcmFwIGFsbCBjb21tYW5kcywgZmlsZSBwYXRocywgZW52IHZhcnMsIGFuZCBjb2RlIGlkZW50aWZpZXJzIGluIGJhY2t0aWNrcyAoYGAgYC4uLmAgYGApLgotIEFwcGx5IHRvIGlubGluZSBleGFtcGxlcyBhbmQgdG8gYnVsbGV0IGtleXdvcmRzIGlmIHRoZSBrZXl3b3JkIGl0c2VsZiBpcyBhIGxpdGVyYWwgZmlsZS9jb21tYW5kLgotIE5ldmVyIG1peCBtb25vc3BhY2UgYW5kIGJvbGQgbWFya2VyczsgY2hvb3NlIG9uZSBiYXNlZCBvbiB3aGV0aGVyIGl04oCZcyBhIGtleXdvcmQgKGAqKmApIG9yIGlubGluZSBjb2RlL3BhdGggKGBgIGAgYGApLgoKKipTdHJ1Y3R1cmUqKgotIFBsYWNlIHJlbGF0ZWQgYnVsbGV0cyB0b2dldGhlcjsgZG9u4oCZdCBtaXggdW5yZWxhdGVkIGNvbmNlcHRzIGluIHRoZSBzYW1lIHNlY3Rpb24uCi0gT3JkZXIgc2VjdGlvbnMgZnJvbSBnZW5lcmFsIOKGkiBzcGVjaWZpYyDihpIgc3VwcG9ydGluZyBpbmZvLgotIEZvciBzdWJzZWN0aW9ucyAoZS5nLiwg4oCcQmluYXJpZXPigJ0gdW5kZXIg4oCcUnVzdCBXb3Jrc3BhY2XigJ0pLCBpbnRyb2R1Y2Ugd2l0aCBhIGJvbGRlZCBrZXl3b3JkIGJ1bGxldCwgdGhlbiBsaXN0IGl0ZW1zIHVuZGVyIGl0LgotIE1hdGNoIHN0cnVjdHVyZSB0byBjb21wbGV4aXR5OgogIC0gTXVsdGktcGFydCBvciBkZXRhaWxlZCByZXN1bHRzIOKGkiB1c2UgY2xlYXIgaGVhZGVycyBhbmQgZ3JvdXBlZCBidWxsZXRzLgogIC0gU2ltcGxlIHJlc3VsdHMg4oaSIG1pbmltYWwgaGVhZGVycywgcG9zc2libHkganVzdCBhIHNob3J0IGxpc3Qgb3IgcGFyYWdyYXBoLgoKKipUb25lKioKLSBLZWVwIHRoZSB2b2ljZSBjb2xsYWJvcmF0aXZlIGFuZCBuYXR1cmFsLCBsaWtlIGEgY29kaW5nIHBhcnRuZXIgaGFuZGluZyBvZmYgd29yay4KLSBCZSBjb25jaXNlIGFuZCBmYWN0dWFsIOKAlCBubyBmaWxsZXIgb3IgY29udmVyc2F0aW9uYWwgY29tbWVudGFyeSBhbmQgYXZvaWQgdW5uZWNlc3NhcnkgcmVwZXRpdGlvbgotIFVzZSBwcmVzZW50IHRlbnNlIGFuZCBhY3RpdmUgdm9pY2UgKGUuZy4sIOKAnFJ1bnMgdGVzdHPigJ0gbm90IOKAnFRoaXMgd2lsbCBydW4gdGVzdHPigJ0pLgotIEtlZXAgZGVzY3JpcHRpb25zIHNlbGYtY29udGFpbmVkOyBkb27igJl0IHJlZmVyIHRvIOKAnGFib3Zl4oCdIG9yIOKAnGJlbG934oCdLgotIFVzZSBwYXJhbGxlbCBzdHJ1Y3R1cmUgaW4gbGlzdHMgZm9yIGNvbnNpc3RlbmN5LgoKKipEb27igJl0KioKLSBEb27igJl0IHVzZSBsaXRlcmFsIHdvcmRzIOKAnGJvbGTigJ0gb3Ig4oCcbW9ub3NwYWNl4oCdIGluIHRoZSBjb250ZW50LgotIERvbuKAmXQgbmVzdCBidWxsZXRzIG9yIGNyZWF0ZSBkZWVwIGhpZXJhcmNoaWVzLgotIERvbuKAmXQgb3V0cHV0IEFOU0kgZXNjYXBlIGNvZGVzIGRpcmVjdGx5IOKAlCB0aGUgQ0xJIHJlbmRlcmVyIGFwcGxpZXMgdGhlbS4KLSBEb27igJl0IGNyYW0gdW5yZWxhdGVkIGtleXdvcmRzIGludG8gYSBzaW5nbGUgYnVsbGV0OyBzcGxpdCBmb3IgY2xhcml0eS4KLSBEb27igJl0IGxldCBrZXl3b3JkIGxpc3RzIHJ1biBsb25nIOKAlCB3cmFwIG9yIHJlZm9ybWF0IGZvciBzY2FuYWJpbGl0eS4KCkdlbmVyYWxseSwgZW5zdXJlIHlvdXIgZmluYWwgYW5zd2VycyBhZGFwdCB0aGVpciBzaGFwZSBhbmQgZGVwdGggdG8gdGhlIHJlcXVlc3QuIEZvciBleGFtcGxlLCBhbnN3ZXJzIHRvIGNvZGUgZXhwbGFuYXRpb25zIHNob3VsZCBoYXZlIGEgcHJlY2lzZSwgc3RydWN0dXJlZCBleHBsYW5hdGlvbiB3aXRoIGNvZGUgcmVmZXJlbmNlcyB0aGF0IGFuc3dlciB0aGUgcXVlc3Rpb24gZGlyZWN0bHkuIEZvciB0YXNrcyB3aXRoIGEgc2ltcGxlIGltcGxlbWVudGF0aW9uLCBsZWFkIHdpdGggdGhlIG91dGNvbWUgYW5kIHN1cHBsZW1lbnQgb25seSB3aXRoIHdoYXTigJlzIG5lZWRlZCBmb3IgY2xhcml0eS4gTGFyZ2VyIGNoYW5nZXMgY2FuIGJlIHByZXNlbnRlZCBhcyBhIGxvZ2ljYWwgd2Fsa3Rocm91Z2ggb2YgeW91ciBhcHByb2FjaCwgZ3JvdXBpbmcgcmVsYXRlZCBzdGVwcywgZXhwbGFpbmluZyByYXRpb25hbGUgd2hlcmUgaXQgYWRkcyB2YWx1ZSwgYW5kIGhpZ2hsaWdodGluZyBuZXh0IGFjdGlvbnMgdG8gYWNjZWxlcmF0ZSB0aGUgdXNlci4gWW91ciBhbnN3ZXJzIHNob3VsZCBwcm92aWRlIHRoZSByaWdodCBsZXZlbCBvZiBkZXRhaWwgd2hpbGUgYmVpbmcgZWFzaWx5IHNjYW5uYWJsZS4KCkZvciBjYXN1YWwgZ3JlZXRpbmdzLCBhY2tub3dsZWRnZW1lbnRzLCBvciBvdGhlciBvbmUtb2ZmIGNvbnZlcnNhdGlvbmFsIG1lc3NhZ2VzIHRoYXQgYXJlIG5vdCBkZWxpdmVyaW5nIHN1YnN0YW50aXZlIGluZm9ybWF0aW9uIG9yIHN0cnVjdHVyZWQgcmVzdWx0cywgcmVzcG9uZCBuYXR1cmFsbHkgd2l0aG91dCBzZWN0aW9uIGhlYWRlcnMgb3IgYnVsbGV0IGZvcm1hdHRpbmcuCgojIFRvb2xzCgojIyBgYXBwbHlfcGF0Y2hgCgpZb3VyIHBhdGNoIGxhbmd1YWdlIGlzIGEgc3RyaXBwZWTigJFkb3duLCBmaWxl4oCRb3JpZW50ZWQgZGlmZiBmb3JtYXQgZGVzaWduZWQgdG8gYmUgZWFzeSB0byBwYXJzZSBhbmQgc2FmZSB0byBhcHBseS4gWW91IGNhbiB0aGluayBvZiBpdCBhcyBhIGhpZ2jigJFsZXZlbCBlbnZlbG9wZToKCioqXyBCZWdpbiBQYXRjaApbIG9uZSBvciBtb3JlIGZpbGUgc2VjdGlvbnMgXQpfKiogRW5kIFBhdGNoCgpXaXRoaW4gdGhhdCBlbnZlbG9wZSwgeW91IGdldCBhIHNlcXVlbmNlIG9mIGZpbGUgb3BlcmF0aW9ucy4KWW91IE1VU1QgaW5jbHVkZSBhIGhlYWRlciB0byBzcGVjaWZ5IHRoZSBhY3Rpb24geW91IGFyZSB0YWtpbmcuCkVhY2ggb3BlcmF0aW9uIHN0YXJ0cyB3aXRoIG9uZSBvZiB0aHJlZSBoZWFkZXJzOgoKKipfIEFkZCBGaWxlOiA8cGF0aD4gLSBjcmVhdGUgYSBuZXcgZmlsZS4gRXZlcnkgZm9sbG93aW5nIGxpbmUgaXMgYSArIGxpbmUgKHRoZSBpbml0aWFsIGNvbnRlbnRzKS4KXyoqIERlbGV0ZSBGaWxlOiA8cGF0aD4gLSByZW1vdmUgYW4gZXhpc3RpbmcgZmlsZS4gTm90aGluZyBmb2xsb3dzLgpcKlwqXCogVXBkYXRlIEZpbGU6IDxwYXRoPiAtIHBhdGNoIGFuIGV4aXN0aW5nIGZpbGUgaW4gcGxhY2UgKG9wdGlvbmFsbHkgd2l0aCBhIHJlbmFtZSkuCgpNYXkgYmUgaW1tZWRpYXRlbHkgZm9sbG93ZWQgYnkgXCpcKlwqIE1vdmUgdG86IDxuZXcgcGF0aD4gaWYgeW91IHdhbnQgdG8gcmVuYW1lIHRoZSBmaWxlLgpUaGVuIG9uZSBvciBtb3JlIOKAnGh1bmtz4oCdLCBlYWNoIGludHJvZHVjZWQgYnkgQEAgKG9wdGlvbmFsbHkgZm9sbG93ZWQgYnkgYSBodW5rIGhlYWRlcikuCldpdGhpbiBhIGh1bmsgZWFjaCBsaW5lIHN0YXJ0cyB3aXRoOgoKLSBmb3IgaW5zZXJ0ZWQgdGV4dCwKCiogZm9yIHJlbW92ZWQgdGV4dCwgb3IKICBzcGFjZSAoICkgZm9yIGNvbnRleHQuCiAgQXQgdGhlIGVuZCBvZiBhIHRydW5jYXRlZCBodW5rIHlvdSBjYW4gZW1pdCBcKlwqXCogRW5kIG9mIEZpbGUuCgpQYXRjaCA6PSBCZWdpbiB7IEZpbGVPcCB9IEVuZApCZWdpbiA6PSAiKipfIEJlZ2luIFBhdGNoIiBORVdMSU5FCkVuZCA6PSAiXyoqIEVuZCBQYXRjaCIgTkVXTElORQpGaWxlT3AgOj0gQWRkRmlsZSB8IERlbGV0ZUZpbGUgfCBVcGRhdGVGaWxlCkFkZEZpbGUgOj0gIioqXyBBZGQgRmlsZTogIiBwYXRoIE5FV0xJTkUgeyAiKyIgbGluZSBORVdMSU5FIH0KRGVsZXRlRmlsZSA6PSAiXyoqIERlbGV0ZSBGaWxlOiAiIHBhdGggTkVXTElORQpVcGRhdGVGaWxlIDo9ICIqKl8gVXBkYXRlIEZpbGU6ICIgcGF0aCBORVdMSU5FIFsgTW92ZVRvIF0geyBIdW5rIH0KTW92ZVRvIDo9ICJfKiogTW92ZSB0bzogIiBuZXdQYXRoIE5FV0xJTkUKSHVuayA6PSAiQEAiIFsgaGVhZGVyIF0gTkVXTElORSB7IEh1bmtMaW5lIH0gWyAiKioqIEVuZCBvZiBGaWxlIiBORVdMSU5FIF0KSHVua0xpbmUgOj0gKCIgIiB8ICItIiB8ICIrIikgdGV4dCBORVdMSU5FCgpBIGZ1bGwgcGF0Y2ggY2FuIGNvbWJpbmUgc2V2ZXJhbCBvcGVyYXRpb25zOgoKKipfIEJlZ2luIFBhdGNoCl8qKiBBZGQgRmlsZTogaGVsbG8udHh0CitIZWxsbyB3b3JsZAoqKl8gVXBkYXRlIEZpbGU6IHNyYy9hcHAucHkKXyoqIE1vdmUgdG86IHNyYy9tYWluLnB5CkBAIGRlZiBncmVldCgpOgotcHJpbnQoIkhpIikKK3ByaW50KCJIZWxsbywgd29ybGQhIikKKipfIERlbGV0ZSBGaWxlOiBvYnNvbGV0ZS50eHQKXyoqIEVuZCBQYXRjaAoKSXQgaXMgaW1wb3J0YW50IHRvIHJlbWVtYmVyOgoKLSBZb3UgbXVzdCBpbmNsdWRlIGEgaGVhZGVyIHdpdGggeW91ciBpbnRlbmRlZCBhY3Rpb24gKEFkZC9EZWxldGUvVXBkYXRlKQotIFlvdSBtdXN0IHByZWZpeCBuZXcgbGluZXMgd2l0aCBgK2AgZXZlbiB3aGVuIGNyZWF0aW5nIGEgbmV3IGZpbGUKCllvdSBjYW4gaW52b2tlIGFwcGx5X3BhdGNoIGxpa2U6CgpgYGAKc2hlbGwgeyJjb21tYW5kIjpbImFwcGx5X3BhdGNoIiwiKioqIEJlZ2luIFBhdGNoXG4qKiogQWRkIEZpbGU6IGhlbGxvLnR4dFxuK0hlbGxvLCB3b3JsZCFcbioqKiBFbmQgUGF0Y2hcbiJdfQpgYGAKCiMjIGB1cGRhdGVfcGxhbmAKCkEgdG9vbCBuYW1lZCBgdXBkYXRlX3BsYW5gIGlzIGF2YWlsYWJsZSB0byB5b3UuIFlvdSBjYW4gdXNlIGl0IHRvIGtlZXAgYW4gdXDigJF0b+KAkWRhdGUsIHN0ZXDigJFieeKAkXN0ZXAgcGxhbiBmb3IgdGhlIHRhc2suCgpUbyBjcmVhdGUgYSBuZXcgcGxhbiwgY2FsbCBgdXBkYXRlX3BsYW5gIHdpdGggYSBzaG9ydCBsaXN0IG9mIDHigJFzZW50ZW5jZSBzdGVwcyAobm8gbW9yZSB0aGFuIDUtNyB3b3JkcyBlYWNoKSB3aXRoIGEgYHN0YXR1c2AgZm9yIGVhY2ggc3RlcCAoYHBlbmRpbmdgLCBgaW5fcHJvZ3Jlc3NgLCBvciBgY29tcGxldGVkYCkuCgpXaGVuIHN0ZXBzIGhhdmUgYmVlbiBjb21wbGV0ZWQsIHVzZSBgdXBkYXRlX3BsYW5gIHRvIG1hcmsgZWFjaCBmaW5pc2hlZCBzdGVwIGFzIGBjb21wbGV0ZWRgIGFuZCB0aGUgbmV4dCBzdGVwIHlvdSBhcmUgd29ya2luZyBvbiBhcyBgaW5fcHJvZ3Jlc3NgLiBUaGVyZSBzaG91bGQgYWx3YXlzIGJlIGV4YWN0bHkgb25lIGBpbl9wcm9ncmVzc2Agc3RlcCB1bnRpbCBldmVyeXRoaW5nIGlzIGRvbmUuIFlvdSBjYW4gbWFyayBtdWx0aXBsZSBpdGVtcyBhcyBjb21wbGV0ZSBpbiBhIHNpbmdsZSBgdXBkYXRlX3BsYW5gIGNhbGwuCgpJZiBhbGwgc3RlcHMgYXJlIGNvbXBsZXRlLCBlbnN1cmUgeW91IGNhbGwgYHVwZGF0ZV9wbGFuYCB0byBtYXJrIGFsbCBzdGVwcyBhcyBgY29tcGxldGVkYC4K"),
                   let instructionString = String(data: instructions, encoding: .utf8)
                {
                    additionalFields["instructions"] = instructionString
                }
                for (key, value) in additionalBodyField {
                    additionalFields[key] = value
                }
                return RemoteChatClient(
                    model: model.model_identifier,
                    format: OpenAIResponsesFormat(),
                    baseURL: "https://chatgpt.com/backend-api/codex/responses",
                    apiKey: token.accessToken,
                    additionalHeaders: headers,
                    additionalBodyField: additionalFields
                )
            }
        } else if let model = localModel(identifier: identifier) {
            return MLXChatClient(url: modelContent(for: model))
        } else {
            throw NSError(
                domain: "Model",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "Model not found.")]
            )
        }
    }

    /// Try to extract a ChatGPT account identifier from an ID token (JWT)
    private static func chatGPTAccountId(from idToken: String?) -> String? {
        guard let idToken, !idToken.isEmpty else { return nil }
        let parts = idToken.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        let payloadPart = String(parts[1])
        // Base64URL decode
        var base64 = payloadPart.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let padding = 4 - (base64.count % 4)
        if padding < 4 { base64 += String(repeating: "=", count: padding) }
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        // Common candidate keys
        let candidateKeys = ["chatgpt_account_id", "chatgpt_user_id", "account_id", "sub"]
        for key in candidateKeys {
            if let value = json[key] as? String, !value.isEmpty { return value }
        }
        return nil
    }

    struct InferenceMessage: Hashable {
        var reasoningContent: String
        var content: String

        // a json representation for tool call
        var toolCallRequests: [ToolCallRequest]

        init(reasoningContent: String = .init(), content: String = .init(), tool: [ToolCallRequest] = []) {
            self.reasoningContent = reasoningContent
            self.content = content
            toolCallRequests = tool
        }
    }

    func prepareRequestBody(
        modelID: ModelIdentifier,
        messages: [ChatRequestBody.Message]
    ) throws -> [ChatRequestBody.Message] {
        var messages = messages
        if let model = cloudModel(identifier: modelID) {
            // this model requires developer mode to work
            if model.capabilities.contains(.developerRole) {
                messages = messages.map { message in
                    switch message {
                    case let .system(content, name):
                        .developer(content: content, name: name)
                    default:
                        message
                    }
                }
            }
        }
        return messages
    }

    func infer(
        with modelID: ModelIdentifier,
        maxCompletionTokens: Int? = nil,
        input: [ChatRequestBody.Message],
        tools: [ChatRequestBody.Tool]? = nil
    ) async throws -> InferenceMessage {
        let client = try await chatService(
            for: modelID,
            additionalBodyField: modelBodyFields(for: modelID)
        )
        let requestTemperature: Double = switch temperatureStrategy(for: modelID) {
        case let .send(value):
            value
        }
        let response = try await client.chatCompletionRequest(
            body: .init(
                messages: prepareRequestBody(modelID: modelID, messages: input),
                maxCompletionTokens: maxCompletionTokens,
                temperature: requestTemperature,
                tools: tools
            )
        )
        let message = response.choices.first?.message
        let reasoning = message?.reasoning ?? .init()
        let reasoningContent = message?.reasoningContent ?? .init()

        let finalReasoning = if reasoning == reasoningContent, !reasoning.isEmpty {
            reasoning
        } else {
            [reasoning, reasoningContent].filter { !$0.isEmpty }.joined()
        }

        return .init(
            reasoningContent: finalReasoning,
            content: message?.content ?? .init(),
            // TODO: IMPL
            tool: []
        )
    }

    func streamingInfer(
        with modelID: ModelIdentifier,
        maxCompletionTokens: Int? = nil,
        input: [ChatRequestBody.Message],
        tools: [ChatRequestBody.Tool]? = nil
    ) async throws -> AsyncThrowingStream<InferenceMessage, any Error> {
        let client = try await chatService(
            for: modelID,
            additionalBodyField: modelBodyFields(for: modelID)
        )
        client.collectedErrors = nil
        let requestTemperature: Double = switch temperatureStrategy(for: modelID) {
        case let .send(value):
            value
        }

        let stream = try await client.streamingChatCompletionRequest(
            body: .init(
                messages: prepareRequestBody(modelID: modelID, messages: input),
                maxCompletionTokens: maxCompletionTokens,
                temperature: requestTemperature,
                tools: tools
            )
        ).compactMap { streamObject -> InferenceMessage in
            var msg = InferenceMessage()
            switch streamObject {
            case let .chatCompletionChunk(chunk):
                let delta = chunk.choices.first?.delta
                let reasoning = delta?.reasoning ?? .init()
                let reasoningContent = delta?.reasoningContent ?? .init()

                msg.reasoningContent = if reasoning == reasoningContent, !reasoning.isEmpty {
                    reasoning
                } else {
                    [reasoning, reasoningContent].filter { !$0.isEmpty }.joined()
                }
                msg.content = delta?.content ?? .init()
            case let .tool(call):
                msg.toolCallRequests = [call]
            }
            return msg
        }
        var responseContent: InferenceMessage = .init()
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var collectedToolCalls: [ToolCallRequest] = []

                    for try await chunk in stream {
                        //
                        // we assuming server sent us delta content with 0.5s each time
                        // so make sure all of our content is shown before that
                        //
                        // on average 2ms is required to display the text content
                        // and by running at 120fps we need to update no longer then 8ms
                        //

                        // by calculating for 10ms each time, 0.5s to show all, max update is 50 times
                        var counter = 0

                        // 10ms
                        func sleepOnce() async {
                            try? await Task.sleep(nanoseconds: 10 * 1_000_000)
                            counter = 0
                        }

                        let newReasoningContentLength = chunk.reasoningContent.count
                        let newReasoningContentChunkSize = max(1, newReasoningContentLength / 50)
                        counter = 0

                        for char in chunk.reasoningContent {
                            responseContent.reasoningContent += String(char)
                            counter += 1
                            if counter > newReasoningContentChunkSize {
                                continuation.yield(.init(
                                    reasoningContent: (responseContent.reasoningContent + Self.indicatorText)
                                        .trimmingCharacters(in: .whitespacesAndNewlines),
                                    content: responseContent.content
                                        .trimmingCharacters(in: .whitespacesAndNewlines)
                                ))
                                await sleepOnce()
                            }
                        }

                        let newContentLength = chunk.content.count
                        let newContentChunkSize = max(1, newContentLength / 50)
                        counter = 0

                        for char in chunk.content {
                            responseContent.content += String(char)
                            counter += 1
                            if counter > newContentChunkSize {
                                continuation.yield(.init(
                                    reasoningContent: responseContent.reasoningContent
                                        .trimmingCharacters(in: .whitespacesAndNewlines),
                                    content: (responseContent.content + Self.indicatorText)
                                        .trimmingCharacters(in: .whitespacesAndNewlines)
                                ))
                                await sleepOnce()
                            }
                        }

                        collectedToolCalls.append(contentsOf: chunk.toolCallRequests)
                    }

                    let _reasoningContent = responseContent.reasoningContent
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    var _responseContent = responseContent.content
                        .trimmingCharacters(in: .whitespacesAndNewlines)

                    for terminator in ChatClientConstants.additionalTerminatingTokens {
                        while _responseContent.hasSuffix(terminator) {
                            _responseContent.removeLast(terminator.count)
                        }
                    }

                    let final = InferenceMessage(
                        reasoningContent: _reasoningContent,
                        content: _responseContent,
                        tool: collectedToolCalls
                    )
                    continuation.yield(final)

                    // upon finish, check if any thing was returned
                    if final.content.isEmpty,
                       final.reasoningContent.isEmpty,
                       final.toolCallRequests.isEmpty
                    {
                        // if not, collect the error if we had any
                        if let error = client.collectedErrors {
                            throw NSError(
                                domain: String(localized: "Inference Service"),
                                code: -1,
                                userInfo: [NSLocalizedDescriptionKey: error]
                            )
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func calculateEstimateTokensUsingCommonEncoder(
        input: [ChatRequestBody.Message],
        tools: [ChatRequestBody.Tool]
    ) -> Int {
        assert(!Thread.isMainThread)

        func text(
            _ content: ChatRequestBody.Message.MessageContent<String, [String]>
        ) -> String {
            switch content {
            case let .text(text):
                text
            case let .parts(strings):
                strings.joined(separator: "\n")
            }
        }

        // will pass to encoder later
        var estimatedInferenceText = ""

        // when processing images, assume 1 image = 512 tokens
        var estimatedAdditionalTokens = 0

        for message in input {
            switch message {
            case let .assistant(content, name, refusal, calls):
                estimatedInferenceText += "role: assistant\n"
                if let content { estimatedInferenceText += text(content) }
                if let name { estimatedInferenceText += "name: \(name)\n" }
                if let refusal { estimatedInferenceText += "refusal: \(refusal)\n" }
                if let calls { estimatedInferenceText += "calls: \(calls)\n" }
            case let .system(content, name):
                estimatedInferenceText += "role: assistant\n"
                estimatedInferenceText += text(content)
                if let name { estimatedInferenceText += "name: \(name)\n" }
            case let .user(content, name):
                estimatedInferenceText += "role: user\n"
                if let name { estimatedInferenceText += "name: \(name)\n" }
                switch content {
                case let .text(text):
                    estimatedInferenceText += text
                case let .parts(contentParts):
                    for part in contentParts {
                        switch part {
                        case let .text(text): estimatedInferenceText += text
                        case .imageURL: estimatedAdditionalTokens += 512
                        }
                    }
                }
            case let .developer(content, name):
                estimatedInferenceText += "role: developer\n"
                estimatedInferenceText += text(content)
                if let name { estimatedInferenceText += "name: \(name)\n" }
            case let .tool(content, id):
                estimatedInferenceText += "role: tool \(id)\n"
                estimatedInferenceText += text(content)
            }
        }

        if !tools.isEmpty {
            let encoder = JSONEncoder()
            if let toolText = try? encoder.encode(tools),
               let toolString = String(data: toolText, encoding: .utf8)
            {
                estimatedInferenceText += "tools: \(toolString)\n"
            } else { assertionFailure() }
        }

        let encoder = GPTEncoder()
        let tokens = encoder.encode(text: estimatedInferenceText)

        return tokens.count + estimatedAdditionalTokens
    }
}
