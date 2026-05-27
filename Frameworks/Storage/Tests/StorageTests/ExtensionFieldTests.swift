//
//  ExtensionFieldTests.swift
//  StorageTests
//
//  Coverage:
//  - ExtensionDictionary defaults / encode-decode round-trip / corrupted fallback
//  - CloudModel.ext_data / Conversation.ext_data fetch+save round-trip
//  - conversationExtDataPut: writes value, bumps modified, errors on missing id
//  - cloudModelExtDataPut: symmetric path
//

import Foundation
@testable import Storage
import Testing
import WCDBSwift

struct ExtensionFieldTests {
    @Test
    func `extension dictionary default is empty`() {
        let d = ExtensionDictionary()
        #expect(d.isEmpty)
    }

    @Test
    func `extension dictionary column codable round trip`() {
        var d = ExtensionDictionary()
        d["foo"] = "bar"
        d["chat_client_kit"] = #"{"x":1}"#

        let value = d.archivedValue()
        let restored = ExtensionDictionary(with: value)
        #expect(restored?.storage == d.storage)
    }

    @Test
    func `extension dictionary falls back to empty on corrupted text`() {
        let bad: WCDBSwift.Value = .init("not a plist 这就是垃圾 ##")
        let restored = ExtensionDictionary(with: bad)
        #expect(restored != nil)
        #expect(restored?.isEmpty == true)
    }

    @Test
    func `extension dictionary falls back to empty on empty text`() {
        let empty: WCDBSwift.Value = .init("")
        let restored = ExtensionDictionary(with: empty)
        #expect(restored != nil)
        #expect(restored?.isEmpty == true)
    }

    @Test
    func `conversation ext_data persists across fetch`() throws {
        try StorageTestSupport.withTemporaryStorage { sdb in
            let conv = sdb.conversationMake { _ in }
            try sdb.conversationExtDataPut(
                id: conv.objectId,
                key: ExtensionKey.chatClientKit,
                value: #"{"cursor":42}"#
            )
            let refreshed = sdb.conversationWith(identifier: conv.objectId)
            #expect(
                refreshed?.ext_data[ExtensionKey.chatClientKit] == #"{"cursor":42}"#
            )
        }
    }

    @Test
    func `conversationExtDataPut bumps modified`() throws {
        try StorageTestSupport.withTemporaryStorage { sdb in
            let conv = sdb.conversationMake { _ in }
            let originalModified = conv.modified
            Thread.sleep(forTimeInterval: 0.01)

            try sdb.conversationExtDataPut(
                id: conv.objectId,
                key: ExtensionKey.chatClientKit,
                value: "hello"
            )

            let refreshed = sdb.conversationWith(identifier: conv.objectId)
            #expect(refreshed != nil)
            #expect((refreshed?.modified ?? Date.distantPast) > originalModified)
        }
    }

    @Test
    func `conversationExtDataPut throws on missing id`() throws {
        try StorageTestSupport.withTemporaryStorage { sdb in
            #expect(throws: StorageError.conversationNotFound("non-existent-id")) {
                try sdb.conversationExtDataPut(
                    id: "non-existent-id",
                    key: ExtensionKey.chatClientKit,
                    value: "x"
                )
            }
        }
    }

    @Test
    func `conversationExtDataPut nil value deletes key`() throws {
        try StorageTestSupport.withTemporaryStorage { sdb in
            let conv = sdb.conversationMake { _ in }
            try sdb.conversationExtDataPut(
                id: conv.objectId, key: "tmp", value: "x"
            )
            try sdb.conversationExtDataPut(
                id: conv.objectId, key: "tmp", value: nil
            )
            let refreshed = sdb.conversationWith(identifier: conv.objectId)
            #expect(refreshed?.ext_data["tmp"] == nil)
        }
    }

    @Test
    func `cloudModelExtDataPut round trip`() throws {
        try StorageTestSupport.withTemporaryStorage { sdb in
            let model = CloudModel(deviceId: Storage.deviceId, name: "test")
            try sdb.cloudModelPut(model)

            try sdb.cloudModelExtDataPut(
                id: model.objectId,
                key: ExtensionKey.chatClientKitScripts,
                value: "plist string here"
            )

            let refreshed = sdb.cloudModel(with: model.objectId)
            #expect(
                refreshed?.ext_data[ExtensionKey.chatClientKitScripts] == "plist string here"
            )
        }
    }

    @Test
    func `cloudModelExtDataPut throws on missing id`() throws {
        try StorageTestSupport.withTemporaryStorage { sdb in
            #expect(throws: StorageError.cloudModelNotFound("missing")) {
                try sdb.cloudModelExtDataPut(
                    id: "missing",
                    key: "k",
                    value: "v"
                )
            }
        }
    }
}
