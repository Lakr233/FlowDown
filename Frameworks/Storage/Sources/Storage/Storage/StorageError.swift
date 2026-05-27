//
//  StorageError.swift
//  Storage
//

import Foundation

public enum StorageError: Error, LocalizedError, Equatable {
    case conversationNotFound(Conversation.ID)
    case cloudModelNotFound(CloudModel.ID)

    public var errorDescription: String? {
        switch self {
        case let .conversationNotFound(id):
            "Conversation not found: \(id)"
        case let .cloudModelNotFound(id):
            "CloudModel not found: \(id)"
        }
    }
}
