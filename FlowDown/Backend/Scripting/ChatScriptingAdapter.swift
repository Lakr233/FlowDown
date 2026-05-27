//
//  ChatScriptingAdapter.swift
//  FlowDown
//
//  Bridges CloudModel + Conversation (Storage layer) → ChatScriptingHandle
//  (ChatClientKit layer). ChatClientKit itself does NOT depend on Storage —
//  this file is the only place the two cross.
//
//  Plan §8. Constraints baked in:
//  - manifest snapshot uses an explicit **whitelist** of CloudModel fields,
//    never blacklist (plan §1.10 / Round 2 codex HIGH #11). New
//    CloudModel sensitive fields will NOT leak automatically.
//  - writeContext routes through `sdb.conversationExtDataPut`, which
//    runs in its own short transaction and propagates errors.
//  - **Caller invariant**: makeHandle must NOT be invoked from inside
//    a WCDB transaction. saveContext synchronous wait + watchdog
//    will fatalError on lock inversion (plan §8.4).
//

import ChatClientKit
import Foundation
import Storage

enum ChatScriptingAdapter {
    /// Build a `ChatScriptingHandle` for a (model, conversation) pair.
    /// Returns `nil` if the model has no scripting config — caller passes
    /// nil to `streamingChat(body:scripting:)` and behaviour is identical
    /// to the no-scripting path.
    static func makeHandle(
        modelIdentifier: ModelManager.ModelIdentifier,
        conversationId: Conversation.ID
    ) -> ChatScriptingHandle? {
        guard let model = sdb.cloudModel(with: modelIdentifier) else {
            return nil
        }
        let rawConfig = model.ext_data[ExtensionKey.chatClientKitScripts] ?? ""
        guard let config = ChatClientKitScriptConfig.decodePList(rawConfig),
              config.hasAnyStage
        else { return nil }

        let modelId = model.objectId
        let manifest = makeManifest(from: model)

        let convId = conversationId
        return ChatScriptingHandle(
            conversationId: convId,
            config: config,
            manifest: manifest,
            readContext: {
                sdb.conversationWith(identifier: convId)?
                    .ext_data[ExtensionKey.chatClientKit] ?? ""
            },
            writeContext: { json in
                try sdb.conversationExtDataPut(
                    id: convId,
                    key: ExtensionKey.chatClientKit,
                    value: json
                )
                _ = modelId // referenced for future telemetry hookup
            }
        )
    }

    /// Explicit whitelist of CloudModel fields safe to expose to scripts.
    /// **Adding a new CloudModel field does NOT automatically expose it.**
    /// That is the point — default-deny prevents accidentally leaking new
    /// sensitive fields.
    private static func makeManifest(from model: CloudModel) -> ManifestSnapshot {
        let safe: AnyCodingValue = .object([
            "objectId": .string(model.objectId),
            "name": .string(model.name),
            "model_identifier": .string(model.model_identifier),
            "endpoint": .string(model.endpoint),
            "comment": .string(model.comment),
            "headers": .object(model.headers.mapValues { .string($0) }),
            "bodyFields": .string(model.bodyFields),
            "capabilities": .array(Array(model.capabilities).map { .string($0.rawValue) }),
            "context": .int(model.context.rawValue),
            "response_format": .string(model.response_format.rawValue),
            // token / api credentials: NEVER exported. Scripts in inherit=true
            // mode can still read the constructed Authorization header,
            // but manifest stays clean (plan §1.10 — redaction is hygiene,
            // not a security boundary).
        ])
        return ManifestSnapshot(payload: safe)
    }
}
