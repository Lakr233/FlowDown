//
//  Message+ReplyMetadata.swift
//  FlowDown
//
//  Created by GPT-5 Codex on 2025/11/05.
//

import Foundation
import Storage

extension Message {
    struct MetadataContainer: Codable, Equatable {
        var reply: ReplyMetadata?

        init(reply: ReplyMetadata? = nil) {
            self.reply = reply
        }
    }

    struct ReplyMetadata: Codable, Equatable {
        public var parentUserMessageId: Message.ID
        public var attemptIndex: Int
        public var isHistorical: Bool

        public init(parentUserMessageId: Message.ID, attemptIndex: Int, isHistorical: Bool) {
            self.parentUserMessageId = parentUserMessageId
            self.attemptIndex = attemptIndex
            self.isHistorical = isHistorical
        }
    }

    private static let metadataDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        return decoder
    }()

    private static let metadataEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    var replyMetadata: ReplyMetadata? {
        get { metadataContainer.reply }
        set {
            var container = metadataContainer
            container.reply = newValue
            updateMetadataContainer(container)
        }
    }

    var isHistoricalReply: Bool {
        replyMetadata?.isHistorical ?? false
    }

    private var metadataContainer: MetadataContainer {
        if let metadata,
           let container = try? Self.metadataDecoder.decode(MetadataContainer.self, from: metadata)
        {
            return container
        }
        return .init()
    }

    private func updateMetadataContainer(_ container: MetadataContainer) {
        let data = try? Self.metadataEncoder.encode(container)
        update(\.metadata, to: data)
    }
}
