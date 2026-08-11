//
//  Storage+Export.swift
//  FlowDown
//
//  Created by 秋星桥 on 2/5/25.
//

import Foundation
import Storage
import ZIPFoundation

/// Timestamp used to name exported archives and settings backups.
let exportTimestampFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter
}()

nonisolated extension Storage {
    func exportZipFile() -> Result<URL, Error> {
        let result = exportDatabase()
        switch result {
        case let .success(databaseOutput):
            let tempURL = FileManager.default
                .temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
            try? FileManager.default.createDirectory(
                at: tempURL,
                withIntermediateDirectories: true,
            )
            let zipURL = tempURL
                .appendingPathComponent(
                    String(
                        format: String(localized: "Exported Database %@"),
                        exportTimestampFormatter.string(from: Date()),
                    ),
                )
                .appendingPathExtension("zip")
            do {
                try FileManager.default.zipItem(at: databaseOutput, to: zipURL, shouldKeepParent: false)
                try? FileManager.default.removeItem(at: databaseOutput)
                return .success(zipURL)
            } catch {
                return .failure(error)
            }
        case let .failure(failure):
            return .failure(failure)
        }
    }
}
