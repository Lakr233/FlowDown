//
//  Storage+CloudModel.swift
//  Storage
//
//  Created by 秋星桥 on 1/28/25.
//

import Foundation
import WCDBSwift

public extension Storage {
    func cloudModelList() -> [CloudModel] {
        (
            try? db.getObjects(
                fromTable: CloudModel.tableName,
                where: CloudModel.Properties.removed == false,
                orderBy: [
                    CloudModel.Properties.model_identifier
                        .order(.ascending),
                ],
            ),
        ) ?? []
    }

    func cloudModelPut(_ object: CloudModel) throws {
        try cloudModelPut(objects: [object])
    }

    func cloudModelPut(objects: [CloudModel]) throws {
        guard !objects.isEmpty else {
            return
        }

        try putSyncable(objects)
    }

    func cloudModel(with identifier: CloudModel.ID) -> CloudModel? {
        try? db.getObject(
            fromTable: CloudModel.tableName,
            where: CloudModel.Properties.objectId == identifier && CloudModel.Properties.removed == false,
        )
    }

    func cloudModelEdit(identifier: CloudModel.ID, _ block: @escaping (inout CloudModel) -> Void) {
        let read: CloudModel? = try? db.getObject(
            fromTable: CloudModel.tableName,
            where: CloudModel.Properties.objectId == identifier,
        )
        guard var object = read else { return }
        block(&object)
        try? cloudModelPut(objects: [object])
    }

    func cloudModelRemove(identifier: CloudModel.ID) {
        let object: CloudModel? = try? db.getObject(
            fromTable: CloudModel.tableName,
            where: CloudModel.Properties.objectId == identifier,
        )

        guard let object else { return }

        object.markModified()

        let update = StatementUpdate().update(table: CloudModel.tableName)
            .set(CloudModel.Properties.removed)
            .to(true)
            .set(CloudModel.Properties.modified)
            .to(object.modified)
            .where(CloudModel.Properties.objectId == identifier)

        try? db.exec(update)

        try? pendingUploadEnqueue(sources: [(object, .delete)])
    }
}
