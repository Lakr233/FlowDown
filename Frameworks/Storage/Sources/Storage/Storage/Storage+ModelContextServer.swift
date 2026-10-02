//
//  Storage+ModelContextServer.swift
//  Storage
//
//  Created by LiBr on 6/29/25.
//

import Foundation
import WCDBSwift

public extension Storage {
    func modelContextServerList() -> [ModelContextServer] {
        (
            try? db.getObjects(
                fromTable: ModelContextServer.tableName,
                where: ModelContextServer.Properties.removed == false,
                orderBy: [
                    ModelContextServer.Properties.creation.order(.ascending),
                ],
            ),
        ) ?? []
    }

    typealias ModelContextServerMakeInitDataBlock = (ModelContextServer) -> Void
    func modelContextServerMake(_ block: ModelContextServerMakeInitDataBlock? = nil) -> ModelContextServer {
        let object = ModelContextServer()
        if let block {
            block(object)
        }

        object.creation = .now
        object.modified = object.creation

        try? runTransaction {
            try $0.insert([object], intoTable: ModelContextServer.tableName)
            try self.pendingUploadEnqueue(sources: [(object, .insert)], handle: $0)
        }
        return object
    }

    func modelContextServerPut(object: ModelContextServer) {
        modelContextServerPut(objects: [object])
    }

    func modelContextServerPut(objects: [ModelContextServer], skipSync: Bool = false) {
        guard !objects.isEmpty else {
            return
        }

        try? putSyncable(objects, restoreInsertModified: false, skipSync: skipSync)
    }

    func modelContextServerWith(_ identifier: ModelContextServer.ID) -> ModelContextServer? {
        try? db.getObject(
            fromTable: ModelContextServer.tableName,
            where: ModelContextServer.Properties.objectId == identifier
                && ModelContextServer.Properties.removed == false,
        )
    }

    func modelContextServerEdit(
        identifier: ModelContextServer.ID,
        skipSync: Bool = false,
        _ block: @escaping (inout ModelContextServer) -> Void
    ) {
        let read: ModelContextServer? = try? db.getObject(
            fromTable: ModelContextServer.tableName,
            where: ModelContextServer.Properties.objectId == identifier,
        )
        guard var object = read else { return }
        block(&object)
        modelContextServerPut(objects: [object], skipSync: skipSync)
    }

    func modelContextServerRemove(identifier: ModelContextServer.ID) {
        let object: ModelContextServer? = try? db.getObject(
            fromTable: ModelContextServer.tableName,
            where: ModelContextServer.Properties.objectId == identifier,
        )

        guard let object else {
            return
        }

        object.markModified()

        let update = StatementUpdate().update(table: ModelContextServer.tableName)
            .set(ModelContextServer.Properties.removed)
            .to(true)
            .set(ModelContextServer.Properties.modified)
            .to(object.modified)
            .where(ModelContextServer.Properties.objectId == identifier)

        try? db.exec(update)

        try? pendingUploadEnqueue(sources: [(object, .delete)])
    }
}
