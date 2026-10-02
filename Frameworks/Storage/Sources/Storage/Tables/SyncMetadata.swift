//
//  SyncMetadata.swift
//  Storage
//
//  Created by king on 2025/10/17.
//

import CloudKit
import Foundation
import WCDBSwift

package final class SyncMetadata: Identifiable, Codable, TableNamed, TableCodable {
    package static let tableName: String = "SyncMetadata"

    package var id: String {
        recordName
    }

    package var zoneName: String = .init()
    package var ownerName: String = .init()
    package var recordName: String = .init()
    package var lastKnownRecordData: Data?

    package var lastKnownRecord: CKRecord? {
        get {
            guard let lastKnownRecordData, !lastKnownRecordData.isEmpty else { return nil }
            do {
                let coder = try NSKeyedUnarchiver(forReadingFrom: lastKnownRecordData)
                let record = CKRecord(coder: coder)
                coder.finishDecoding()
                return record
            } catch {
                // swiftformat:disable:next redundantSelf
                Logger.database.errorFile("lastKnownRecordData unarchiver error zoneName:\(self.zoneName) ownerName:\(self.ownerName) recordName:\(self.recordName) \(error)")
                return nil
            }
        }

        set {
            guard let newValue else {
                lastKnownRecordData = nil
                return
            }

            let archiver = NSKeyedArchiver(requiringSecureCoding: true)
            newValue.encodeSystemFields(with: archiver)
            lastKnownRecordData = archiver.encodedData
        }
    }

    package enum CodingKeys: String, CodingTableKey {
        package typealias Root = SyncMetadata
        package static let objectRelationalMapping = TableBinding(CodingKeys.self) {
            BindColumnConstraint(zoneName, isNotNull: true)
            BindColumnConstraint(ownerName, isNotNull: true)
            BindColumnConstraint(recordName, isNotNull: true)
            BindColumnConstraint(lastKnownRecordData, isNotNull: false)

            BindIndex(
                recordName,
                zoneName,
                ownerName,
                namedWith: "_recordNameAndZoneNameAndOwnerNameIndex",
                isUnique: true
            )
        }

        case zoneName
        case ownerName
        case recordName
        case lastKnownRecordData
    }

    convenience init(record: CKRecord) {
        self.init()

        let recordID = record.recordID
        let zoneID = recordID.zoneID
        zoneName = zoneID.zoneName
        ownerName = zoneID.ownerName
        recordName = recordID.recordName
        lastKnownRecord = record
    }
}
